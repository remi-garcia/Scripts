# warmstart.jl
# Take a model and force the warm start to apply completely

using JuMP

mutable struct VarWarmStartData
    var::VariableRef
    is_fixed::Bool
    lower_bound::Number
    upper_bound::Number
end

function store_model_data(model::Model)
    model_data = Vector{VarWarmStartData}()
    for var_curr in all_variables(model)
        lb::Float64 = -Inf
        if has_lower_bound(var_curr)
            lb = lower_bound(var_curr)
        end
        ub::Float64 = Inf
        if has_upper_bound(var_curr)
            ub = upper_bound(var_curr)
        end
        if is_fixed(var_curr)
            lb = fix_value(var_curr)
            ub = fix_value(var_curr)
        end
        push!(model_data, VarWarmStartData(var_curr, is_fixed(var_curr), lb, ub))
    end

    return model_data
end

function fix_warmstart!(model::Model)
    for var_curr in all_variables(model)
        if has_start_value(var_curr)
            fix(var_curr, start_value(var_curr), force=true)
        end
    end

    return model
end

function save_warmstart(model::Model)
    ws_values = Dict{VariableRef, Float64}()
    for var_curr in all_variables(model)
        var_val = value(var_curr)
        if is_integer(var_curr) || is_binary(var_curr)
            var_val = round(var_val)
        end
        ws_values[var_curr] = var_val
    end

    return ws_values
end

function reset_model!(model::Model, model_data::Vector{VarWarmStartData}, ws_values::Dict{VariableRef, Float64})
    for curr_var_data in model_data
        var_curr = curr_var_data.var
        if is_fixed(var_curr)
            unfix(var_curr)
        end
        if !isinf(curr_var_data.lower_bound)
            set_lower_bound(var_curr, curr_var_data.lower_bound)
        end
        if !isinf(curr_var_data.upper_bound)
            set_upper_bound(var_curr, curr_var_data.upper_bound)
        end
        if curr_var_data.is_fixed
            fix(var_curr, curr_var_data.lower_bound, force=true)
        end
        if haskey(ws_values, var_curr)
            set_start_value(var_curr, ws_values[var_curr])
        end
    end

    return model
end



function warmstart!(model::Model; warmstart_timelimit::T=60.0, kwargs...) where T <: Real
    model_data = store_model_data(model)
    timelimit = time_limit_sec(model)
    # Without a solution, the original start values are kept
    ws_values = Dict{VariableRef, Float64}()
    try
        fix_warmstart!(model)
        set_time_limit_sec(model, Float64(warmstart_timelimit))
        optimize!(model)
        if has_values(model)
            ws_values = save_warmstart(model)
        else
            @warn "warmstart: no solution with the start values fixed ($(termination_status(model))), start values kept"
        end
    finally
        reset_model!(model, model_data, ws_values)
        set_time_limit_sec(model, timelimit)
    end

    return model
end
