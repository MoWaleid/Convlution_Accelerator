set script_dir [file normalize [file dirname [info script]]]
set root [file normalize [file join $script_dir .. ..]]
set rtl [file join $root Convlution_Accelerator.srcs sources_1 new]
set sim [file join $root Convlution_Accelerator.srcs sim_1 new]
set out [file join $root work \
    [format "cfglut_geometry_regression_%s" [clock seconds]]]

create_project cfglut_geometry_regression $out -part xc7z020clg484-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [list \
    [file join $rtl config_pkg.vhd] \
    [file join $rtl conv_pkg.vhd] \
    [file join $rtl cfglut5_kcm.vhd] \
    [file join $rtl cfglut5_bitheap_3x3.vhd] \
    [file join $rtl cfglut5_bitheap_5x5.vhd] \
    [file join $rtl conv_channel.vhd] \
    [file join $rtl conv_engine.vhd]]

add_files -fileset sim_1 -norecurse [list \
    [file join $sim tb_cfglut5_exact.vhd] \
    [file join $sim tb_cfglut5_pipeline.vhd] \
    [file join $sim tb_cfglut5_exact_n5.vhd] \
    [file join $sim tb_cfglut5_pipeline_n5.vhd]]

# The engine uses process(all), so every RTL and testbench source must be
# analyzed as VHDL-2008 just like the production research-build flow.
set_property file_type {VHDL 2008} [get_files *.vhd]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

foreach top {tb_cfglut5_exact tb_cfglut5_pipeline tb_cfglut5_exact_n5 tb_cfglut5_pipeline_n5} {
    set_property top $top [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    close_sim
    puts "CFGLUT_GEOMETRY_TEST_PASS: $top"
}

puts "CFGLUT_GEOMETRY_REGRESSION_PASS"
close_project
