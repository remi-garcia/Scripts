# hcub.jl
# Run hcub and read the output with AdderGraphs

using AdderGraphs

function generate_hcub_cmd(v::Vector{Int}; hcub_seed::Int=0, kwargs...)
    return "hcub "*join(v, " ")*" -v 1 -seed $(hcub_seed) -ga"
end


function hcubcall(hcub_cmd::String; kwargs...)
    filename = tempname()
    # hcub_cmd *= " > $(filename)"
    argv = Vector{String}(string.(split(hcub_cmd)))
    open(filename, "w") do fileout
        redirect_stdout(fileout) do
            try
                run(`$(argv)`)
            catch
            end
        end
    end
    return read(filename, String)
end


function hcub(C::Vector{Int}; kwargs...)
    str_result = hcubcall(generate_hcub_cmd(C; kwargs...); kwargs...)
    # s = split(str_result, "\n")
    # addercost = length(s)-1
    # return addercost, 0
    addergraph = read_hcub_output(str_result, C)
    return addergraph
end
