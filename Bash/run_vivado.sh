#!/bin/bash

# Script for VHDL --TCL--> Vivado run
# Inspired from the vivado-runsyn.py tool in FloPoCo


# Set variables
verbose=false
project_name="vivado_project"
main_vhdl_file=
additional_vhdl_files=()
part=
do_implementation=false
do_ooc=false
frequency=1
delay_between_registers=false
do_simulation=false
sim_file=
bsim_file=
ooc_entities=()

do_not_run=false
results_file=$(realpath "results.csv")
delete_after=true


############################################################
# Functions                                                #
############################################################
show_help()
{
    # Display Help
    echo "Syntax: run_vivado [-h|v|p|part|i|ooc|f|d|s|bs] -- vhdl_files"
    echo "options:"
    echo "h     help                Print this help."
    echo "v     verbose             Verbose mode."
    echo "p     project=name        Project name (default: ${project_name})."
    echo "vhdl=file                 Main VHDL file."
    echo "avhdl=file                Additional VHDL files."
    echo "      part=part           Part name (default: none)."
    echo "i     implement           Do implementation (default: synthesis only)."
    echo "ooc                       Out of context implementation."
    echo "f     frequency           Frequency (default: ${frequency}MHz)."
    echo "d     delay_registers     Get delay between registers (ignore io)."
    echo "s                         File for simulation."
    echo "bs                        File for behavioral simulation."
    echo "      ooc_entity=entity   Entity to implement in ooc mode."
    echo
    echo "t     only_tcl            Do not run vivado, just prepare the project."
    echo "r     read_results=file   Read vivado results and write them (default file: $(basename ${results_file}))."
    echo "k     keep_project        Do not delete the project after saving vivado results."
    echo
}


die() {
    printf '%s\n' "$1" >&2
    exit 1
}


log() {
    if [ $verbose = true ]; then
        echo -e "$@"
    fi
}


get_last_entity() {
    echo -e $(echo -e $(grep entity $1 | tail -2 | head -1) | awk '{print $2}')
}

get_insig_last_entity() {
    local first_line=$(tac "$1" | awk -v nb_lines=$(wc -l < $1) '/entity /{print nb_lines-FNR+1; exit}')
    local last_line=$(tac "$1" | awk -v nb_lines=$(wc -l < $1) '/entity;/{print nb_lines-FNR+1; exit}')

    #echo -e "first: ${first_line}"
    #echo -e "last: ${last_line}"
    #echo -e $(awk -v s="$first_line" -v e="$last_line" 'NR>1*s&&NR<1*e' $1)
    
    local lines=$(awk -v s="$first_line" -v e="$last_line" 'NR>1*s&&NR<1*e' $1)
    local insig_lines=$(echo -e "${lines}" | sed 's/;/\n/g' | grep -E -i ':\s*in')
    local insig=$(echo -e "${insig_lines}" | sed 's/\s*\:.*//g' | cat | awk 'NF>=1{print $NF}')
    echo -e "${insig}"
}

get_outsig_last_entity() {
    local first_line=$(tac "$1" | awk -v nb_lines=$(wc -l < $1) '/entity /{print nb_lines-FNR+1; exit}')
    local last_line=$(tac "$1" | awk -v nb_lines=$(wc -l < $1) '/entity;/{print nb_lines-FNR+1; exit}')

    #echo -e "first: ${first_line}"
    #echo -e "last: ${last_line}"
    #echo -e $(awk -v s="$first_line" -v e="$last_line" 'NR>1*s&&NR<1*e' $1)
    
    local lines=$(awk -v s="$first_line" -v e="$last_line" 'NR>1*s&&NR<1*e' $1)
    local outsig_lines=$(echo -e "${lines}" | sed 's/;/\n/g' | grep -E -i ':\s*out')
    local outsig=$(echo -e "${outsig_lines}" | sed 's/\s*\:.*//g' | cat | awk 'NF>=1{print $NF}')
    echo -e "${outsig}"
}


############################################################
# Main                                                     #
############################################################

OLD_IFS="$IFS"
IFS=$'\n'
while :; do
    case $1 in
        -h|-\?|--help)
            show_help    # Display a usage synopsis.
            exit
            ;;
        -v|--verbose)
            verbose=true
            ;;
        -p|--project)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                project_name=$2
                shift
            else
                die 'ERROR: "--project_name" requires a non-empty option argument.'
            fi
            ;;
        -p=?*|--project=?*)
            project_name=${1#*=} # Delete everything up to "=" and assign the remainder.
            ;;
        -p=|--project=)         # Handle the case of an empty --project=
            die 'ERROR: "--project" requires a non-empty option argument.'
            ;;
        -vhdl|--vhdl)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                main_vhdl_file=$(realpath "$2")
                shift
            else
                die 'ERROR: "--vhdl" requires a non-empty option argument.'
            fi
            ;;
        -vhdl=?*|--vhdl=?*)
            main_vhdl_file=$(realpath "${1#*=}") # Delete everything up to "=" and assign the remainder.
            ;;
        -vhdl=|--vhdl=)         # Handle the case of an empty --vhdl=
            die 'ERROR: "--vhdl" requires a non-empty option argument.'
            ;;
        -avhdl|--avhdl)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                additional_vhdl_files+=($(realpath "$2"))
                shift
            else
                die 'ERROR: "--vhdl" requires a non-empty option argument.'
            fi
            ;;
        -avhdl=?*|--avhdl=?*)
            additional_vhdl_files+=($(realpath "${1#*=}")) # Delete everything up to "=" and assign the remainder.
            ;;
        -avhdl=|--avhdl=)         # Handle the case of an empty --vhdl=
            die 'ERROR: "--vhdl" requires a non-empty option argument.'
            ;;
        --part)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                part=$2
                shift
            else
                die 'ERROR: "--part" requires a non-empty option argument.'
            fi
            ;;
        --part=?*)
            part=${1#*=} # Delete everything up to "=" and assign the remainder.
            ;;
        --part=)         # Handle the case of an empty --part=
            die 'ERROR: "--part" requires a non-empty option argument.'
            ;;
        -i|--implement)
            do_implementation=true
            ;;
        -ooc)
            do_ooc=true
            ;;
        -f|--frequency)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                frequency=$2
                shift
            else
                die 'ERROR: "--frequency" requires a non-empty option argument.'
            fi
            ;;
        -f=?*|--frequency=?*)
            frequency=${1#*=} # Delete everything up to "=" and assign the remainder.
            ;;
        -f=|--frequency=)         # Handle the case of an empty --frequency=
            die 'ERROR: "--frequency" requires a non-empty option argument.'
            ;;
        -d|--delay_registers)
            delay_between_registers=true
            ;;
        -s)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                sim_file=$(realpath "$2")
                shift
            else
                die 'ERROR: "-s" requires a non-empty option argument.'
            fi
            ;;
        -s=?*)
            sim_file=$(realpath "${1#*=}") # Delete everything up to "=" and assign the remainder.
            ;;
        -s=)         # Handle the case of an empty -s=
            die 'ERROR: "-s" requires a non-empty option argument.'
            ;;
        -bs)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                bsim_file=$(realpath "$2")
                shift
            else
                die 'ERROR: "-bs" requires a non-empty option argument.'
            fi
            ;;
        -bs=?*)
            bsim_file=$(realpath "${1#*=}") # Delete everything up to "=" and assign the remainder.
            ;;
        -bs=)         # Handle the case of an empty -bs=
            die 'ERROR: "-bs" requires a non-empty option argument.'
            ;;
        --ooc_entity)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                ooc_entities+=($2)
                shift
            else
                die 'ERROR: "--ooc_entity" requires a non-empty option argument.'
            fi
            ;;
        --ooc_entity=?*)
            ooc_entities+=(${1#*=}) # Delete everything up to "=" and assign the remainder.
            ;;
        --ooc_entity=)         # Handle the case of an empty --ooc_entity=
            die 'ERROR: "--ooc_entity" requires a non-empty option argument.'
            ;;
        -t|--only_tcl)
            do_not_run=true
            ;;
        -r|--read_results)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                results_file=$(realpath "$2")
                shift
            else
                die 'ERROR: "--read_results" requires a non-empty option argument.'
            fi
            ;;
        -r=?*|--read_results=?*)
            results_file=$(realpath "${1#*=}") # Delete everything up to "=" and assign the remainder.
            ;;
        -r=|--read_results=)         # Handle the case of an empty --read_results=
            die 'ERROR: "--read_results" requires a non-empty option argument.'
            ;;
        -k|--keep_project)
            delete_after=false
            ;;
        --)              # End of all options.
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)               # Default case: No more options, so break out of the loop.
            break
    esac

    shift
done
IFS="$OLD_IFS"

if [ -z "$main_vhdl_file" ]; then
    echo -e "Missing main vhdl file"
    exit 1
fi
if [ -z "${part}" ]; then
    echo -e "Missing 'part' argument"
    exit 1
fi

remaining_args=$@
log "Ignored remaining args=\"${remaining_args}\""

if [ ! -z "${sim_file}" ]; then
    if [ $do_implementation = true ]; then
        do_simulation=true
    fi
fi


log "Verbose mode"
log "project_name:              ${project_name}"
log "Main VHDL file:            ${main_vhdl_file}"
if [ -z "${additional_vhdl_files}" ]; then
    log "No additional VHDL files"
else
    log "Additional VHDL files:"
    for val in "${additional_vhdl_files[@]}"; do
        log "\t- ${val}"
    done
fi
log "part:                      ${part}"
log "implement:                 ${do_implementation}"
log "out of context:            ${do_ooc}"
log "frequency:                 ${frequency} MHz"
log "delay between registers:   ${delay_between_registers}"
if [ -z "${ooc_entities}" ]; then
    log "No OOC entities"
else
    log "OOC entities:"
    for val in "${ooc_entities[@]}"; do
        log "\t- ${val}"
    done
fi
log "only tcl:                  ${do_not_run}"
log "save results:              ${results_file}"
log "delete project after run:  ${delete_after}"




basedir="$(pwd)"
workdir="$(pwd)/${project_name}"
if [ -d "$workdir" ]; then
    rm -r "${workdir}"
fi
mkdir -p "${workdir}"
srcfiles="${workdir}/src_files"
mkdir -p "${srcfiles}"
cp "$(realpath "${main_vhdl_file}")" "${srcfiles}/"
local_main_file="${srcfiles}/$(basename ${main_vhdl_file})"
for curr_vhdlfile in "${additional_vhdl_files[@]}"; do
    cp "$(realpath "${curr_vhdlfile}")" "${srcfiles}/"
done
cd "${workdir}"
xdc_file="${workdir}/clock.xdc"
log "Create clock.xdc file"
period=$(echo "scale=2; 1000.0/${frequency}" | bc -l)
half_period=$(echo "scale=2; ${period}/2.0" | bc -l)
log "\tperiod: ${period}"
log "\thalf_period: ${half_period}"
echo -e "create_clock -name clk -period ${period} -waveform {0.000 ${half_period}} [get_ports clk]" >> ${xdc_file}
insig=$(get_insig_last_entity ${local_main_file})
echo "${insig}" | while IFS= read -r curr_insig ; do echo -e "set_input_delay -clock [get_clocks clk] 0 [get_ports ${curr_insig}]" >> ${xdc_file}; done
outsig=$(get_outsig_last_entity ${local_main_file})
echo "${outsig}" | while IFS= read -r curr_outsig ; do echo -e "set_output_delay -clock [get_clocks clk] 0 [get_ports ${curr_outsig}]" >> ${xdc_file}; done



tcl_script="${workdir}/${project_name}.tcl"
log "Write tcl script: ${tcl_script}"
echo -e "# Generated" >> ${tcl_script}
echo -e "create_project ${project_name} -part ${part}" >> ${tcl_script}
echo -e "set_property target_language VHDL [current_project]" >> ${tcl_script}
for curr_srcfile in "${srcfiles}"/*; do
    if [ -f "${curr_srcfile}" ]; then
        echo -e "add_files -fileset sources_1 -norecurse ${curr_srcfile}" >> ${tcl_script}
    fi
done
main_entity=$(get_last_entity "${local_main_file}")
echo -e "set_property top ${main_entity} [get_filesets sources_1]" >> ${tcl_script}
echo -e "read_xdc -mode out_of_context ${xdc_file}" >> ${tcl_script}


if [ ! -z "${bsim_file}" ]; then
    srcbsimfolder="${workdir}/bsim_file"
    mkdir -p "${srcbsimfolder}"
    cp "${bsim_file}" "${srcbsimfolder}/"
    local_bsim_file="${srcbsimfolder}/$(basename ${bsim_file})"
    log "Behavioral simulation"
    echo -e "# For behavioral simulation" >> ${tcl_script}
    echo -e "create_fileset -simset bsim_1" >> ${tcl_script}
    echo -e "add_files -fileset bsim_1 -norecurse ${local_bsim_file}" >> ${tcl_script}
    entity_bsimulation=$(get_last_entity "${local_bsim_file}")
    echo -e "set_property top ${entity_bsimulation} [get_filesets bsim_1]" >> ${tcl_script}
    echo -e "set_property TARGET_SIMULATOR XSim [get_filesets bsim_1]" >> ${tcl_script}
    echo -e "set_property -name {xsim.elaborate.xelab.more_options} -value {-timeprecision_vhdl 1ns} -objects [get_filesets bsim_1]" >> ${tcl_script}
    echo -e "launch_simulation -simset [get_filesets bsim_1] -mode \"behavioral\"" >> ${tcl_script}
    echo -e "restart" >> ${tcl_script}
    echo -e "run all" >> ${tcl_script}
    echo -e "set simError 0" >> ${tcl_script}
    echo -e "set simError [get_value -radix unsigned errorCounter]" >> ${tcl_script}
    echo -e "if { \$simError != 0 } {" >> ${tcl_script}
    echo -e "\tputs \"Error in simulation\"" >> ${tcl_script}
    echo -e "\texit 1" >> ${tcl_script}
    echo -e "}" >> ${tcl_script}
fi

if [ -n "${ooc_entities}" ]; then
    echo -e "set_property USED_IN {out_of_context synthesis implementation} [get_files ${xdc_file}]" >> ${tcl_script}
    for curr_ooc_entity in "${ooc_entities[@]}"; do
        echo -e "create_fileset -blockset -define_from ${curr_ooc_entity} ${curr_ooc_entity}" >> ${tcl_script}
    done
fi


reports_folder="${workdir}/reports"
mkdir -p "${reports_folder}"
power_report="${reports_folder}/power_report.rpt"
utilization_report_synth="${reports_folder}/utilization_synth.rpt"
utilization_report_impl="${reports_folder}/utilization_placed.rpt"
timing_report="${reports_folder}/timing.rpt"
pulse_report="${reports_folder}/pulse.rpt"


echo -e "update_compile_order -fileset sources_1" >> ${tcl_script}
#echo -e "synth_design -mode out_of_context -global_retiming on" >> ${tcl_script}
echo -e "set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]" >> ${tcl_script}
echo -e "launch_runs synth_1 -jobs 6" >> ${tcl_script}
echo -e "wait_on_run synth_1" >> ${tcl_script}
echo -e "open_run synth_1 -name synth_1" >> ${tcl_script}
echo -e "set_property IOB FALSE [all_inputs]" >> ${tcl_script}
echo -e "set_property IOB FALSE [all_outputs]" >> ${tcl_script}
echo -e "report_utilization -file ${utilization_report_synth}" >> ${tcl_script}

echo -e "set util_str [report_utilization -return_string]" >> ${tcl_script}
echo -e "# Generate utilization report and capture its output" >> ${tcl_script}
echo -e "proc extract_used_and_total {util_str resource} {" >> ${tcl_script}
echo -e "\t# Escape the resource name to work in regex" >> ${tcl_script}
echo -e "\tset escaped_resource [string map {\" \" \"\\\\\\\\s+\"} \$resource]" >> ${tcl_script}
echo -e "\tset pattern \"^\\\\\\\\|\\\\\\\\s*\$escaped_resource\\\\\\\\*?\\\\\\\\s*\\\\\\\\|\\\\\\\\s*(\\\\\\\\d+)\\\\\\\\s+\\\\\\\\|\\\\\\\\s*\\\\\\\\d+\\\\\\\\s+\\\\\\\\|\\\\\\\\s*\\\\\\\\d+\\\\\\\\s+\\\\\\\\|\\\\\\\\s*(\\\\\\\\d+)\"" >> ${tcl_script}
echo -e "\tif {[regexp -nocase -line \$pattern \$util_str -> used total]} {" >> ${tcl_script}
echo -e "\t\treturn [list \$used \$total]" >> ${tcl_script}
echo -e "\t} else {" >> ${tcl_script}
echo -e "\t\treturn [list 0 0]" >> ${tcl_script}
echo -e "\t}" >> ${tcl_script}
echo -e "}" >> ${tcl_script}
echo -e "# Extract resource usage and capacity" >> ${tcl_script}
echo -e "lassign [extract_used_and_total \$util_str \"Slice LUTs\"]      lut_used lut_total" >> ${tcl_script}
echo -e "lassign [extract_used_and_total \$util_str \"Slice Registers\"] ff_used ff_total" >> ${tcl_script}
echo -e "lassign [extract_used_and_total \$util_str \"Block RAM Tile\"]  bram_used bram_total" >> ${tcl_script}
echo -e "lassign [extract_used_and_total \$util_str \"DSPs\"]            dsp_used dsp_total" >> ${tcl_script}
echo -e "lassign [extract_used_and_total \$util_str \"CLBs\"]            clb_used clb_total" >> ${tcl_script}
echo -e "lassign [extract_used_and_total \$util_str \"URAM\"]            uram_used uram_total" >> ${tcl_script}

echo -e "set resource_data [list \\" >> ${tcl_script}
echo -e "\tLUT      \$lut_used   \$lut_total \\" >> ${tcl_script}
echo -e "\tFF       \$ff_used    \$ff_total \\" >> ${tcl_script}
echo -e "\tBRAM_18K \$bram_used  \$bram_total \\" >> ${tcl_script}
echo -e "\tDSP      \$dsp_used   \$dsp_total \\" >> ${tcl_script}
echo -e "\tCLB      \$clb_used   \$clb_total \\" >> ${tcl_script}
echo -e "\tURAM     \$uram_used  \$uram_total \\" >> ${tcl_script}
echo -e "]" >> ${tcl_script}

echo -e "set exceeds_limit false"  >> ${tcl_script}

echo -e "foreach {name used total} \$resource_data {" >> ${tcl_script}
echo -e "\tputs [format \"%s utilization: %s/%s.\" \$name \$used \$total]" >> ${tcl_script}
echo -e "\tif {\$used > \$total} {" >> ${tcl_script}
echo -e "\t\tputs [format \"CRITICAL WARNING: %s usage (%s) exceeds device capacity (%s).\" \$name \$used \$total]" >> ${tcl_script}
echo -e "\t\tset exceeds_limit true" >> ${tcl_script}
echo -e "\t}" >> ${tcl_script}
echo -e "}" >> ${tcl_script}


if [ $do_implementation = true ]; then
    echo -e "if {\$exceeds_limit} {" >> ${tcl_script}
    echo -e "\tputs \"Implementation will NOT be launched — design exceeds resource limits.\"" >> ${tcl_script}
    echo -e "} else {" >> ${tcl_script}
    if [ $do_ooc = true ]; then
        echo -e "\twrite_edif ${workdir}/${main_entity}.edf" >> ${tcl_script}
        echo -e "\tread_edif ${workdir}/${main_entity}.edf" >> ${tcl_script}
        #https://adaptivesupport.amd.com/s/question/0D52E00006hpKnSSAU/
        #This does not seem necessary
        echo -e "\tlink_design -mode out_of_context -quiet" >> ${tcl_script}
    fi
    echo -e "\tlaunch_runs impl_1 -quiet" >> ${tcl_script}
    echo -e "\twait_on_run impl_1" >> ${tcl_script}
    echo -e "\topen_run impl_1 -name impl_1" >> ${tcl_script}

    echo -e "\tset_property IOB FALSE [all_inputs]" >> ${tcl_script}
    echo -e "\tset_property IOB FALSE [all_outputs]" >> ${tcl_script}

    echo -e "\treport_utilization -file ${utilization_report_impl}" >> ${tcl_script}
    echo -e "}" >> ${tcl_script}
fi


if [ $delay_between_registers = true ]; then
    echo -e "report_timing -file ${timing_report} -from [all_registers] -to [all_registers]" >> ${tcl_script}
    #https://adaptivesupport.amd.com/s/question/0D54U00008KxsUuSAJ/
    #https://adaptivesupport.amd.com/s/question/0D52E00006hpZKRSA2/
    #echo -e "set paths [get_timing_paths -from [all_registers] -to [all_registers]]" >> ${tcl_script}
    #echo -e "if {[llength \$paths] == 0} {" >> ${tcl_script}
    #echo -e "\treport_pulse_width -file ${pulse_report} -min_period -cells [get_cells]" >> ${tcl_script}
    #echo -e "}" >> ${tcl_script}
else
    echo -e "report_timing -file ${timing_report}" >> ${tcl_script}
fi
echo -e "report_pulse_width -file ${pulse_report} -min_period -cells [get_cells]" >> ${tcl_script}

echo -e "read_xdc -mode out_of_context ${xdc_file}" >> ${tcl_script}


if [ $do_simulation = true ]; then
    srcsimfolder="${workdir}/sim_file"
    mkdir -p "${srcsimfolder}"
    cp "${sim_file}" "${srcsimfolder}/"
    local_sim_file="${srcsimfolder}/$(basename ${sim_file})"
    sdf_file="${workdir}/${project_name}_sdf.sdf"
    verilog_file="${workdir}/${project_name}_verilog.v"
    saif_file="${workdir}/${project_name}_saif.saif"
    entity_simulation=$(get_last_entity "${local_sim_file}")
    log "Simulation"
    echo -e "if {\$exceeds_limit} {" >> ${tcl_script}
    echo -e "\tputs \"Simulation will NOT be launched — design exceeds resource limits.\"" >> ${tcl_script}
    echo -e "} else {" >> ${tcl_script}
    echo -e "\t# For simulation" >> ${tcl_script}
    echo -e "\twrite_sdf -file ${sdf_file}" >> ${tcl_script}
    echo -e "\twrite_verilog -sdf_file ${sdf_file} -mode timesim -sdf_anno true ${verilog_file}" >> ${tcl_script}
    echo -e "\tadd_files -fileset sim_1 -norecurse ${sdf_file}" >> ${tcl_script}
    echo -e "\tadd_files -fileset sim_1 -norecurse ${verilog_file}" >> ${tcl_script}
    echo -e "\tadd_files -fileset sim_1 -norecurse ${local_sim_file}" >> ${tcl_script}
    echo -e "\tset_property top ${entity_simulation} [get_filesets sim_1]" >> ${tcl_script}
    echo -e "\tset_property TARGET_SIMULATOR XSim [get_filesets sim_1]" >> ${tcl_script}
    echo -e "\tlaunch_simulation -simset [get_filesets sim_1] -mode \"post-implementation\" -type timing" >> ${tcl_script}
    echo -e "\trestart" >> ${tcl_script}
    echo -e "\topen_saif ${saif_file}" >> ${tcl_script}
    echo -e "\tlog_saif [get_object]" >> ${tcl_script}
    echo -e "\trun 100000 ns" >> ${tcl_script}
    echo -e "\tclose_saif" >> ${tcl_script}
    echo -e "\tread_saif ${saif_file}" >> ${tcl_script}
    echo -e "}" >> ${tcl_script}
fi
echo -e "report_power -file ${power_report}" >> ${tcl_script}


if [ $do_not_run = true ]; then
    cd "${basedir}"
    exit
fi

vivado_output_file=$(realpath "vivado_current_run.log")
vivado_command="vivado -mode batch -source ${tcl_script}"
log "Run vivado: ${vivado_command}"
eval ${vivado_command} > ${vivado_output_file} 2>&1
retVal=$?
if [ $retVal -ne 0 ]; then
    if [ $retVal -eq 127 ]; then
        echo -e "Vivado not found on system"
        exit 1
    else
        echo -e "Vivado errored"
        exit 1
    fi
fi


implementation_done=false
simulation_done=false
utilization_report="${utilization_report_synth}"
if [ -f "${utilization_report_impl}" ]; then
    implementation_done=true
    utilization_report="${utilization_report_impl}"
    if [ $do_simulation = true ]; then
        simulation_done=true
    fi
fi
cat ${utilization_report} >> ${vivado_output_file}
cat ${timing_report} >> ${vivado_output_file}
if [ -f "${pulse_report}" ]; then
    cat ${pulse_report} >> ${vivado_output_file}
fi
cat ${power_report} >> ${vivado_output_file}
if [ $verbose = true ]; then
    log "Utilization report:"
    cat ${utilization_report}
    log "Timing report:"
    cat ${timing_report}
    if [ -f "${pulse_report}" ]; then
        log "Pulse report:"
        cat ${pulse_report}
    fi
fi


if [ ! -f "${results_file}" ]; then
    echo "Project name;Impl;Sim;LUTs;FFs;DSPs;data path delay;Total On-Chip Power (W);Device Static (W);Dynamic (W); Clocks (dyn); Logic (dyn); Signals (dyn);i DSPs; I/O (dyn)" > $results_file
fi

# Project name
echo -ne "${project_name};" >> ${results_file}
echo -ne "${implementation_done};" >> ${results_file}
echo -ne "${simulation_done};" >> ${results_file}

# LUTs
echo -ne $(grep -m 1 "Slice LUTs" ${utilization_report} | awk '{print $5}') >> ${results_file}
echo -ne ";" >> ${results_file}
# FF
echo -ne $(grep -m 1 "Slice Registers" ${utilization_report} | awk '{print $5}') >> ${results_file}
echo -ne ";" >> ${results_file}
# DSPs
echo -ne $(grep -m 1 "DSPs  " ${utilization_report} | awk '{print $4}') >> ${results_file}
echo -ne ";" >> ${results_file}
# Delay
#if [ ! -f "${pulse_report}" ]; then
#    echo -ne $(grep -m 1 "Data Path Delay" ${timing_report} | awk '{print $4}') >> ${results_file}
#else
#    echo -ne $(grep -m 1 "Min Period" ${pulse_report} | awk '{print $6}') >> ${results_file}
#    echo -ne "ns" >> ${results_file}
#fi
timing_delay=`echo -ne $(grep -m 1 "Data Path Delay" ${timing_report} | awk '{print $4}')`
timing_delay=${timing_delay::-2}
pulse_delay=`echo -ne $(grep -m 1 "Min Period" ${pulse_report} | awk '{print $6}')`
if (( $(echo "${timing_delay} > ${pulse_delay}" | bc -l) )); then
    echo -ne "${timing_delay}" >> ${results_file}
else
    echo -ne "${pulse_delay}" >> ${results_file}
fi
echo -ne "ns" >> ${results_file}
echo -ne ";" >> ${results_file}
# Power
# total power
echo -ne $(grep -m 1 "Total On-Chip Power (W)" ${power_report} | awk '{print $7}') >> ${results_file}
echo -ne ";" >> ${results_file}
# static power
echo -ne $(grep -m 1 "Device Static (W)" ${power_report} | awk '{print $6}') >> ${results_file}
echo -ne ";" >> ${results_file}
#dynamic power
echo -ne $(grep -m 1 "Dynamic (W)" ${power_report} | awk '{print $5}') >> ${results_file}
echo -ne ";" >> ${results_file}
#clocks
echo -ne $(grep -m 1 "Clocks" ${power_report} | awk '{print $4}') >> ${results_file}
echo -ne ";" >> ${results_file}
#slice logic
echo -ne $(grep -m 1 "Slice Logic" ${power_report} | awk '{print $5}') >> ${results_file}
echo -ne ";" >> ${results_file}
#signals
echo -ne $(grep -m 1 "Signals" ${power_report} | awk '{print $4}') >> ${results_file}
echo -ne ";" >> ${results_file}
#DSPs
echo -ne $(grep -m 1 "DSPs" ${power_report} | awk '{print $4}') >> ${results_file}
echo -ne ";" >> ${results_file}
#I/O
echo -ne $(grep -m 1 "I/O      " ${power_report} | awk '{print $4}') >> ${results_file}
echo -ne ";" >> ${results_file}
echo -e "" >> ${results_file}


cd "${basedir}"

if [ $delete_after = true ]; then
    rm -r "${workdir}"
fi

