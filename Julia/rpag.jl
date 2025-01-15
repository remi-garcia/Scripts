# rpag.jl
# Run rpag and read the output with AdderGraphs

# Requirement: run_with_timeout
include("$(@__DIR__())/run_with_timeout.jl")

using AdderGraphs

function generate_rpag_cmd(v::Vector{Int}; with_register_cost::Bool=false, nb_extra_stages::Int=0, kwargs...)
    return "rpag $(with_register_cost ? "" : "--cost_model=hl_min_ad ")$(nb_extra_stages==0 ? "" : "--no_of_extra_stages=$(nb_extra_stages) ")"*join(v, " ")
end


function rpagcall(rpag_cmd::String; use_rpag_lib::Bool=false, kwargs...)
    filename = tempname()
    argv = Vector{String}(string.(split(rpag_cmd)))
    rpag_success = true
    open(filename, "w") do fileout
        redirect_stdout(fileout) do
            if use_rpag_lib
                ccall((:main, "librpag"), Cint, (Cint, Ptr{Ptr{UInt8}}), length(argv), argv)
                Base.Libc.flush_cstdio()
            else
                try
                    rpag_success = run_with_timeout(`$(argv)`; kwargs...)
                    rpag_success = true
                catch
                    rpag_success = false
                end
            end
        end
    end
    return read(filename, String), rpag_success
end


function rpag(C::Vector{Int}; kwargs...)
    if isempty(Base.Libc.Libdl.find_library("librpag"))
        @warn "librpag not found"
        return AdderGraph()
    end
    str_result, rpag_success = rpagcall(generate_rpag_cmd(C; kwargs...); kwargs...)
    # RPAG exit status is 1 even in case of success
    # if !rpag_success
    #     @warn "rpag failed to produce an adder graph"
    #     return AdderGraph()
    # end
    s = split(str_result, "\n")
    # Workaround
    if isempty(s) || (length(s) == 1 && isempty(s[1]))
        @warn "rpag failed to produce an adder graph"
        return AdderGraph()
    end
    addergraph_str = ""
    for val in s
        if startswith(val, "pipelined_adder_graph=")
            addergraph_str = string(split(val, "=")[2])
        end
    end
    addergraph = read_addergraph(addergraph_str)
    ag_outputs = get_outputs(addergraph)
    for c in C
        if c == 1
            push_output!(addergraph, 1)
        end
        if !(c in ag_outputs)
            @warn "rpag did not produce output value $(c)"
        end
    end
    return addergraph
end
