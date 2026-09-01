# ZedBoard PS preset copied from the local known-good zedboard_platform
# system.bd (xc7z020clg484-1, ZedBoard board-part).  It captures DDR,
# MIO electrical settings, UART1, SD0, Ethernet/RGMII, and MDIO exactly.
# The accelerator design restores its required AXI ports after calling this.
proc apply_zedboard_ps_platform {ps_cell} {
    if {[llength [get_bd_cells -quiet $ps_cell]] != 1} {
        error "Expected one processing_system7 cell: $ps_cell"
    }

    set_property -dict [list \
        CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {650} \
        CONFIG.PCW_CLK0_FREQ {100000000} \
        CONFIG.PCW_CLK1_FREQ {10000000} \
        CONFIG.PCW_CLK2_FREQ {10000000} \
        CONFIG.PCW_CLK3_FREQ {10000000} \
        CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
        CONFIG.PCW_DDR_RAM_HIGHADDR {0x1FFFFFFF} \
        CONFIG.PCW_EN_EMIO_TTC0 {1} \
        CONFIG.PCW_EN_EMIO_WP_SDIO0 {1} \
        CONFIG.PCW_EN_ENET0 {1} \
        CONFIG.PCW_EN_GPIO {1} \
        CONFIG.PCW_EN_QSPI {1} \
        CONFIG.PCW_EN_SDIO0 {1} \
        CONFIG.PCW_EN_TTC0 {1} \
        CONFIG.PCW_EN_UART1 {1} \
        CONFIG.PCW_EN_USB0 {1} \
        CONFIG.PCW_ENET_RESET_ENABLE {1} \
        CONFIG.PCW_ENET_RESET_SELECT {Share reset pin} \
        CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
        CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
        CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
        CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {1000 Mbps} \
        CONFIG.PCW_ENET0_RESET_ENABLE {0} \
        CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
        CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
        CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO} \
        CONFIG.PCW_I2C_RESET_ENABLE {1} \
        CONFIG.PCW_MIO_0_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_0_PULLUP {enabled} \
        CONFIG.PCW_MIO_0_SLEW {slow} \
        CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_1_PULLUP {disabled} \
        CONFIG.PCW_MIO_1_SLEW {fast} \
        CONFIG.PCW_MIO_10_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_10_PULLUP {enabled} \
        CONFIG.PCW_MIO_10_SLEW {slow} \
        CONFIG.PCW_MIO_11_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_11_PULLUP {enabled} \
        CONFIG.PCW_MIO_11_SLEW {slow} \
        CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_12_PULLUP {enabled} \
        CONFIG.PCW_MIO_12_SLEW {slow} \
        CONFIG.PCW_MIO_13_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_13_PULLUP {enabled} \
        CONFIG.PCW_MIO_13_SLEW {slow} \
        CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_14_PULLUP {enabled} \
        CONFIG.PCW_MIO_14_SLEW {slow} \
        CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_15_PULLUP {enabled} \
        CONFIG.PCW_MIO_15_SLEW {slow} \
        CONFIG.PCW_MIO_16_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_16_PULLUP {disabled} \
        CONFIG.PCW_MIO_16_SLEW {fast} \
        CONFIG.PCW_MIO_17_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_17_PULLUP {disabled} \
        CONFIG.PCW_MIO_17_SLEW {fast} \
        CONFIG.PCW_MIO_18_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_18_PULLUP {disabled} \
        CONFIG.PCW_MIO_18_SLEW {fast} \
        CONFIG.PCW_MIO_19_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_19_PULLUP {disabled} \
        CONFIG.PCW_MIO_19_SLEW {fast} \
        CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_2_SLEW {fast} \
        CONFIG.PCW_MIO_20_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_20_PULLUP {disabled} \
        CONFIG.PCW_MIO_20_SLEW {fast} \
        CONFIG.PCW_MIO_21_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_21_PULLUP {disabled} \
        CONFIG.PCW_MIO_21_SLEW {fast} \
        CONFIG.PCW_MIO_22_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_22_PULLUP {disabled} \
        CONFIG.PCW_MIO_22_SLEW {fast} \
        CONFIG.PCW_MIO_23_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_23_PULLUP {disabled} \
        CONFIG.PCW_MIO_23_SLEW {fast} \
        CONFIG.PCW_MIO_24_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_24_PULLUP {disabled} \
        CONFIG.PCW_MIO_24_SLEW {fast} \
        CONFIG.PCW_MIO_25_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_25_PULLUP {disabled} \
        CONFIG.PCW_MIO_25_SLEW {fast} \
        CONFIG.PCW_MIO_26_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_26_PULLUP {disabled} \
        CONFIG.PCW_MIO_26_SLEW {fast} \
        CONFIG.PCW_MIO_27_IOTYPE {HSTL 1.8V} \
        CONFIG.PCW_MIO_27_PULLUP {disabled} \
        CONFIG.PCW_MIO_27_SLEW {fast} \
        CONFIG.PCW_MIO_28_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_28_PULLUP {disabled} \
        CONFIG.PCW_MIO_28_SLEW {fast} \
        CONFIG.PCW_MIO_29_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_29_PULLUP {disabled} \
        CONFIG.PCW_MIO_29_SLEW {fast} \
        CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_3_SLEW {fast} \
        CONFIG.PCW_MIO_30_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_30_PULLUP {disabled} \
        CONFIG.PCW_MIO_30_SLEW {fast} \
        CONFIG.PCW_MIO_31_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_31_PULLUP {disabled} \
        CONFIG.PCW_MIO_31_SLEW {fast} \
        CONFIG.PCW_MIO_32_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_32_PULLUP {disabled} \
        CONFIG.PCW_MIO_32_SLEW {fast} \
        CONFIG.PCW_MIO_33_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_33_PULLUP {disabled} \
        CONFIG.PCW_MIO_33_SLEW {fast} \
        CONFIG.PCW_MIO_34_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_34_PULLUP {disabled} \
        CONFIG.PCW_MIO_34_SLEW {fast} \
        CONFIG.PCW_MIO_35_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_35_PULLUP {disabled} \
        CONFIG.PCW_MIO_35_SLEW {fast} \
        CONFIG.PCW_MIO_36_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_36_PULLUP {disabled} \
        CONFIG.PCW_MIO_36_SLEW {fast} \
        CONFIG.PCW_MIO_37_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_37_PULLUP {disabled} \
        CONFIG.PCW_MIO_37_SLEW {fast} \
        CONFIG.PCW_MIO_38_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_38_PULLUP {disabled} \
        CONFIG.PCW_MIO_38_SLEW {fast} \
        CONFIG.PCW_MIO_39_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_39_PULLUP {disabled} \
        CONFIG.PCW_MIO_39_SLEW {fast} \
        CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_4_SLEW {fast} \
        CONFIG.PCW_MIO_40_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_40_PULLUP {disabled} \
        CONFIG.PCW_MIO_40_SLEW {fast} \
        CONFIG.PCW_MIO_41_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_41_PULLUP {disabled} \
        CONFIG.PCW_MIO_41_SLEW {fast} \
        CONFIG.PCW_MIO_42_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_42_PULLUP {disabled} \
        CONFIG.PCW_MIO_42_SLEW {fast} \
        CONFIG.PCW_MIO_43_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_43_PULLUP {disabled} \
        CONFIG.PCW_MIO_43_SLEW {fast} \
        CONFIG.PCW_MIO_44_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_44_PULLUP {disabled} \
        CONFIG.PCW_MIO_44_SLEW {fast} \
        CONFIG.PCW_MIO_45_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_45_PULLUP {disabled} \
        CONFIG.PCW_MIO_45_SLEW {fast} \
        CONFIG.PCW_MIO_46_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_46_PULLUP {enabled} \
        CONFIG.PCW_MIO_46_SLEW {slow} \
        CONFIG.PCW_MIO_47_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_47_PULLUP {disabled} \
        CONFIG.PCW_MIO_47_SLEW {slow} \
        CONFIG.PCW_MIO_48_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_48_PULLUP {disabled} \
        CONFIG.PCW_MIO_48_SLEW {slow} \
        CONFIG.PCW_MIO_49_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_49_PULLUP {disabled} \
        CONFIG.PCW_MIO_49_SLEW {slow} \
        CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_5_SLEW {fast} \
        CONFIG.PCW_MIO_50_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_50_PULLUP {disabled} \
        CONFIG.PCW_MIO_50_SLEW {slow} \
        CONFIG.PCW_MIO_51_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_51_PULLUP {disabled} \
        CONFIG.PCW_MIO_51_SLEW {slow} \
        CONFIG.PCW_MIO_52_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_52_PULLUP {disabled} \
        CONFIG.PCW_MIO_52_SLEW {slow} \
        CONFIG.PCW_MIO_53_IOTYPE {LVCMOS 1.8V} \
        CONFIG.PCW_MIO_53_PULLUP {disabled} \
        CONFIG.PCW_MIO_53_SLEW {slow} \
        CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_6_SLEW {fast} \
        CONFIG.PCW_MIO_7_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_7_SLEW {slow} \
        CONFIG.PCW_MIO_8_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_8_SLEW {fast} \
        CONFIG.PCW_MIO_9_IOTYPE {LVCMOS 3.3V} \
        CONFIG.PCW_MIO_9_PULLUP {enabled} \
        CONFIG.PCW_MIO_9_SLEW {slow} \
        CONFIG.PCW_MIO_TREE_PERIPHERALS {GPIO#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#GPIO#Quad SPI Flash#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#USB Reset#SD 0#UART 1#UART 1#GPIO#GPIO#Enet 0#Enet 0} \
        CONFIG.PCW_MIO_TREE_SIGNALS {gpio[0]#qspi0_ss_b#qspi0_io[0]#qspi0_io[1]#qspi0_io[2]#qspi0_io[3]/HOLD_B#qspi0_sclk#gpio[7]#qspi_fbclk#gpio[9]#gpio[10]#gpio[11]#gpio[12]#gpio[13]#gpio[14]#gpio[15]#tx_clk#txd[0]#txd[1]#txd[2]#txd[3]#tx_ctl#rx_clk#rxd[0]#rxd[1]#rxd[2]#rxd[3]#rx_ctl#data[4]#dir#stp#nxt#data[0]#data[1]#data[2]#data[3]#clk#data[5]#data[6]#data[7]#clk#cmd#data[0]#data[1]#data[2]#data[3]#reset#cd#tx#rx#gpio[50]#gpio[51]#mdc#mdio} \
        CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
        CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE {1} \
        CONFIG.PCW_QSPI_GRP_FBCLK_IO {MIO 8} \
        CONFIG.PCW_QSPI_GRP_IO1_ENABLE {0} \
        CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
        CONFIG.PCW_QSPI_GRP_SINGLE_SS_IO {MIO 1 .. 6} \
        CONFIG.PCW_QSPI_GRP_SS1_ENABLE {0} \
        CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_QSPI_PERIPHERAL_FREQMHZ {200} \
        CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} \
        CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
        CONFIG.PCW_SD0_GRP_CD_IO {MIO 47} \
        CONFIG.PCW_SD0_GRP_POW_ENABLE {0} \
        CONFIG.PCW_SD0_GRP_WP_ENABLE {1} \
        CONFIG.PCW_SD0_GRP_WP_IO {EMIO} \
        CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
        CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {50} \
        CONFIG.PCW_SDIO_PERIPHERAL_VALID {1} \
        CONFIG.PCW_SINGLE_QSPI_DATA_MODE {x4} \
        CONFIG.PCW_TTC_PERIPHERAL_FREQMHZ {50} \
        CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_TTC0_TTC0_IO {EMIO} \
        CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
        CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
        CONFIG.PCW_UART1_GRP_FULL_ENABLE {0} \
        CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
        CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.176} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.159} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.162} \
        CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.187} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {-0.073} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {-0.034} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {-0.03} \
        CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {-0.082} \
        CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {525} \
        CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125} \
        CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} \
        CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
        CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
        CONFIG.PCW_USB_RESET_ENABLE {1} \
        CONFIG.PCW_USB_RESET_SELECT {Share reset pin} \
        CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
        CONFIG.PCW_USB0_RESET_ENABLE {1} \
        CONFIG.PCW_USB0_RESET_IO {MIO 46} \
        CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39}
    ] $ps_cell
}
