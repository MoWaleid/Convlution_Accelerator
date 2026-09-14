# Pure RTL wrapper regression, independent of regenerated Zynq/DMA IP.
#
# Variants:
#   baseline / optimized / baseline_stress / optimized_stress
#       A-H regression + metric acceptance checker must PASS.
#   negative_control
#       Prefetch DISABLED but OPTIMIZED expectations enforced.  The metric
#       checker MUST FAIL (frame D shows 62 internal invalid advances).
#       This proves the checker actually detects the regression the
#       optimization fixes; used as the acceptance self-test.
set root [file normalize [file join [file dirname [info script]] ..]]
set variant optimized
if {[llength $argv]} { set variant [lindex $argv 0] }
if {$variant ni {baseline optimized baseline_stress optimized_stress negative_control}} {
    error "Use baseline, optimized, baseline_stress, optimized_stress or negative_control"
}
set enabled [expr {[string match "optimized*" $variant] ? "true" : "false"}]
set stress  [expr {($variant eq "baseline_stress" || $variant eq "optimized_stress") ? "true" : "false"}]
set expect_checker_fail [expr {$variant eq "negative_control"}]
set work_dir [file join $root work edge_$variant]
file mkdir $work_dir
create_project -force edge_sim $work_dir -part xc7z020clg484-1
set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]
foreach name {config_pkg conv_pkg sync_fifo coeff_bias_shift_regfile axi_lite_ctrl window_generator cfglut5_kcm cfglut5_bitheap_3x3 conv_channel conv_engine conv_top axi_stream_input_frontend axi_stream_output_serializer conv_axis_wrapper} {
    add_files -norecurse [file join $rtl $name.vhd]
}
add_files -fileset sim_1 -norecurse [file join $root Convlution_Accelerator.srcs sim_1 imports new tb_conv_axis_wrapper.vhd]
set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top conv_axis_wrapper [get_filesets sources_1]
set_property top tb_conv_axis_wrapper [get_filesets sim_1]
set_property generic "G_WINDOW_PREFETCH=$enabled G_REQUIRE_CONTINUOUS=$enabled G_STRESS=$stress" [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -mode behavioral
run all
close_sim

set log_file [file join $work_dir edge_sim.sim sim_1 behav xsim simulate.log]
set fd [open $log_file r]
set log_text [read $fd]
close $fd

if {[string first "CONV_AXIS_WRAPPER COMPLETE M4 INTEGRATION REGRESSION PASS" $log_text] < 0 || [regexp -nocase {(^|\n)(Error:|Failure:|Fatal:)} $log_text]} {
    error "Edge regression failed: $log_file"
}

# ---------------------------------------------------------------------
# Metric acceptance checker.
#
# Enforces the internal edge-bubble requirement on the benchmark frame
# (record 2: guaranteed input supply, continuously ready sink):
#   - exactly 3 WINDOW_METRICS records with sequence ids 1, 2, 3
#     (frames C, D, H; aborted/partial frames produce no record)
#   - frame D invalid_advances = 0 with prefetch, 62 without
#     (31 logical row transitions x 2 history pixels, deterministic
#     under the continuous-supply fixture)
#   - exactly one EDGE_METRICS record with ready_mode=1 and gaps=0
#   - latency records (start_to_first_output, start_to_done) present
# External output-gap counts for the stalled frames C/H are reported
# but not asserted; source starvation must not fail the run.
# ---------------------------------------------------------------------
proc check_metrics {log_text built_enabled expected_policy_enabled} {
    set records {}
    foreach {_ seq pre inv} [regexp -all -inline -line \
        {WINDOW_METRICS seq=(\d+) prefetch=(true|false) invalid_advances=(\d+)} $log_text] {
        lappend records [list $seq $pre $inv]
    }
    if {[llength $records] != 3} {
        return "expected 3 WINDOW_METRICS records (frames C,D,H), got [llength $records]"
    }
    set seqs {}
    foreach r $records { lappend seqs [lindex $r 0] }
    if {$seqs ne "1 2 3"} { return "WINDOW_METRICS sequence mismatch: $seqs" }
    set d [lindex $records 1]
    if {[lindex $d 1] ne $built_enabled} {
        return "frame D prefetch flag [lindex $d 1] does not match built config $built_enabled"
    }
    # The EXPECTATION follows the policy under test, not the built config:
    # the negative control builds prefetch=false but enforces the optimized
    # expectation (0), so a 62-bubble baseline must fail here.
    set expected_invalid [expr {$expected_policy_enabled ? 0 : 62}]
    if {[lindex $d 2] != $expected_invalid} {
        return "frame D invalid_advances=[lindex $d 2], expected $expected_invalid"
    }
    set dmetrics 0
    foreach {_ rm gaps} [regexp -all -inline -line \
        {EDGE_METRICS prefetch=\w+ ready_mode=(\d+) gaps=(\d+)} $log_text] {
        if {$rm == 1} {
            incr dmetrics
            if {$gaps != 0} { return "frame D output gaps=$gaps, expected 0" }
        }
    }
    if {$dmetrics != 1} {
        return "expected exactly 1 ready_mode=1 EDGE_METRICS record, got $dmetrics"
    }
    if {![regexp {EDGE_LATENCY start_to_first_output=} $log_text]} {
        return "missing start_to_first_output latency record"
    }
    if {![regexp {EDGE_LATENCY start_to_done=} $log_text]} {
        return "missing start_to_done latency record"
    }
    return ""
}

set built_enabled $enabled
set expected_policy_enabled [expr {$expect_checker_fail ? "true" : $enabled}]
set check_fail [check_metrics $log_text $built_enabled $expected_policy_enabled]

if {$expect_checker_fail} {
    if {$check_fail eq ""} {
        error "Negative control unexpectedly PASSED the metric checker; the checker does not detect the regression"
    }
    if {$check_fail ne "frame D invalid_advances=62, expected 0"} {
        error "Negative control failed for an unexpected reason: $check_fail"
    }
    puts "EDGE_NEGATIVE_CONTROL_FAIL_AS_EXPECTED: $check_fail"
} else {
    if {$check_fail ne ""} {
        error "Metric acceptance checker failed: $check_fail"
    }
    puts "EDGE_REGRESSION_PASS variant=$variant"
}
close_project
