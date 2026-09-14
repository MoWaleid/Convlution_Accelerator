# Profile-matrix wrapper regression runner (research releases).
#
# Runs the A-H wrapper regression (imports/new/tb_conv_axis_wrapper.vhd)
# against an ISOLATED project whose config_pkg.vhd is the one rendered for a
# research release by `research_release.py prepare <ID>`.  This is the
# five-release generalization of scripts/test_edge_bubbles.tcl (which remains
# the historical K16/N3 edge-fixture evidence).
#
# Usage from the Vivado Tcl console (match the research_build.tcl pattern):
#   close_project   ;# only if another sim project from a prior run is open
#   set profile_wrapper_release B32_CFGLUT125
#   set profile_wrapper_variant optimized
#   source scripts/research_release/test_profile_wrappers.tcl
# (Unset variables default to B32_CFGLUT125 / optimized.  The GUI console's
# ::argv carries Vivado's own launch arguments, so it is deliberately not
# consulted.)  Variants:
#   optimized         prefetch ON, zero-gap assert ON  - full edge-free claim
#   optimized_relaxed prefetch ON, zero-gap assert OFF - functional gate for
#                     profiles where the gapless claim is not proven (K4, N5);
#                     measured transition bubbles are recorded, not asserted
#   optimized_stress  prefetch ON + stress fixture
#   baseline          prefetch OFF - expected invalid advances = (N-1)*(rows-1)
#   negative_control  prefetch OFF but checker enforces the optimized
#                     expectation; the run must FAIL with the exact
#                     invalid_advances mismatch (checker self-test)
#
# Claim scope (wrapper evidence, 2026-09-14): the edge-free zero-bubble
# property is proven for N=3 with K>=8 (B32_CFGLUT125, A32_CFGLUT125).
# K=4 (D32/D640) and N=5 (C32) show engine bubbles at row transitions that
# surface externally on the continuous-sink frame; run those with
# optimized_relaxed and record the measured values.
set script_dir [file normalize [file dirname [info script]]]
set root [file normalize [file join $script_dir .. ..]]
set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]
set sim [file join $root Convlution_Accelerator.srcs sim_1 imports new]

set release_id B32_CFGLUT125
set variant optimized
if {[info exists profile_wrapper_release]} { set release_id $profile_wrapper_release }
if {[info exists profile_wrapper_variant]} { set variant $profile_wrapper_variant }
if {$variant ni {optimized optimized_relaxed optimized_stress baseline baseline_stress negative_control}} {
    error "Use optimized, optimized_relaxed, optimized_stress, baseline, baseline_stress or negative_control"
}
set enabled [expr {[string match "optimized*" $variant] ? "true" : "false"}]
set stress  [expr {($variant eq "optimized_stress" || $variant eq "baseline_stress") ? "true" : "false"}]
set expect_checker_fail [expr {$variant eq "negative_control"}]
set require_continuous [expr {($variant eq "optimized_relaxed") ? "false" : $enabled}]

# Cross-check the rendered identity against the release spec (fail closed).
set rendered_config [file join $root work research_$release_id src config_pkg.vhd]
if {![file isfile $rendered_config]} {
    error "Missing $rendered_config - run: python scripts/research_release/research_release.py prepare $release_id"
}

# The rendered per-release config_pkg is the build-tree source of truth.
set fh [open $rendered_config r]; set cfg_text [read $fh]; close $fh
set spec_path [file join $script_dir builds $release_id.spec.tcl]
if {![file isfile $spec_path]} {
    error "Missing release spec: $spec_path"
}
set sfh [open $spec_path r]; set spec_text [read $sfh]; close $sfh
set spec_build_id ""; set spec_k ""; set spec_n ""; set spec_w ""; set spec_h ""
foreach {label pattern dst} {
    build_id {CFG_BUILD_ID\s*:\s*std_logic_vector\(127 downto 0\)\s*:=\s*x"([0-9A-Fa-f]+)"} spec_build_id
    cfg_k    {CFG_K\s*:\s*integer\s*:=\s*(\d+)} spec_k
    cfg_n    {CFG_N\s*:\s*integer\s*:=\s*(\d+)} spec_n
    cfg_w    {CFG_UNPADDED_WIDTH\s*:\s*integer\s*:=\s*(\d+)} spec_w
    cfg_h    {CFG_UNPADDED_HEIGHT\s*:\s*integer\s*:=\s*(\d+)} spec_h
} {
    # GLM-F2: every regexp return is checked; a failed parse must not
    # inherit a stale variable from an interactive Vivado session.
    if {![regexp -nocase -line $pattern $cfg_text -> $dst]} {
        error "$release_id: rendered config_pkg is missing $label - re-run research_release.py prepare"
    }
}
foreach {label pattern dst} {
    build_id {set spec\(build_id_hex\)\s+(\S+)} cat_build_id
    spec_k   {set spec\(k\)\s+(\d+)} cat_k
    spec_n   {set spec\(n\)\s+(\d+)} cat_n
    spec_w   {set spec\(w\)\s+(\d+)} cat_w
    spec_h   {set spec\(h\)\s+(\d+)} cat_h
} {
    if {![regexp -line $pattern $spec_text -> $dst]} {
        error "$release_id: release spec is missing $label"
    }
}
if {$spec_build_id ne $cat_build_id || $spec_k ne $cat_k || $spec_n ne $cat_n || $spec_w ne $cat_w || $spec_h ne $cat_h} {
    error "$release_id: rendered config_pkg ($spec_build_id K$spec_k N$spec_n W$spec_w H$spec_h) disagrees with spec ($cat_build_id K$cat_k N$cat_n W$cat_w H$cat_h) - re-run research_release.py prepare"
}
set release_driver [file join $script_dir research_release.py]
if {[catch {exec python -B $release_driver verify-render $release_id} render_check]} {
    error "$release_id: deterministic rendered-config verification failed: $render_check"
}
puts $render_check
puts "PROFILE_WRAPPER_IDENTITY_OK: $release_id K=$spec_k N=$spec_n W=$spec_w H=$spec_h build_id=$spec_build_id"

set run_nonce [format "%s_%s" [clock microseconds] [pid]]
set out [file join $root work \
    [format "profile_wrapper_%s_%s_%s" $release_id $variant $run_nonce]]
if {[file exists $out]} {
    error "Refusing to reuse wrapper evidence directory: $out"
}

# Bind every official result to a clean tracked source state and the exact
# rendered config. Untracked work/ outputs are allowed; tracked source edits
# must be committed before qualification.
if {[catch {exec git -C $root diff --quiet}]} {
    error "Tracked unstaged changes exist; commit or revert them before official qualification"
}
if {[catch {exec git -C $root diff --cached --quiet}]} {
    error "Tracked staged changes exist; commit them before official qualification"
}
set git_commit [string trim [exec git -C $root rev-parse HEAD]]

proc official_sha256 {path} {
    if {[catch {exec certutil -hashfile $path SHA256} out]} {
        error "certutil could not hash $path"
    }
    if {![regexp -nocase {(^|\n)([0-9a-f]{64})(\r?$|\n)} $out -> _ hex]} {
        error "certutil returned no canonical SHA-256 for $path"
    }
    return [string tolower $hex]
}

set tb_path [file normalize [file join $sim tb_conv_axis_wrapper.vhd]]
set runner_path [file normalize [info script]]

# A prior failed run leaves profile_wrapper_sim open; close only that one.
# Any other open project (e.g. the main Vivado project) must be closed by the
# user before sourcing this script.
if {![catch {current_project}]} {
    if {[get_property NAME [current_project]] eq "profile_wrapper_sim"} {
        close_project
    } else {
        error "Close the currently open Vivado project before running the isolated wrapper regression"
    }
}

create_project profile_wrapper_sim $out -part xc7z020clg484-1
set meta_fd [open [file join $out run_meta.txt] w]
puts $meta_fd "release_id=$release_id"
puts $meta_fd "variant=$variant"
puts $meta_fd "git_commit=$git_commit"
puts $meta_fd "vivado=[version -short]"
puts $meta_fd "runner=$runner_path"
puts $meta_fd "runner_sha256=[official_sha256 $runner_path]"
puts $meta_fd "testbench=$tb_path"
puts $meta_fd "testbench_sha256=[official_sha256 $tb_path]"
puts $meta_fd "rendered_config=$rendered_config"
puts $meta_fd "rendered_config_sha256=[official_sha256 $rendered_config]"
close $meta_fd
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
add_files -fileset sim_1 -norecurse $tb_path

set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top conv_axis_wrapper [get_filesets sources_1]
set_property top tb_conv_axis_wrapper [get_filesets sim_1]
set_property generic "G_WINDOW_PREFETCH=$enabled G_REQUIRE_CONTINUOUS=$require_continuous G_STRESS=$stress" [get_filesets sim_1]
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
#
# gapless_expected gates the external zero-bubble assertion. Option A makes
# this an explicit release claim for A32/B32 only; it must not expand to a
# future geometry merely because that geometry also has N=3 and K>=8.
# ---------------------------------------------------------------------
set expected_invalid_no_prefetch [expr {($spec_n - 1) * ($spec_h - 1)}]
set gapless_expected [expr {$release_id in {A32_CFGLUT125 B32_CFGLUT125}}]
proc check_metrics {log_text built_enabled expected_policy_enabled expected_invalid_no_prefetch gapless_expected spec_k} {
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
    set dmetrics 0
    set dgaps ""
    foreach {_ rm gaps} [regexp -all -inline -line \
        {EDGE_METRICS prefetch=\w+ ready_mode=(\d+) gaps=(\d+)} $log_text] {
        if {$rm == 1} {
            incr dmetrics
            set dgaps $gaps
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
    if {!$gapless_expected} {
        puts "PROFILE_WRAPPER_EDGE_GAP_KNOWN: frame D invalid_advances=[lindex $d 2] gaps=$dgaps (edge-free zero-bubble claim not proven for this geometry; recorded, not asserted)"
        return ""
    }
    # Internal zero-bubble (no engine advance on an invalid window) is the
    # stricter tier proven at K16 (B32).  K8 (A32) deterministically absorbs
    # one internal bubble per row transition behind two output beats per
    # position; recorded, not asserted.
    if {$spec_k == 16} {
        set expected_invalid [expr {$expected_policy_enabled ? 0 : $expected_invalid_no_prefetch}]
        if {[lindex $d 2] != $expected_invalid} {
            return "frame D invalid_advances=[lindex $d 2], expected $expected_invalid"
        }
    } else {
        puts "PROFILE_WRAPPER_INTERNAL_BUBBLES_RECORDED: frame D invalid_advances=[lindex $d 2] (external output gapless; internal tier proven at K16 only)"
    }
    if {$expected_policy_enabled} {
        # Option A's published claim is external continuity. A32 may contain
        # internal invalid-window advances that its serializer hides.
        if {$dgaps != 0} {
            return "frame D output gaps=$dgaps, expected 0"
        }
    } else {
        puts "PROFILE_WRAPPER_BASELINE_GAPS_RECORDED: frame D gaps=$dgaps"
    }
    return ""
}

set built_enabled $enabled
set expected_policy_enabled [expr {$expect_checker_fail ? "true" : $enabled}]
set check_fail [check_metrics $log_text $built_enabled $expected_policy_enabled \
                    $expected_invalid_no_prefetch $gapless_expected $spec_k]

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
    set terminal_marker "PROFILE_WRAPPER_PASS: $release_id $variant"
    set result_fd [open [file join $out run_result.txt] w]
    puts $result_fd "PROFILE_WRAPPER_IDENTITY_OK: $release_id K=$spec_k N=$spec_n W=$spec_w H=$spec_h build_id=$spec_build_id"
    puts $result_fd $terminal_marker
    puts $result_fd "OPTION_A_EXTERNAL_GAPLESS_CLAIM=[expr {$gapless_expected ? {yes} : {no}}]"
    close $result_fd
    puts $terminal_marker
}
close_project
