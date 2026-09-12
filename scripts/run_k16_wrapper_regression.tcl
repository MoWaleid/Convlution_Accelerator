set project_dir [file normalize [file join [file dirname [info script]] ..]]
set project_path [file join $project_dir Convlution_Accelerator.xpr]

open_project $project_path
set simset [get_filesets sim_1]
set previous_top [get_property top $simset]

set_property top tb_conv_axis_wrapper $simset
update_compile_order -fileset sim_1

if {[catch {
  launch_simulation -simset sim_1 -mode behavioral
  run all
} message options]} {
  catch {close_sim -force}
  set_property top $previous_top $simset
  close_project
  return -options $options $message
}

close_sim -force

set simulation_log [file join $project_dir Convlution_Accelerator.sim \
  sim_1 behav xsim simulate.log]
set log_channel [open $simulation_log r]
set log_text [read $log_channel]
close $log_channel

if {[string first "CONV_AXIS_WRAPPER COMPLETE M4 INTEGRATION REGRESSION PASS" $log_text] < 0 ||
    [regexp -nocase {(^|\n)Failure:} $log_text]} {
  set_property top $previous_top $simset
  close_project
  error "K16 full-wrapper regression did not reach its PASS marker; inspect $simulation_log"
}

set_property top $previous_top $simset
close_project
puts "K16_FULL_WRAPPER_REGRESSION_COMPLETED"
