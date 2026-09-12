set project_dir [file normalize [file join [file dirname [info script]] ..]]
set source_dir [file join $project_dir Convlution_Accelerator.srcs sources_1 new]
set report_dir [file join $project_dir reports_cfglut engine_ooc]

file mkdir $report_dir
create_project -in_memory -part xc7z020clg484-1

read_vhdl -vhdl2008 [file join $source_dir config_pkg.vhd]
read_vhdl -vhdl2008 [file join $source_dir conv_pkg.vhd]
read_vhdl -vhdl2008 [file join $source_dir cfglut5_kcm.vhd]
read_vhdl -vhdl2008 [file join $source_dir cfglut5_bitheap_3x3.vhd]
read_vhdl -vhdl2008 [file join $source_dir conv_channel.vhd]
read_vhdl -vhdl2008 [file join $source_dir conv_engine.vhd]

synth_design -top conv_engine -part xc7z020clg484-1 -mode out_of_context \
    -generic C_K=16 -generic C_N=3

create_clock -name clk -period 10.000 [get_ports clk]

report_utilization -hierarchical \
    -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -delay_type max -max_paths 20 \
    -file [file join $report_dir timing_synth.rpt]

puts "CFGLUT_ENGINE_SYNTH_COMPLETE"
