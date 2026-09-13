# Fresh, isolated complete-system build; no prior .xpr/.runs cache required.
set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root release variant.tcl]
set out [file join $root work release_$release_mhz]
if {[file exists $out]} { error "Build directory exists: $out. Archive it before rebuilding; nothing was deleted." }
file mkdir $out
create_project edgefree [file join $out project] -part xc7z020clg484-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
set_property source_mgmt_mode All [current_project]
set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]
foreach name {config_pkg conv_pkg sync_fifo coeff_bias_shift_regfile axi_lite_ctrl window_generator cfglut5_kcm cfglut5_bitheap_3x3 conv_channel conv_engine conv_top axi_stream_input_frontend axi_stream_output_serializer conv_axis_wrapper} {
    import_files -norecurse [file join $rtl $name.vhd]
}
import_files -norecurse [file join $rtl conv_axis_wrapper_bd.v]
set_property file_type {VHDL 2008} [get_files *.vhd]
import_files -fileset constrs_1 -norecurse [file join $root Zedboard-Master.xdc]
import_files -norecurse [file join $root Convlution_Accelerator.srcs sources_1 bd accelerator_dma accelerator_dma.bd]
update_compile_order -fileset sources_1
set bd [get_files */accelerator_dma.bd]
open_bd_design $bd
set ps [get_bd_cells processing_system7_0]
if {abs([get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps] - $release_mhz) > 0.001} { error "PS frequency differs from release" }
set dma [get_bd_cells axi_dma_0]
foreach {key value} {c_sg_length_width 22 c_include_sg 0 c_m_axi_mm2s_data_width 64 c_m_axi_s2mm_data_width 64 c_m_axis_mm2s_tdata_width 64 c_s_axis_s2mm_tdata_width 64} {
    if {[get_property CONFIG.$key $dma] != $value} { error "DMA mismatch: $key" }
}
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
set artifacts [file join $out artifacts]
file mkdir $artifacts
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
if {[llength $clocks] != 1 || abs([get_property PERIOD $clocks] - 1000.0/$release_mhz) > 0.001} { error "Wrong physical clock" }
set fd [open [file join $artifacts timing.rpt] r]; set timing [read $fd]; close $fd
if {$wns < 0 || $whs < 0 || [string first "All user specified timing constraints are met." $timing] < 0} { error "Timing failure: setup=$wns hold=$whs; reports preserved" }
set checks [check_timing -verbose -return_string]
set fd [open [file join $artifacts check_timing.rpt] w]; puts $fd $checks; close $fd
if {[regexp {There are [1-9][0-9]* } $checks]} { error "Unresolved timing checks" }
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} { error "DRC errors" }
set fd [open [file join $artifacts route.rpt] r]; set route [read $fd]; close $fd
if {![regexp {nets with routing errors[^:]*:[ ]+0} $route]} { error "Routing is not clean" }
write_checkpoint [file join $artifacts edgefree.routed.dcp]
close_design
# Produce the run-registered bitstream product; write_hw_platform resolves
# the bitstream through the implementation run's output products, so a
# hand-copied file is not sufficient.
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set run_bit [file join [get_property DIRECTORY $impl] accelerator_dma_wrapper.bit]
if {![file exists $run_bit]} { error "Bitstream was not produced by the implementation run" }
file copy -force $run_bit [file join $artifacts edgefree.bit]
write_hw_platform -fixed -include_bit -file [file join $artifacts edgefree.xsa]
set fd [open [file join $artifacts timing_pass.txt] w]
puts $fd "MHz=$release_mhz\nWNS=$wns\nWHS=$whs\nBOARD_VALIDATION=NOT_RUN"
close $fd
puts "EDGEFREE_RELEASE_BUILD_PASS MHz=$release_mhz WNS=$wns WHS=$whs ARTIFACTS=$artifacts"
close_project
