# run with timeout
# https://discourse.julialang.org/t/53876/3

function run_with_timeout(command; timeout::Int=0, kwargs...)
    if timeout == 0
        cmd = run(command; wait=true)
        return success(cmd)
    end
    cmd = run(command; wait=false)
    start_time = time_ns()
    while (time_ns()-start_time)*1e-9 < timeout
        if !process_running(cmd)
            return success(cmd)
        end
        sleep(1)
    end
    kill(cmd)
    return false
end
