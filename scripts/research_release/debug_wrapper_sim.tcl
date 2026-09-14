# debug_wrapper_sim.tcl <RELEASE_ID> <TB_FILE> [require_continuous] —
# isolated A-H wrapper sim on current RTL with the release's rendered
# config_pkg.  Debug/bisect tool with the same project shape as
# test_profile_wrappers.tcl; the testbench file is a parameter so an
# older/instrumented TB revision can be compiled against the current RTL.
#
# GLM-F5: the output directory is unique per run (timestamp + nonce) and is
# NEVER deleted, so concurrent or repeated runs cannot clobber evidence.
# The run is fail-closed: any missing PASS marker, Failure/Error/Fatal in
# the XSim log, or a parse/hash problem exits Vivado with a nonzero status.
# A run_meta.txt records the resolved TB path/hash and the rendered
# config_pkg hash so results are source-bound.
set script_dir [file normalize [file dirname [info script]]]
set root [file normalize [file join $script_dir .. ..]]
set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]

set require_continuous true
if {[info exists argv] && [llength $argv] >= 2} {
    set release_id [lindex $argv 0]
    set tb_file [file normalize [lindex $argv 1]]
    if {[llength $argv] >= 3} { set require_continuous [lindex $argv 2] }
} else {
    error "usage: vivado -mode batch -source debug_wrapper_sim.tcl -tclargs <RELEASE_ID> <TB_FILE> <require_continuous true|false>"
}
if {![file isfile $tb_file]} { error "TB not found: $tb_file" }

set rendered_config [file normalize [file join $root work research_$release_id src config_pkg.vhd]]
if {![file isfile $rendered_config]} { error "missing rendered config_pkg: $rendered_config" }

proc sha256_of {path} {
    if {[catch {exec certutil -hashfile $path SHA256} out]} {
        error "certutil could not hash $path"
    }
    if {![regexp -nocase {(^|\n)([0-9a-f]{64})(\r?$|\n)} $out -> _ hex]} {
        error "certutil returned no canonical SHA-256 for $path"
    }
    return [string tolower $hex]
}

set run_nonce [format "%s_%s" [clock microseconds] [pid]]
set out [file join $root work \
    [format "debug_wrapper_%s_%s" $release_id $run_nonce]]
if {[file exists $out]} {
    error "Refusing to reuse debug evidence directory: $out"
}
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

set meta [open [file join $out run_meta.txt] w]
puts $meta "release_id=$release_id"
puts $meta "require_continuous=$require_continuous"
puts $meta "tb_file=$tb_file"
puts $meta "tb_sha256=[sha256_of $tb_file]"
puts $meta "rendered_config=$rendered_config"
puts $meta "rendered_config_sha256=[sha256_of $rendered_config]"
puts $meta "vivado=[version -short]"
close $meta

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
if {[string first "CONV_AXIS_WRAPPER COMPLETE M4 INTEGRATION REGRESSION PASS" $log_text] < 0 || [regexp -nocase {(^|\n)(Error:|Failure:|Fatal:)} $log_text]} {
    puts "DEBUG_WRAPPER_RESULT: FAIL"
    foreach ln [split $log_text "\n"] {
        if {[regexp {(Note:|Failure:|Error:|Fatal:)} $ln]} { puts "  $ln" }
    }
    # GLM-F5: fail the batch run; the caller must not see success.
    error "debug wrapper regression FAILED for $release_id: $log_file"
}
puts "DEBUG_WRAPPER_RESULT: PASS"
quit
