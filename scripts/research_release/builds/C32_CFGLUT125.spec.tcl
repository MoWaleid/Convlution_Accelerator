# C32_CFGLUT125 — C32 geometry (N=5, K=8, 32x32) on the exact CFGLUT5/Dadda
# edge-free datapath at 125 MHz, per the 2026-09-14 five-profile directive.
# First N=5 physical release: consumes the generated cfglut5_bitheap_5x5
# entity (25 taps / 50 signed rows, Dadda targets 42,28,19,13,9,6,4,3,2).
# Reuses the canonical profiles/C32 parameter bundle. Final release name at
# catalog cutover: C32.
set spec(release_id) C32_CFGLUT125
set spec(shape_id) {N5K8W32H32-CVH1}
set spec(n) 5
set spec(k) 8
set spec(w) 32
set spec(h) 32
set spec(build_id_hex) 45463132354b30384e35573332523031
set spec(clock_mhz) 125
set spec(profile) C32_CFGLUT125
set spec(render_config_pkg) 1
set spec(sources) {config_pkg.vhd conv_pkg.vhd sync_fifo.vhd coeff_bias_shift_regfile.vhd axi_lite_ctrl.vhd window_generator.vhd cfglut5_kcm.vhd cfglut5_bitheap_3x3.vhd cfglut5_bitheap_5x5.vhd conv_channel.vhd conv_engine.vhd conv_top.vhd axi_stream_input_frontend.vhd axi_stream_output_serializer.vhd conv_axis_wrapper.vhd conv_axis_wrapper_bd.v}
