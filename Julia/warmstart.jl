# warmstart.jl
# Take a model and force the warm start to apply completely

using JuMP

mutable struct VarWarmStartData
    var_name::String
    is_fixed::Bool
    lower_bound::Number
    upper_bound::Number
end

function store_model_data(model::Model)
    model_data = Vector{VarWarmStartData}()
    all_variable_names = name.(all_variables(model))
    for var_name in all_variable_names
        var_curr = variable_by_name(model, var_name)
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
        push!(model_data, VarWarmStartData(var_name, is_fixed(var_curr), lb, ub))
    end

    return model_data
end

function fix_warmstart!(model::Model)
    all_variable_names = name.(all_variables(model))
    for var_name in all_variable_names
        var_curr = variable_by_name(model, var_name)
        if has_start_value(var_curr)
            fix(var_curr, start_value(var_curr), force=true)
        end
    end

    return model
end

function save_warmstart(model::Model)
    all_variable_names = sort!(name.(all_variables(model)))
    ws_values = Dict{String, Float64}()
    for var_name in all_variable_names
        var_curr = variable_by_name(model, var_name)
        var_val = value(var_curr)
        if is_integer(var_curr) || is_binary(var_curr)
            var_val = round(var_val)
        end
        ws_values[var_name] = var_val
    end

    return ws_values
end

function reset_model!(model::Model, model_data::Vector{VarWarmStartData}, ws_values::Dict{String, Float64})
    for curr_var_data in model_data
        var_name = curr_var_data.var_name
        var_curr = variable_by_name(model, var_name)
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

        set_start_value(var_curr, ws_values[var_name])
    end

    return model
end



function warmstart!(model::Model; warmstart_timelimit::Float64=60.0, kwargs...)
    model_data = store_model_data(model)
    fix_warmstart!(model)

    timelimit = 0.0
    if !isnothing(time_limit_sec(model))
        timelimit = time_limit_sec(model)
    end
    set_time_limit_sec(model, warmstart_timelimit.0)
    optimize!(model)

    ws_values = save_warmstart(model)
    reset_model!(model, model_data, ws_values)

    if timelimit > 0
        set_time_limit_sec(model, timelimit)
    end

    return model
end

warmstart!(model::Model; warmstart_timelimit::Int, kwargs...) = warmstart!(model; warmstart_timelimit=Float64(warmstart_timelimit), kwargs...)
