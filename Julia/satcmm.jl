# satcmm.jl
# Run satcmm and read the output with AdderGraphs

# Requirement: run_with_timeout
include("$(@__DIR__())/run_with_timeout.jl")

using AdderGraphs

function generate_satcmm_cmd(v::Vector{Int}; satcmm_right_shifts::Bool=true, satcmm_normalize_adder_graph::Bool=true, satcmm_max_num_adders::Int=0, satcmm_word_size::Int=0, satcmm_threads::Int=1, satcmm_timeout::Int=0, kwargs...)
    return "satcmm $(join(v, ";")) allow_post_adder_right_shift=$(Int(satcmm_right_shifts)) $(satcmm_max_num_adders > 0 ? "max_num_adders=$(satcmm_max_num_adders)" : "") $(satcmm_word_size > 0 ? "define_solver_word_size=$(satcmm_word_size)" : "") threads=$(satcmm_threads) $(satcmm_timeout > 0 ? "timeout=$(satcmm_timeout)" : "") normalize_adder_graph=$(Int(satcmm_normalize_adder_graph))"
end

function satcmmcall(satcmm_cmd::String; kwargs...)
    filename = tempname()
    argv = Vector{String}(string.(split(satcmm_cmd)))
    satcmm_success = true
    open(filename, "w") do fileout
        redirect_stdout(fileout) do
            redirect_stderr(fileout) do
                # timeout= is per SAT instance, timelimit bounds the whole call
                satcmm_success = run_with_timeout(pipeline(`$(argv)`; stderr=fileout); kwargs...)
            end
        end
    end
    return read(filename, String), satcmm_success
end


function satcmm(C::Vector{Int}; flag_optimal::Vector{Int}=Vector{Int}([0]), kwargs...)
    str_result, satcmm_success = satcmmcall(generate_satcmm_cmd(C; kwargs...); kwargs...)
    if !satcmm_success
        @warn "satcmm failed to produce an adder graph"
        return AdderGraph()
    end
    s = split(str_result, "\n")
    i = findfirst(startswith("Adder graph: "), s)
    j = findfirst(startswith("# Add optimal = "), s)
    if isnothing(i) || isnothing(j)
        @warn "satcmm failed to produce an adder graph"
        return AdderGraph()
    end
    addergraph = read_addergraph(string(chopprefix(s[i], "Adder graph: ")))
    flag_optimal[1] = parse(Int, chopprefix(s[j], "# Add optimal = "))
    return addergraph
end

