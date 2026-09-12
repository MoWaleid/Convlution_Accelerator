# User-run only, after focused software/RTL tests pass.
# vivado -mode batch -source scripts/build_profile.tcl -tclargs B32
# Explicit profile; fresh isolated project/run tree; never reset the live runs.
proc require {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc contained {path root} {
    set p [string tolower [file normalize $path]]
    set r [string tolower [file normalize $root]]
    return [expr {$p eq $r || [string first "$r/" "$p/"] == 0}]
}
proc write_text {path text} {
    set f [open $path {WRONLY CREAT EXCL}]
    puts $f $text
    close $f
}
if {[catch {
require {[llength $argv] == 1} "Usage: -tclargs A32|B32|C32|D32|D640 (no implicit profile)"
set profile [lindex $argv 0]
require {$profile in {A32 B32 C32 D32 D640}} "Unknown profile"
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set intended [file join $root Convlution_Accelerator.xpr]
set python [file join $root .venv Scripts python.exe]
require {[file isfile $intended] && [file isfile $python]} "Expected project/Python missing"
if {[llength [get_projects -quiet]] == 0} { open_project $intended }
set actual [file normalize [file join [get_property DIRECTORY [current_project]] "[get_property NAME [current_project]].xpr"]]
require {[string equal -nocase $actual $intended]} "Wrong open project: $actual"
require {[get_property PART [current_project]] eq "xc7z020clg484-1"} "Wrong FPGA part"
require {[get_property TOP [get_filesets sources_1]] eq "accelerator_dma_wrapper"} "Wrong integrated top"

# Unique directory names do NOT generate release IDs. IDs come only from catalog.
set tag "[clock format [clock seconds] -gmt 1 -format %Y%m%d_%H%M%S]_[pid]_[clock clicks]"
set out [file join $root profile_builds "${profile}_$tag"]
require {![file exists $out]} "Output already exists: $out"
file mkdir $out
puts "BUILD_PROFILE: OUTPUT $out"
puts [exec $python -B [file join $script_dir prepare_profile.py] --profile $profile --out [file join $out inputs]]
# Snapshot input config/ID before any synthesis. Keep original project untouched.
set clone [file join $out project]
save_project_as -exclude_run_results "M7_$profile" $clone
require {[contained [get_property DIRECTORY [current_project]] $clone]} "Project clone did not become current"
require {[get_property NAME [current_project]] eq "M7_$profile"} "Wrong cloned project"
# Refuse any source alias that could make a subsequent change hit live inputs.
foreach f [get_files -of_objects [get_filesets sources_1]] {
    require {[contained $f $out]} "Clone references external source; stop for review: $f"
}
foreach f [get_files -of_objects [get_filesets constrs_1]] {
    require {[contained $f $out]} "Clone references external constraint; stop for review: $f"
}
set configs [get_files -all -quiet *config_pkg.vhd]
require {[llength $configs] == 1} "Expected one integrated config_pkg"
set config [lindex $configs 0]
require {[contained $config $out]} "Config outside isolated build"
file copy -force [file join $out inputs rtl config_pkg.vhd] $config

# The copied RTL must match the frozen snapshot (except its selected config,
# which was replaced above). Fail if save_project_as kept an unexpected source.
foreach source [glob [file join $out inputs rtl *]] {
    set files [get_files -all -quiet *[file tail $source]]
    require {[llength $files] == 1} "Missing/duplicate RTL [file tail $source]"
    set dest [lindex $files 0]
    set a [open $source rb]; set bytes_a [read $a]; close $a
    set b [open $dest rb]; set bytes_b [read $b]; close $b
    require {$bytes_a eq $bytes_b} "Snapshot/project RTL mismatch: $dest"
}
set bds [get_files -quiet *accelerator_dma.bd]
require {[llength $bds] == 1} "Expected tracked accelerator_dma BD"
set bd [lindex $bds 0]
require {[contained $bd $out]} "BD outside isolated build"
open_bd_design $bd
set dma [get_bd_cells axi_dma_0]
require {[llength $dma] == 1} "DMA instance missing"
foreach {key value} {
    c_sg_length_width 22
    c_m_axi_mm2s_data_width 64
    c_m_axi_s2mm_data_width 64
    c_m_axis_mm2s_tdata_width 64
    c_s_axis_s2mm_tdata_width 64
    c_include_sg 0
} {
    require {[get_property CONFIG.$key $dma] == $value} "BD DMA mismatch: $key"
}
set ps [get_bd_cells processing_system7_0]
require {[llength $ps] == 1} "PS instance missing"
require {[get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps] == 100} "Expected 100 MHz FCLK0"
set accelerator [get_bd_cells conv_axis_wrapper_bd_0]
require {[llength $accelerator] == 1} "Integrated BD adapter missing"
update_module_reference $accelerator
validate_bd_design
save_bd_design
generate_target all $bd
update_compile_order -fileset sources_1
# Only isolated runs are reset; named A32 bitstreams/checkpoints are never touched.
foreach run {synth_1 impl_1} {
    require {[contained [get_property DIRECTORY [get_runs $run]] $out]} "Run outside isolated build"
    set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs $run]
    set_property INCREMENTAL_CHECKPOINT "" [get_runs $run]
}
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
require {[get_property STATUS [get_runs synth_1]] eq "synth_design Complete!"} "Synthesis failed"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
require {[get_property STATUS [get_runs impl_1]] eq "write_bitstream Complete!"} "Implementation failed"

# Query the completed routed design, never a closed/stale synthesis context.
open_run impl_1
set artifacts [file join $out artifacts]
file mkdir $artifacts
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $artifacts timing_summary.rpt]
report_utilization -hierarchical -file [file join $artifacts utilization.rpt]
report_route_status -file [file join $artifacts route_status.rpt]
set checks [check_timing -verbose -return_string]
write_text [file join $artifacts check_timing.rpt] $checks
report_drc -file [file join $artifacts drc.rpt]
set setup [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
require {[llength $setup] == 1 && [llength $hold] == 1} "Timing paths missing"
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
write_text [file join $out build_status.txt] "profile=$profile\nWNS=$wns\nWHS=$whs\nQualification=NOT_QUALIFIED"
require {[string is double -strict $wns] && [string is double -strict $whs]} "Invalid timing result"
require {$wns >= 0 && $whs >= 0} "TIMING_FAIL: WNS=$wns WHS=$whs"
set f [open [file join $artifacts timing_summary.rpt] r]; set summary [read $f]; close $f
require {[string first "All user specified timing constraints are met." $summary] >= 0} "Timing summary did not pass (includes pulse-width checks)"
require {![regexp {There are [1-9][0-9]* } $checks]} "Unresolved check_timing findings"
require {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]] == 0} "DRC errors"
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit [file join $impl_dir accelerator_dma_wrapper.bit]
require {[file isfile $bit]} "Missing bitstream"
file copy $bit [file join $artifacts "$profile.bit"]
write_checkpoint [file join $artifacts "$profile.routed.dcp"]
write_hw_platform -fixed -include_bit -file [file join $artifacts "$profile.xsa"]
# Hash finalized inputs and exported artifacts, without importing application code.
set hash_code {
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = [root / "build_status.txt"]
for directory in ("inputs", "artifacts"):
    files += [p for p in (root / directory).rglob("*") if p.is_file()]
with (root / "SHA256SUMS.txt").open("x", encoding="ascii") as output:
    for p in sorted(files):
        output.write(hashlib.sha256(p.read_bytes()).hexdigest()+"  "+p.relative_to(root).as_posix()+"\n")
}
exec $python -B -c $hash_code $out
puts "BUILD_PROFILE: TIMING_PASS $profile WNS=$wns WHS=$whs"
puts "BUILD_PROFILE: NOT_QUALIFIED -- M5 tests, fitting/stream/geometry review, M7 switching and cold-boot gates still required"
puts "BUILD_PROFILE: ARTIFACTS $artifacts"



} build_failure]} {
    puts stderr "BUILD_PROFILE: FAIL $build_failure"
    exit 1
}
exit 0
