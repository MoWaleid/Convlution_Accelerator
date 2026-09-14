# B32_CFGLUT100 — the exact same CFGLUT5/Dadda, five-stage, edge-free
# research datapath as B32_CFGLUT125, constrained at 100 MHz.  This is the
# common-clock release used for safe FPGA-Manager switching against A32_MAC100
# and for the matched M12 architecture comparison.
set spec(release_id) B32_CFGLUT100
set spec(shape_id) {N3K16W32H32-CVH1}
set spec(n) 3
set spec(k) 16
set spec(w) 32
set spec(h) 32
set spec(build_id_hex) 45463130304b31364e33573332523031
set spec(clock_mhz) 100
set spec(profile) B32_CFGLUT100
set spec(render_config_pkg) 1
set spec(sources) {config_pkg.vhd conv_pkg.vhd sync_fifo.vhd coeff_bias_shift_regfile.vhd axi_lite_ctrl.vhd window_generator.vhd cfglut5_kcm.vhd cfglut5_bitheap_3x3.vhd conv_channel.vhd conv_engine.vhd conv_top.vhd axi_stream_input_frontend.vhd axi_stream_output_serializer.vhd conv_axis_wrapper.vhd conv_axis_wrapper_bd.v}
