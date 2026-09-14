# research_build.tcl — fresh, isolated research-line build (M10 Gate 1, D3).
# Adapted from the teammate release flow (00a6e11 release_build.tcl) with our
# identity discipline: the build is driven by a checked spec
# (builds/<RELEASE_ID>.spec.tcl) that research_release.py cross-validates
# against profiles/m7_profiles.json releases entries (shape_id + build_id),
# and every artifact lands under work/research_<ID>/artifacts with a
# build-input manifest assembled by the driver.
#
# Invocation:
#   batch:  vivado -mode batch -source scripts/research_release/research_build.tcl -tclargs <RELEASE_ID>
#   GUI:    set research_release_id <RELEASE_ID>
#           source scripts/research_release/research_build.tcl
#
# Fail-closed: the output directory must either not exist (for specs that do
# not render config_pkg) or contain only the prepared rendered config_pkg.
# Stale projects/artifacts are never reused. Timing/DRC/route gates must pass;
# exactly one clock at the spec frequency; the isolated imported BD is set to
# the checked profile clock and must retain the approved DMA configuration.

set script_dir [file normalize [file dirname [info script]]]
set root [file normalize [file join $script_dir .. ..]]

if {![info exists research_release_id]} {
    if {[info exists argv] && [llength $argv] >= 1} {
        set research_release_id [lindex $argv 0]
    } else {
        error "Usage: set research_release_id <ID>; source scripts/research_release/research_build.tcl\n       or: vivado -mode batch -source scripts/research_release/research_build.tcl -tclargs <ID>"
    }
}

source [file join $script_dir builds ${research_release_id}.spec.tcl]
foreach key {release_id shape_id n k w h build_id_hex clock_mhz profile render_config_pkg sources} {
    if {![info exists spec($key)]} { error "spec missing key: $key" }
}
if {$spec(release_id) ne $research_release_id} { error "spec release_id mismatch" }

set out [file join $root work research_${research_release_id}]
set rendered_config [file join $out src config_pkg.vhd]
if {[file exists $out]} {
    if {!$spec(render_config_pkg)} {
        error "Build directory exists: $out. Archive it before rebuilding; nothing was deleted."
    }
    set out_entries [glob -nocomplain -tails -directory $out *]
    set src_entries [glob -nocomplain -tails -directory [file join $out src] *]
    if {$out_entries ne {src} || $src_entries ne {config_pkg.vhd} || ![file isfile $rendered_config]} {
        error "Prepared build directory is not pristine: expected only src/config_pkg.vhd under $out. Nothing was deleted."
    }
} else {
    if {$spec(render_config_pkg)} {
        error "Rendered config missing: run research_release.py prepare $research_release_id first"
    }
    file mkdir $out
}
set artifacts [file join $out artifacts]
file mkdir $artifacts

set fd [open [file join $artifacts tool.txt] w]
puts $fd [version -short]
close $fd

create_project research_$research_release_id [file join $out project] -part xc7z020clg484-1
set zedboard_part digilentinc.com:zedboard:part0:1.1
set board_repo_candidates {}
if {[info exists env(VIVADO_BOARD_REPO_PATHS)]} {
    foreach repo [split $env(VIVADO_BOARD_REPO_PATHS) ";"] {
        if {$repo ne ""} { lappend board_repo_candidates [file normalize $repo] }
    }
}
if {[info exists env(APPDATA)]} {
    set vivado_version [version -short]
    lappend board_repo_candidates [file normalize [file join \
        $env(APPDATA) Xilinx Vivado $vivado_version xhub board_store \
        xilinx_board_store XilinxBoardStore Vivado $vivado_version boards]]
}
foreach repo $board_repo_candidates {
    if {![file isdirectory $repo]} { continue }
    set_property board_part_repo_paths [list $repo] [current_project]
    if {[llength [get_board_parts -quiet $zedboard_part]]} {
        puts "ZEDBOARD_REPO: $repo"
        break
    }
}
if {![llength [get_board_parts -quiet $zedboard_part]]} {
    error "Required board part is unavailable: $zedboard_part. Install the board files or set VIVADO_BOARD_REPO_PATHS."
}
set_property board_part $zedboard_part [current_project]
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property source_mgmt_mode All [current_project]

set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]
set imported {}
foreach name $spec(sources) {
    if {$name eq "config_pkg.vhd" && $spec(render_config_pkg)} {
        # Rendered by research_release.py from the repo template + spec.
        # Each selected-profile constant is replaced exactly once; the repo
        # template itself is never touched.
        set path [file join $out src config_pkg.vhd]
    } else {
        set path [file join $rtl $name]
    }
    if {![file exists $path]} { error "source missing: $path" }
    lappend imported $path
}
foreach path $imported {
    import_files -norecurse $path
}
set_property file_type {VHDL 2008} [get_files *.vhd]
import_files -fileset constrs_1 -norecurse [file join $root Zedboard-Master.xdc]
set bd_path [file join $root Convlution_Accelerator.srcs sources_1 bd accelerator_dma accelerator_dma.bd]
if {![file exists $bd_path]} { error "block design missing: $bd_path" }
import_files -norecurse $bd_path
update_compile_order -fileset sources_1

set bd [get_files */accelerator_dma.bd]
open_bd_design $bd
set ps [get_bd_cells processing_system7_0]
set preset_clock_mhz [get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ $ps]
set_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $spec(clock_mhz) $ps
set actual_clock_mhz [get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ $ps]
if {abs($actual_clock_mhz - $spec(clock_mhz)) > 0.001} {
    error "Unable to apply spec clock $spec(clock_mhz) MHz to isolated BD: effective frequency is $actual_clock_mhz MHz"
}
puts "BD_CLOCK: board preset $preset_clock_mhz MHz -> isolated profile $actual_clock_mhz MHz"
set dma [get_bd_cells axi_dma_0]
foreach {key value} {c_sg_length_width 22 c_include_sg 0 c_m_axi_mm2s_data_width 64 c_m_axi_s2mm_data_width 64 c_m_axis_mm2s_tdata_width 64 c_s_axis_s2mm_tdata_width 64} {
    if {[get_property CONFIG.$key $dma] != $value} { error "DMA mismatch: $key" }
}
set ilas [get_bd_cells -quiet -filter {VLNV =~ *system_ila*}]
if {[llength $ilas] != 0} { error "System ILA present in the release BD" }
update_module_reference accelerator_dma_conv_axis_wrapper_bd_0_0
validate_bd_design
save_bd_design
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property top accelerator_dma_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "Synthesis failed" }
set impl [get_runs impl_1]
set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED false $impl
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 4
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS $impl]]} { error "Implementation failed" }
open_run impl_1

report_timing_summary -delay_type min_max -report_unconstrained -file [file join $artifacts timing.rpt]
report_utilization -hierarchical -file [file join $artifacts utilization.rpt]
report_route_status -file [file join $artifacts route.rpt]
report_drc -file [file join $artifacts drc.rpt]
report_methodology -file [file join $artifacts methodology.rpt]
report_power -file [file join $artifacts power.rpt]
report_timing -max_paths 100 -nworst 1 -file [file join $artifacts top100.rpt]

set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set clocks [get_clocks]
if {[llength $clocks] != 1 || abs([get_property PERIOD $clocks] - 1000.0/$spec(clock_mhz)) > 0.001} {
    error "Wrong physical clock: expected exactly one at $spec(clock_mhz) MHz"
}
set fd [open [file join $artifacts timing.rpt] r]; set timing [read $fd]; close $fd
if {$wns < 0 || $whs < 0 || [string first "All user specified timing constraints are met." $timing] < 0} {
    error "Timing failure: setup=$wns hold=$whs; reports preserved"
}
set checks [check_timing -verbose -return_string]
set fd [open [file join $artifacts check_timing.rpt] w]; puts $fd $checks; close $fd
if {[regexp {There are [1-9][0-9]* } $checks]} { error "Unresolved timing checks" }
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} { error "DRC errors" }
set fd [open [file join $artifacts route.rpt] r]; set route [read $fd]; close $fd
if {![regexp {nets with routing errors[^:]*:[ ]+0} $route]} { error "Routing is not clean" }
write_checkpoint [file join $artifacts research.routed.dcp]
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set run_bit [file join [get_property DIRECTORY $impl] accelerator_dma_wrapper.bit]
if {![file exists $run_bit]} { error "Bitstream was not produced by the implementation run" }
file copy -force $run_bit [file join $artifacts ${research_release_id}.bit]
write_hw_platform -fixed -include_bit -file [file join $artifacts ${research_release_id}.xsa]

set fd [open [file join $artifacts results.txt] w]
puts $fd "release_id=$research_release_id"
puts $fd "shape_id=$spec(shape_id)"
puts $fd "MHz=$spec(clock_mhz)"
puts $fd "WNS=$wns"
puts $fd "WHS=$whs"
puts $fd "BOARD_VALIDATION=NOT_RUN"
close $fd
puts "RESEARCH_BUILD_OK: $research_release_id WNS=$wns WHS=$whs -> $artifacts"
