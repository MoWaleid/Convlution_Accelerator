set project_dir [file normalize [file join [file dirname [info script]] ..]]
set project_file [file join $project_dir Convlution_Accelerator.xpr]
set report_dir [file join $project_dir reports_cfglut implementation]

file mkdir $report_dir
open_project $project_file

if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
  error "Exact CFGLUT synthesis is not complete: [get_property STATUS [get_runs synth_1]]"
}

set impl_run [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run

reset_run impl_1
launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS $impl_run]
puts "CFGLUT_IMPLEMENTATION_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} {
  error "Exact CFGLUT implementation failed: $impl_status"
}

open_run impl_1
set worst_setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $worst_setup_path] != 1} {
  error "Could not obtain a post-route setup timing path"
}
set final_wns [get_property SLACK [lindex $worst_setup_path 0]]
puts "CFGLUT_POSTROUTE_WNS_NS=$final_wns"
if {$final_wns < 0.0} {
  error "Exact CFGLUT implementation does not meet 100 MHz: WNS=${final_wns} ns"
}

report_utilization -hierarchical \
  -file [file join $report_dir utilization_impl.rpt]
report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $report_dir timing_impl.rpt]
report_power -file [file join $report_dir power_impl.rpt]
report_drc -file [file join $report_dir drc_impl.rpt]
close_design
close_project
puts "CFGLUT_IMPLEMENTATION_COMPLETE"
