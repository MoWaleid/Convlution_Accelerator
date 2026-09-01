# Reproducibly create the Zynq-7020 accelerator + AXI DMA block design.
# Run with Vivado 2025.2 from this repository, for example:
#   vivado -mode batch -source scripts/create_accelerator_dma_bd.tcl

set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ..]]
set project_file [file join $project_root Convlution_Accelerator.xpr]
set rtl_dir [file join $project_root Convlution_Accelerator.srcs sources_1 new]
set design_name accelerator_dma

if {[llength [get_projects -quiet]] == 0} {
    open_project $project_file
}

if {[file normalize [get_property DIRECTORY [current_project]]] ne $project_root} {
    error "Open project is not $project_file"
}

if {[llength [get_bd_designs -quiet $design_name]] != 0} {
    error "Block design '$design_name' already exists; remove it explicitly before rerunning this creation script."
}

# Module references require automatic source management. Register all wrapper
# dependencies that were added after the original project was created.
set_property source_mgmt_mode All [current_project]
set rtl_files [list \
    [file join $rtl_dir config_pkg.vhd] \
    [file join $rtl_dir conv_pkg.vhd] \
    [file join $rtl_dir coeff_bias_shift_regfile.vhd] \
    [file join $rtl_dir axi_lite_ctrl.vhd] \
    [file join $rtl_dir window_generator.vhd] \
    [file join $rtl_dir conv_channel.vhd] \
    [file join $rtl_dir conv_engine.vhd] \
    [file join $rtl_dir conv_top.vhd] \
    [file join $rtl_dir sync_fifo.vhd] \
    [file join $rtl_dir axi_stream_input_frontend.vhd] \
    [file join $rtl_dir axi_stream_output_serializer.vhd] \
    [file join $rtl_dir conv_axis_wrapper.vhd] \
    [file join $rtl_dir conv_axis_wrapper_bd.v]]

foreach rtl_file $rtl_files {
    if {[llength [get_files -quiet $rtl_file]] == 0} {
        add_files -fileset sources_1 -norecurse $rtl_file
    }
}
set_property file_type {VHDL 2008} [get_files -quiet *.vhd]
update_compile_order -fileset sources_1

create_bd_design $design_name
current_bd_design $design_name

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:* processing_system7_0]
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}] $ps

set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:* axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_s_axis_s2mm_tdata_width {64} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_include_mm2s_dre {0} \
    CONFIG.c_include_s2mm_dre {0}] $dma

set axil_sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_lite_smartconnect]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $axil_sc

set hp0_sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* hp0_smartconnect]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $hp0_sc

set accelerator [create_bd_cell -type module -reference conv_axis_wrapper_bd conv_axis_wrapper_bd_0]

set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_100m]
set const_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* const_zero]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $const_zero
set const_one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* const_one]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $const_one

# PS control-plane master to the DMA and accelerator AXI-Lite slaves.
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_lite_smartconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_lite_smartconnect/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_lite_smartconnect/M01_AXI] [get_bd_intf_pins conv_axis_wrapper_bd_0/S_AXI]

# DMA memory masters to the PS HP0 DDR port and 64-bit streaming datapath.
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins hp0_smartconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins hp0_smartconnect/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins hp0_smartconnect/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins conv_axis_wrapper_bd_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins conv_axis_wrapper_bd_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# One common 100 MHz PL clock domain.
set clk [get_bd_pins processing_system7_0/FCLK_CLK0]
connect_bd_net $clk \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
    [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] \
    [get_bd_pins rst_100m/slowest_sync_clk] \
    [get_bd_pins axi_lite_smartconnect/aclk] \
    [get_bd_pins hp0_smartconnect/aclk] \
    [get_bd_pins axi_dma_0/*aclk] \
    [get_bd_pins conv_axis_wrapper_bd_0/clk]

# Use PS FCLK_RESET0_N as the active-low external reset source. proc_sys_reset
# distributes synchronous active-low peripheral reset to all PL peripherals.
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_100m/ext_reset_in]
connect_bd_net [get_bd_pins const_one/dout] [get_bd_pins rst_100m/dcm_locked]
connect_bd_net [get_bd_pins const_zero/dout] \
    [get_bd_pins rst_100m/aux_reset_in] \
    [get_bd_pins rst_100m/mb_debug_sys_rst]
connect_bd_net [get_bd_pins rst_100m/peripheral_aresetn] \
    [get_bd_pins axi_lite_smartconnect/aresetn] \
    [get_bd_pins hp0_smartconnect/aresetn] \
    [get_bd_pins axi_dma_0/axi_resetn] \
    [get_bd_pins conv_axis_wrapper_bd_0/resetn]

# PS board interfaces required for later top-level integration.
make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/DDR]
make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/FIXED_IO]

assign_bd_address
set ps_addr_space [get_bd_addr_spaces processing_system7_0/Data]
set dma_seg [lindex [get_bd_addr_segs -quiet -of_objects $ps_addr_space -filter {NAME =~ "*axi_dma_0*"}] 0]
set accelerator_seg [lindex [get_bd_addr_segs -quiet -of_objects $ps_addr_space -filter {NAME =~ "*conv_axis_wrapper_bd_0*"}] 0]
if {$dma_seg eq "" || $accelerator_seg eq ""} {
    error "Could not locate DMA or accelerator AXI-Lite address segment"
}
set_property range  0x00010000 $dma_seg
set_property offset 0x40400000 $dma_seg
set_property range  0x00010000 $accelerator_seg
set_property offset 0x43C00000 $accelerator_seg

validate_bd_design
save_bd_design

puts "Task 5A block design created: $design_name"
puts "AXI DMA address:       [get_property OFFSET $dma_seg] range [get_property RANGE $dma_seg]"
puts "Accelerator address:   [get_property OFFSET $accelerator_seg] range [get_property RANGE $accelerator_seg]"
