# hcub.jl
# Run hcub and read the output with AdderGraphs

# Requirement: run_with_timeout
include("$(@__DIR__())/run_with_timeout.jl")

using AdderGraphs

function generate_hcub_cmd(v::Vector{Int}; hcub_seed::Int=0, kwargs...)
    return "hcub "*join(v, " ")*" -v 1 -seed $(hcub_seed) -ga"
end


function hcubcall(hcub_cmd::String; kwargs...)
    filename = tempname()
    # hcub_cmd *= " > $(filename)"
    argv = Vector{String}(string.(split(hcub_cmd)))
    hcub_success = true
    open(filename, "w") do fileout
        redirect_stdout(fileout) do
            try
                hcub_success = run_with_timeout(`$(argv)`; kwargs...)
            catch
                hcub_success = false
            end
        end
    end
    return read(filename, String), hcub_success
end


function hcub(C::Vector{Int}; kwargs...)
    str_result, hcub_success = hcubcall(generate_hcub_cmd(C; kwargs...); kwargs...)
    if !hcub_success
        @warn "hcub failed to produce an adder graph"
        return AdderGraph()
    end
    # s = split(str_result, "\n")
    # addercost = length(s)-1
    # return addercost, 0
    addergraph = read_hcub_output(str_result, C)
    return addergraph
end
