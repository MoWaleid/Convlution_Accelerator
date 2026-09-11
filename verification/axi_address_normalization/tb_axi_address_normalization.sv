`timescale 1ns / 1ps

// Mixed-language regression: the DUT is the actual Verilog BD adapter, with
// the complete VHDL accelerator below it and the current configuration defaults.
module tb_axi_address_normalization;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;

    reg [31:0] S_AXI_AWADDR = 0;
    reg [2:0] S_AXI_AWPROT = 0;
    reg S_AXI_AWVALID = 0;
    wire S_AXI_AWREADY;
    reg [31:0] S_AXI_WDATA = 0;
    reg [3:0] S_AXI_WSTRB = 0;
    reg S_AXI_WVALID = 0;
    wire S_AXI_WREADY;
    wire [1:0] S_AXI_BRESP;
    wire S_AXI_BVALID;
    reg S_AXI_BREADY = 0;
    reg [31:0] S_AXI_ARADDR = 0;
    reg [2:0] S_AXI_ARPROT = 0;
    reg S_AXI_ARVALID = 0;
    wire S_AXI_ARREADY;
    wire [31:0] S_AXI_RDATA;
    wire [1:0] S_AXI_RRESP;
    wire S_AXI_RVALID;
    reg S_AXI_RREADY = 0;

    reg [63:0] s_axis_tdata = 0;
    reg [7:0] s_axis_tkeep = 0;
    reg s_axis_tvalid = 0;
    wire s_axis_tready;
    reg s_axis_tlast = 0;
    wire [63:0] m_axis_tdata;
    wire [7:0] m_axis_tkeep;
    wire m_axis_tvalid;
    reg m_axis_tready = 1;
    wire m_axis_tlast;

    conv_axis_wrapper_bd dut (.*);

    integer errors = 0;
    integer read_checks = 0;
    integer writes = 0;
    integer r_handshakes = 0;
    integer b_handshakes = 0;

    always @(posedge clk) begin
        if (resetn && S_AXI_RVALID && S_AXI_RREADY)
            r_handshakes <= r_handshakes + 1;
        if (resetn && S_AXI_BVALID && S_AXI_BREADY)
            b_handshakes <= b_handshakes + 1;
    end

    task automatic check_read(input [31:0] address, input [31:0] expected);
        reg [31:0] held_data;
        reg [1:0] held_resp;
        begin
            @(negedge clk);
            S_AXI_ARADDR = address;
            S_AXI_ARVALID = 1;
            do @(posedge clk); while (S_AXI_ARREADY !== 1'b1);
            @(negedge clk);
            S_AXI_ARVALID = 0;
            S_AXI_ARADDR = 32'hFFFFFFFF; // Captured address must be retained.
            do @(posedge clk); while (S_AXI_RVALID !== 1'b1);
            held_data = S_AXI_RDATA;
            held_resp = S_AXI_RRESP;
            read_checks = read_checks + 1;
            $display("READ address=%08h actual=%08h expected=%08h RRESP=%02b",
                     address, held_data, expected, held_resp);
            if (held_data !== expected || held_resp !== 2'b00) begin
                errors = errors + 1;
                $display("FAIL: readback at address %08h", address);
            end

            // Every read is stalled for three cycles before its handshake.
            repeat (3) begin
                @(posedge clk);
                if (S_AXI_RVALID !== 1'b1 || S_AXI_RDATA !== held_data ||
                    S_AXI_RRESP !== held_resp) begin
                    errors = errors + 1;
                    $display("FAIL: read response changed while stalled");
                end
            end
            @(negedge clk);
            S_AXI_RREADY = 1;
            @(posedge clk);
            @(negedge clk);
            S_AXI_RREADY = 0;
            @(posedge clk);
            #1;
            if (S_AXI_RVALID !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL: duplicate read response");
            end
        end
    endtask

    task automatic write_register(
        input [31:0] address, input [31:0] value, input [3:0] strobes,
        input integer aw_delay, input integer w_delay
    );
        begin
            @(negedge clk);
            fork
                begin
                    repeat (aw_delay) @(negedge clk);
                    S_AXI_AWADDR = address;
                    S_AXI_AWVALID = 1;
                    do @(posedge clk); while (S_AXI_AWREADY !== 1'b1);
                    @(negedge clk);
                    S_AXI_AWVALID = 0;
                    S_AXI_AWADDR = 32'hFFFFFFFF;
                end
                begin
                    repeat (w_delay) @(negedge clk);
                    S_AXI_WDATA = value;
                    S_AXI_WSTRB = strobes;
                    S_AXI_WVALID = 1;
                    do @(posedge clk); while (S_AXI_WREADY !== 1'b1);
                    @(negedge clk);
                    S_AXI_WVALID = 0;
                    S_AXI_WDATA = 0;
                    S_AXI_WSTRB = 0;
                end
            join
            do @(posedge clk); while (S_AXI_BVALID !== 1'b1);
            repeat (3) begin
                if (S_AXI_BVALID !== 1'b1 || S_AXI_BRESP !== 2'b00) begin
                    errors = errors + 1;
                    $display("FAIL: write response changed while stalled");
                end
                @(posedge clk);
            end
            @(negedge clk);
            S_AXI_BREADY = 1;
            @(posedge clk);
            writes = writes + 1;
            $display("WRITE address=%08h data=%08h WSTRB=%04b BRESP=%02b",
                     address, value, strobes, S_AXI_BRESP);
            @(negedge clk);
            S_AXI_BREADY = 0;
            @(posedge clk);
            #1;
            if (S_AXI_BVALID !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL: duplicate write response");
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1;
        repeat (2) @(posedge clk);

        // The local read is diagnostic; all remaining accesses are physical.
        check_read(32'h00004008, 32'h00000803);
        check_read(32'h43C04008, 32'h00000803);
        check_read(32'h43C04000, 32'h00000001); // IDLE
        check_read(32'h43C0400C, 32'h00200020); // Logical 32 x 32
        check_read(32'h43C04004, 32'h00000000); // CONTROL reads zero

        // Bias is word 62 / +0xF8. Channel 7 has local base 0x700.
        check_read(32'h43C007F8, 32'h00000000);
        write_register(32'h43C007F8, 32'hFEDCBA98, 4'b1111, 0, 0);
        check_read(32'h43C007F8, 32'hFEDCBA98);
        write_register(32'h43C007F8, 32'h12345678, 4'b0101, 0, 3);
        check_read(32'h43C007F8, 32'hFE34BA78);
        write_register(32'h43C000F8, 32'h89ABCDEF, 4'b1111, 3, 0);
        check_read(32'h43C000F8, 32'h89ABCDEF);
        check_read(32'h43C007F8, 32'hFE34BA78); // Channel spacing preserved

        check_read(32'h43C04010, 32'h00000000); // Unimplemented global
        check_read(32'h43C0FFFC, 32'h00000000); // High end of routed aperture
        check_read(32'h43C00800, 32'h00000000); // Channel 8 invalid for K=8
        check_read(32'h43C04008, 32'h00000803);

        if (r_handshakes != read_checks || b_handshakes != writes)
            $fatal(1, "Response count mismatch: R=%0d/%0d B=%0d/%0d",
                   r_handshakes, read_checks, b_handshakes, writes);
        $display("SUMMARY: reads=%0d writes=%0d mismatches=%0d",
                 read_checks, writes, errors);
        if (errors != 0)
            $fatal(1, "AXI physical address normalization failed");
        $display("PASS: AXI physical address normalization");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "WATCHDOG: AXI address regression timed out");
    end
endmodule
