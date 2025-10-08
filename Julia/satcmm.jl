# satcmm.jl
# Run satcmm and read the output with AdderGraphs

using AdderGraphs

function generate_satcmm_cmd(v::Vector{Int}; satcmm_right_shifts::Bool=true, satcmm_normalize_adder_graph::Bool=true, satcmm_max_num_adders::Int=0, satcmm_word_size::Int=0, satcmm_threads::Int=1, timelimit::T=0.0, kwargs...) where T <: Real
    return "sat_cmm "*join(v, ";")*" allow_post_adder_right_shift=$(Int(satcmm_right_shifts)) $(satcmm_max_num_adders > 0 ? "max_num_adders=$(satcmm_max_num_adders)" : "") $(satcmm_word_size > 0 ? "define_solver_word_size=$(satcmm_word_size)" : "") threads=$(satcmm_threads) $(timelimit > 0 ? "timeout=$(timelimit)" : "") normalize_adder_graph=$(Int(satcmm_normalize_adder_graph))"
end

function satcmmcall(satcmm_cmd::String; kwargs...)
    filename = tempname()
    argv = Vector{String}(string.(split(satcmm_cmd)))
    satcmm_success = true
    open(filename, "w") do fileout
        redirect_stderr(fileout) do
            cmd = run(`$(argv)`; wait=true)
            satcmm_success = success(cmd)
        end
    end
    return read(filename, String), satcmm_success
end


function satcmm(C::Vector{Int}; kwargs...)
    str_result, satcmm_success = satcmmcall(generate_satcmm_cmd(C; kwargs...); kwargs...)
    if !satcmm_success
        @warn "satcmm failed to produce an adder graph"
        return AdderGraph()
    end
    s = split(str_result, "\n")
    addergraph = read_addergraph(String(s[2][14:end]))
    return addergraph
end

