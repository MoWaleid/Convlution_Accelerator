set project_dir [file normalize [file join [file dirname [info script]] ..]]
set project_file [file join $project_dir Convlution_Accelerator.xpr]
set report_dir [file join $project_dir reports_cfglut full_synth]

file mkdir $report_dir
open_project $project_file

set bd_file [get_files -quiet */accelerator_dma.bd]
if {[llength $bd_file] != 1} {
  error "Expected exactly one accelerator_dma.bd"
}

open_bd_design $bd_file
validate_bd_design
generate_target all $bd_file
set wrapper_files [make_wrapper -files $bd_file -top]
if {[llength $wrapper_files] > 0} {
  add_files -norecurse $wrapper_files
}
update_compile_order -fileset sources_1
set_property top accelerator_dma_wrapper [get_filesets sources_1]

set conv_ooc [get_runs -quiet accelerator_dma_conv_axis_wrapper_bd_0_0_synth_1]
if {[llength $conv_ooc] == 1} {
  reset_run $conv_ooc
}
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "CFGLUT_FULL_SYNTHESIS_STATUS=$synth_status"
if {$synth_status ne "synth_design Complete!"} {
  error "Exact CFGLUT synthesis failed: $synth_status"
}

open_run synth_1
report_utilization -hierarchical \
  -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $report_dir timing_synth.rpt]
close_design
close_project
puts "CFGLUT_FULL_SYNTH_COMPLETE"
