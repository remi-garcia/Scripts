# Scripts

Standalone helpers. The Julia files are not a package: `include` them from another project, whose environment provides the Julia packages listed below.

## Bash

- `Bash/run_vivado.sh`: synthesizes (and optionally implements and simulates) a VHDL design with Vivado and appends utilization, delay and power to a CSV file. Needs `vivado` on `PATH`. Run it from a scratch directory: the project, `results.csv` and `vivado_current_run.log` are written to the current directory. See `run_vivado.sh -h`.

## Julia

- `Julia/run_with_timeout.jl`: `run_with_timeout(cmd; timelimit)` runs an external command, returns `false` on a non-zero exit or when the time limit is reached. No dependency.
- `Julia/warmstart.jl`: `warmstart!(model)` solves the model with the start values fixed, then uses the solution as the start. Needs JuMP.
- `Julia/modify_models.jl`: `decompose_linear_constraints!` and `bigM_to_indicator!` reformulate the linear constraints of a JuMP model. Needs JuMP. Call `decompose_linear_constraints!` once per model: a second call decomposes the constraints created by the first and repeats variable names.
- `Julia/hcub.jl`: `hcub(C)` runs `hcub` and reads its output as an adder graph. Needs AdderGraphs, the `hcub` binary on `PATH`, and `run_with_timeout.jl` next to it.
- `Julia/rpag.jl`: `rpag(C)` runs `rpag` and reads its output as an adder graph. Needs AdderGraphs, the `rpag` binary on `PATH`, and `run_with_timeout.jl` next to it.
- `Julia/satcmm.jl`: `satcmm(C)` runs `satcmm` and reads its output as an adder graph; `timelimit` bounds the whole call, `satcmm_timeout` is satcmm's timeout per SAT instance. Needs AdderGraphs, the `satcmm` binary on `PATH`, and `run_with_timeout.jl` next to it.

AdderGraphs is not in the General registry: `import Pkg; Pkg.add(url="https://github.com/remi-garcia/AdderGraphs.git")`.
