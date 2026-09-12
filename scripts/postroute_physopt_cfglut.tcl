set project_dir [file normalize [file join [file dirname [info script]] ..]]
set project_file [file join $project_dir Convlution_Accelerator.xpr]
set report_dir [file join $project_dir reports_cfglut postroute_physopt]

file mkdir $report_dir
open_project $project_file
open_run impl_1

# Try implementation-only timing recovery first.  This does not change the
# arithmetic, channel pipeline latency, initiation interval, or AXI protocol.
phys_opt_design -directive AggressiveExplore
route_design -preserve

report_utilization -hierarchical \
  -file [file join $report_dir utilization_impl.rpt]
report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $report_dir timing_impl.rpt]
report_drc -file [file join $report_dir drc_impl.rpt]
write_checkpoint -force \
  [file join $report_dir accelerator_dma_wrapper_postroute_physopt.dcp]

close_design
close_project
puts "CFGLUT_POSTROUTE_PHYSOPT_COMPLETE"
