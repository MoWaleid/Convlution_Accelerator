# Profile-matrix wrapper regression runner (research releases).
#
# Runs the A-H wrapper regression (imports/new/tb_conv_axis_wrapper.vhd)
# against an ISOLATED project whose config_pkg.vhd is the one rendered for a
# research release by `research_release.py prepare <ID>`.  This is the
# five-release generalization of scripts/test_edge_bubbles.tcl (which remains
# the historical K16/N3 edge-fixture evidence).
#
# Usage from the Vivado Tcl console:
#   set argv {B32_CFGLUT125 optimized}; source scripts/research_release/test_profile_wrappers.tcl
# or set the two variables directly before sourcing.  Variants:
#   optimized         prefetch ON  - metric checker must PASS (invalid 0)
#   optimized_stress  prefetch ON + stress fixture
#   baseline          prefetch OFF - expected invalid advances = (N-1)*(rows-1)
#   negative_control  prefetch OFF but checker enforces the optimized
#                     expectation; the run must FAIL with the exact
#                     invalid_advances mismatch (checker self-test)
set script_dir [file normalize [file dirname [info script]]]
set root [file normalize [file join $script_dir .. ..]]
set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]
set sim [file join $root Convlution_Accelerator.srcs sim_1 imports new]

set release_id B32_CFGLUT125
set variant optimized
if {[info exists ::argv] && [llength $::argv] >= 1} {
    set release_id [lindex $::argv 0]
    if {[llength $::argv] >= 2} { set variant [lindex $::argv 1] }
}
if {$variant ni {optimized optimized_stress baseline baseline_stress negative_control}} {
    error "Use optimized, optimized_stress, baseline, baseline_stress or negative_control"
}
set enabled [expr {[string match "optimized*" $variant] ? "true" : "false"}]
set stress  [expr {($variant eq "optimized_stress" || $variant eq "baseline_stress") ? "true" : "false"}]
set expect_checker_fail [expr {$variant eq "negative_control"}]

# Cross-check the rendered identity against the release spec (fail closed).
set rendered_config [file join $root work research_$release_id src config_pkg.vhd]
if {![file isfile $rendered_config]} {
    error "Missing $rendered_config - run: python scripts/research_release/research_release.py prepare $release_id"
}

# The rendered per-release config_pkg is the build-tree source of truth.
set fh [open $rendered_config r]; set cfg_text [read $fh]; close $fh
set spec_path [file join $script_dir builds $release_id.spec.tcl]
set sfh [open $spec_path r]; set spec_text [read $sfh]; close $sfh
set spec_build_id ""; set spec_k ""; set spec_n ""; set spec_w ""
foreach {label pattern dst} {
    build_id {CFG_BUILD_ID\s*:\s*std_logic_vector\(127 downto 0\)\s*:=\s*x"([0-9A-Fa-f]+)"} spec_build_id
    cfg_k    {CFG_K\s*:\s*integer\s*:=\s*(\d+)} spec_k
    cfg_n    {CFG_N\s*:\s*integer\s*:=\s*(\d+)} spec_n
    cfg_w    {CFG_UNPADDED_WIDTH\s*:\s*integer\s*:=\s*(\d+)} spec_w
} {
    regexp -nocase -line $pattern $cfg_text -> $dst
}
regexp -line {set spec\(build_id_hex\)\s+(\S+)} $spec_text -> cat_build_id
regexp -line {set spec\(k\)\s+(\d+)} $spec_text -> cat_k
regexp -line {set spec\(n\)\s+(\d+)} $spec_text -> cat_n
regexp -line {set spec\(w\)\s+(\d+)} $spec_text -> cat_w
if {$spec_build_id ne $cat_build_id || $spec_k ne $cat_k || $spec_n ne $cat_n || $spec_w ne $cat_w} {
    error "$release_id: rendered config_pkg ($spec_build_id K$spec_k N$spec_n W$spec_w) disagrees with spec ($cat_build_id K$cat_k N$cat_n W$cat_w) - re-run research_release.py prepare"
}
puts "PROFILE_WRAPPER_IDENTITY_OK: $release_id K=$spec_k N=$spec_n W=$spec_w build_id=$spec_build_id"

set out [file join $root work \
    [format "profile_wrapper_%s_%s_%s" $release_id $variant [clock seconds]]]

create_project profile_wrapper_sim $out -part xc7z020clg484-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

# All RTL except config_pkg.vhd (rendered per release) and
# conv_axis_wrapper_bd.v (Verilog BD adapter, not part of the RTL sim).
foreach name {conv_pkg sync_fifo coeff_bias_shift_regfile axi_lite_ctrl \
              window_generator cfglut5_kcm cfglut5_bitheap_3x3 \
              cfglut5_bitheap_5x5 conv_channel conv_engine conv_top \
              axi_stream_input_frontend axi_stream_output_serializer \
              conv_axis_wrapper} {
    add_files -norecurse [file join $rtl $name.vhd]
}
add_files -norecurse $rendered_config
add_files -fileset sim_1 -norecurse [file join $sim tb_conv_axis_wrapper.vhd]

set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top conv_axis_wrapper [get_filesets sources_1]
set_property top tb_conv_axis_wrapper [get_filesets sim_1]
set_property generic "G_WINDOW_PREFETCH=$enabled G_REQUIRE_CONTINUOUS=$enabled G_STRESS=$stress" [get_filesets sim_1]
update_compile_order -fileset sim_1

if {$release_id eq "D640_CFGLUT125"} {
    puts "NOTE: D640 simulates 640x480 frames - expect a long xsim run; this is not a hang"
}
launch_simulation -mode behavioral
run all
close_sim

set log_file [file join $out profile_wrapper_sim.sim sim_1 behav xsim simulate.log]
set fd [open $log_file r]
set log_text [read $fd]
close $fd

if {[string first "CONV_AXIS_WRAPPER COMPLETE M4 INTEGRATION REGRESSION PASS" $log_text] < 0 || [regexp -nocase {(^|\n)(Error:|Failure:|Fatal:)} $log_text]} {
    error "Profile wrapper regression failed: $log_file"
}

# ---------------------------------------------------------------------
# Metric acceptance checker (N-aware generalization of test_edge_bubbles.tcl).
# Frames C, D and H emit WINDOW_METRICS; the benchmark frame D is the
# guaranteed-supply / continuously-ready one.  Without prefetch the
# deterministic fixture produces (N-1) invalid advances at each of the
# (rows-1) logical row transitions (N=3/K16 historical fixture: 2*31 = 62).
# ---------------------------------------------------------------------
set expected_invalid_no_prefetch [expr {($spec_n - 1) * ($spec_h - 1)}]
proc check_metrics {log_text built_enabled expected_policy_enabled expected_invalid_no_prefetch} {
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
    set expected_invalid [expr {$expected_policy_enabled ? 0 : $expected_invalid_no_prefetch}]
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
set check_fail [check_metrics $log_text $built_enabled $expected_policy_enabled $expected_invalid_no_prefetch]

if {$expect_checker_fail} {
    if {$check_fail eq ""} {
        error "Negative control unexpectedly PASSED the metric checker; the checker does not detect the regression"
    }
    if {$check_fail ne "frame D invalid_advances=$expected_invalid_no_prefetch, expected 0"} {
        error "Negative control failed for an unexpected reason: $check_fail"
    }
    puts "PROFILE_WRAPPER_NEGATIVE_CONTROL_FAIL_AS_EXPECTED: $check_fail"
} else {
    if {$check_fail ne ""} {
        error "Metric acceptance checker failed: $check_fail"
    }
    puts "PROFILE_WRAPPER_PASS: $release_id $variant"
}
close_project
