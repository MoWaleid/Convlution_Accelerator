# D640_CFGLUT125 — D640 geometry (N=3, K=4, 640x480 VGA) on the exact
# CFGLUT5/Dadda edge-free datapath at 125 MHz, per the 2026-09-14
# five-profile directive. Proves the 640x480 static-image path and the
# 4 MiB u-dma-buf allocation (TX 309444 B, RX 2457600 B, four-guard layout).
# Shares the canonical D640 parameter bundle (same bytes as D32; the
# geometry is the release's own). Final release name at catalog cutover: D640.
set spec(release_id) D640_CFGLUT125
set spec(shape_id) {N3K4W640H480-CVH1}
set spec(n) 3
set spec(k) 4
set spec(w) 640
set spec(h) 480
set spec(build_id_hex) 45463132354e334b30345647412d5231
set spec(clock_mhz) 125
set spec(profile) D640_CFGLUT125
set spec(render_config_pkg) 1
set spec(sources) {config_pkg.vhd conv_pkg.vhd sync_fifo.vhd coeff_bias_shift_regfile.vhd axi_lite_ctrl.vhd window_generator.vhd cfglut5_kcm.vhd cfglut5_bitheap_3x3.vhd cfglut5_bitheap_5x5.vhd conv_channel.vhd conv_engine.vhd conv_top.vhd axi_stream_input_frontend.vhd axi_stream_output_serializer.vhd conv_axis_wrapper.vhd conv_axis_wrapper_bd.v}
