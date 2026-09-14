# debug_wrapper_sim.tcl <RELEASE_ID> <TB_FILE> — isolated A-H wrapper sim on
# current RTL with the release's rendered config_pkg.  Debug bisect tool with
# the same project shape as test_profile_wrappers.tcl; the testbench file is
# a parameter so an older/instrumented TB revision can be compiled against
# the current RTL.
set script_dir [file normalize [file dirname [info script]]]
set root [file normalize [file join $script_dir .. ..]]
set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]

set require_continuous true
if {[info exists argv] && [llength $argv] >= 2} {
    set release_id [lindex $argv 0]
    set tb_file [lindex $argv 1]
    if {[llength $argv] >= 3} { set require_continuous [lindex $argv 2] }
} else {
    error "usage: vivado -mode batch -source debug_wrapper_sim.tcl -tclargs <RELEASE_ID> <TB_FILE> <require_continuous true|false>"
}
if {![file isfile $tb_file]} { error "TB not found: $tb_file" }

set rendered_config [file join $root work research_$release_id src config_pkg.vhd]
if {![file isfile $rendered_config]} { error "missing rendered config_pkg: $rendered_config" }

set out [file join $root work debug_wrapper_$release_id]
file delete -force $out
file mkdir $out

create_project debug_wrapper_sim $out -part xc7z020clg484-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

foreach name {conv_pkg sync_fifo coeff_bias_shift_regfile axi_lite_ctrl \
              window_generator cfglut5_kcm cfglut5_bitheap_3x3 \
              cfglut5_bitheap_5x5 conv_channel conv_engine conv_top \
              axi_stream_input_frontend axi_stream_output_serializer \
              conv_axis_wrapper} {
    add_files -norecurse [file join $rtl $name.vhd]
}
add_files -norecurse $rendered_config
add_files -fileset sim_1 -norecurse $tb_file
set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top conv_axis_wrapper [get_filesets sources_1]
set_property top tb_conv_axis_wrapper [get_filesets sim_1]
set_property generic "G_WINDOW_PREFETCH=true G_REQUIRE_CONTINUOUS=$require_continuous G_STRESS=false" [get_filesets sim_1]
update_compile_order -fileset sim_1

if {$release_id eq "D640_CFGLUT125"} {
    puts "NOTE: D640 simulates 640x480 frames - expect a long xsim run; this is not a hang"
}
launch_simulation -mode behavioral
run all
close_sim

set log_file [file join $out debug_wrapper_sim.sim sim_1 behav xsim simulate.log]
set fd [open $log_file r]
set log_text [read $fd]
close $fd
if {[string first "CONV_AXIS_WRAPPER COMPLETE M4 INTEGRATION REGRESSION PASS" $log_text] >= 0} {
    puts "DEBUG_WRAPPER_RESULT: PASS"
} else {
    puts "DEBUG_WRAPPER_RESULT: FAIL"
    foreach ln [split $log_text "\n"] {
        if {[regexp {(Note:|Failure:|Error:)} $ln]} { puts "  $ln" }
    }
}
quit
