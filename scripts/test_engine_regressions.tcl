# Engine-level arithmetic regressions in the experimental checkout.
# Proves the CFGLUT5 exact arithmetic engine is unaffected by the
# edge-bubble control changes (conv_top CE wiring), which these TBs
# do not instantiate.
set root [file normalize [file join [file dirname [info script]] ..]]
set work_dir [file join $root work engine_sim]
file mkdir $work_dir
create_project -force engine_sim $work_dir -part xc7z020clg484-1
set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]
foreach name {config_pkg conv_pkg sync_fifo coeff_bias_shift_regfile axi_lite_ctrl window_generator cfglut5_kcm cfglut5_bitheap_3x3 conv_channel conv_engine conv_top} {
    add_files -norecurse [file join $rtl $name.vhd]
}
set simsrc [file join $root Convlution_Accelerator.srcs sim_1 new]
add_files -fileset sim_1 -norecurse [list \
    [file join $simsrc tb_cfglut5_exact.vhd] \
    [file join $simsrc tb_cfglut5_k16_smoke.vhd] \
    [file join $simsrc tb_cfglut5_pipeline.vhd]]
add_files -fileset sim_1 -norecurse [file join $root Convlution_Accelerator.srcs sim_1 imports new tb_axi_lite_ctrl.vhd]
set_property file_type {VHDL 2008} [get_files *.vhd]
update_compile_order -fileset sim_1

set checks {
    tb_cfglut5_exact
    {Exact CFGLUT5 KCM + fused compressor regression passed}
    tb_cfglut5_k16_smoke
    {Exact CFGLUT5 K=16 channel/configuration smoke test passed}
    tb_cfglut5_pipeline
    {PIPELINE_125_PASS}
    tb_axi_lite_ctrl
    {AXI_LITE_CTRL COMPLETE UNIT REGRESSION PASS}
}

set failures 0
foreach {top marker} $checks {
    set_property top $top [get_filesets sim_1]
    update_compile_order -fileset sim_1
    catch {close_sim -force}
    launch_simulation -mode behavioral
    run all
    close_sim
    set log_file [file join $work_dir engine_sim.sim sim_1 behav xsim simulate.log]
    set fd [open $log_file r]
    set log_text [read $fd]
    close $fd
    file copy -force $log_file [file join $work_dir ${top}.log]
    if {[string first $marker $log_text] < 0 || [regexp -nocase {(^|\n)(Error:|Failure:|Fatal:)} $log_text]} {
        incr failures
        puts "ENGINE_REGRESSION_FAIL top=$top"
    } else {
        puts "ENGINE_REGRESSION_PASS top=$top"
    }
}
close_project
if {$failures > 0} { error "Engine arithmetic regression failed: $failures marker(s) missing" }
