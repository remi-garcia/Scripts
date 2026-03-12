using JuMP
import MathOptInterface as MOI

import JuMP.all_constraints
function all_constraints(model::Model)
    cstr = Vector{ConstraintRef}()
    for (F, S) in list_of_constraint_types(model)
        append!(cstr, all_constraints(model, F, S))
    end
    return cstr
end
function all_constraints_affexpr(model::Model)
    cstr = Vector{ConstraintRef}()
    for (F, S) in list_of_constraint_types(model)
        if F == AffExpr
            append!(cstr, all_constraints(model, F, S))
        end
    end
    return cstr
end

# helper: check if term is "integral"
function is_integral_term(term::Tuple{Float64, VariableRef})
    coeff, var = term
    return isinteger(coeff) && (is_integer(var) || is_binary(var))
end


function decompose_linear_constraints!(model::Model; min_terms::Int=3, prefix::String="auxsum")
    # Collect linear constraints
    targets = all_constraints_affexpr(model)

    for cref in targets
        co = constraint_object(cref)
        f  = co.func
        set = co.set
        terms = f.terms
        if length(terms) < min_terms
            continue
        end
        pairs = [(coeff, var) for (var, coeff) in terms]
        pairs = sort(pairs, by = t -> is_integral_term(t) ? 0 : 1)
        n = length(pairs)
        aux = Vector{VariableRef}(undef, n - 1)
        cname = name(cref)
        base  = isempty(cname) ? prefix : "$(prefix)__$(cname)"

        # --- Build chain with partial-sum integrality ---
        partial_sum_is_integer = true

        # first aux: sum of first two terms
        if partial_sum_is_integer && all(is_integral_term, pairs[1:2])
            aux[1] = @variable(model, integer=true, base_name="$(base)__1")
        else
            aux[1] = @variable(model, base_name="$(base)__1")  # continuous
            partial_sum_is_integer = false
        end

        # subsequent aux
        for k in 2:(n-1)
            term = pairs[k+1]
            if partial_sum_is_integer && is_integral_term(term)
                aux[k] = @variable(model, integer=true, base_name="$(base)__$(k)")
            else
                aux[k] = @variable(model, base_name="$(base)__$(k)")
                partial_sum_is_integer = false
            end
        end

        # build equalities for the chain
        expr = pairs[1][1] * pairs[1][2] + pairs[2][1] * pairs[2][2]
        @constraint(model, expr == aux[1])
        for k in 3:n
            expr = aux[k - 2] + pairs[k][1] * pairs[k][2]
            @constraint(model, expr == aux[k - 1])
        end

        # final inequality/equality
        if set isa MOI.LessThan{Float64}
            @constraint(model, aux[end] <= normalized_rhs(cref))
        elseif set isa MOI.GreaterThan{Float64}
            @constraint(model, aux[end] >= normalized_rhs(cref))
        elseif set isa MOI.EqualTo{Float64}
            @constraint(model, aux[end] == normalized_rhs(cref))
        end

        # delete original
        delete(model, cref)
    end

    return model
end


function bigM_to_indicator!(model::Model; prefix::String="ind")
    # Collect linear constraints
    targets = all_constraints_affexpr(model)

    for cref in targets
        co = constraint_object(cref)
        f  = co.func
        set = co.set
        terms = f.terms
        pairs = [(coeff, var) for (var, coeff) in terms]
        cname = name(cref)
        base  = isempty(cname) ? prefix : "$(prefix)__$(cname)"
        bin_in_cst = filter(x->is_binary(x[2]), pairs)
        nobin_in_cst = filter(x->!is_binary(x[2]), pairs)
        nb_binvars = length(bin_in_cst)
        if nb_binvars == 0
            continue
        end
        aux = Vector{Vector{VariableRef}}(undef, nb_binvars)
        aux_coeffs = Vector{Vector{Float64}}(undef, nb_binvars)
        for i in 1:nb_binvars
            aux[i] = Vector{VariableRef}(undef, 2^i)
            aux_coeffs[i] = Vector{Float64}(undef, 2^i)
        end
        aux[1][1] = bin_in_cst[1][2]
        aux_coeffs[1][1] = bin_in_cst[1][1]
        aux[1][2] = @variable(model, binary=true, base_name="$(base)__$(1)_$(2)")
        @constraint(model, aux[1][2] == 1 - aux[1][1])
        aux_coeffs[1][2] = 0

        for i in 2:nb_binvars
            for j in 1:2^(i-1)
                curr_coeff = bin_in_cst[i][1]
                curr_var = bin_in_cst[i][2]
                # AND curr_var
                aux[i][j] = @variable(model, binary=true, base_name="$(base)__$(i)_$(j)")
                @constraint(model, aux[i][j] <= curr_var)
                @constraint(model, aux[i][j] <= aux[i-1][j])
                @constraint(model, aux[i][j] >= curr_var + aux[i-1][j] - 1)
                aux_coeffs[i][j] = aux_coeffs[i-1][j]+curr_coeff
                # AND NOT curr_var
                aux[i][2^(i-1)+j] = @variable(model, binary=true, base_name="$(base)__$(i)_$(2^(i-1)+j)")
                @constraint(model, aux[i][2^(i-1)+j] <= (1-curr_var))
                @constraint(model, aux[i][2^(i-1)+j] <= aux[i-1][j])
                @constraint(model, aux[i][2^(i-1)+j] >= (1-curr_var) + aux[i-1][j] - 1)
                aux_coeffs[i][2^(i-1)+j] = aux_coeffs[i-1][j]
            end
        end

        for j in 1:2^nb_binvars
            if set isa MOI.LessThan{Float64}
                @constraint(model, aux[nb_binvars][j] --> {sum(coeff*var for (coeff, var) in nobin_in_cst) + aux_coeffs[nb_binvars][j] <= normalized_rhs(cref)})
            elseif set isa MOI.GreaterThan{Float64}
                @constraint(model, aux[nb_binvars][j] --> {sum(coeff*var for (coeff, var) in nobin_in_cst) + aux_coeffs[nb_binvars][j] >= normalized_rhs(cref)})
            elseif set isa MOI.EqualTo{Float64}
                @constraint(model, aux[nb_binvars][j] --> {sum(coeff*var for (coeff, var) in nobin_in_cst) + aux_coeffs[nb_binvars][j] == normalized_rhs(cref)})
            end
        end

        # delete original
        delete(model, cref)
    end

    return model
end
