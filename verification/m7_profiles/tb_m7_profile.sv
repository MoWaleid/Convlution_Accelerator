`timescale 1ns/1ps
module tb_m7_profile;
    `include "expected.svh"
    reg clk=0;
    always #5 clk=~clk;
    reg resetn=0;
    reg [31:0] S_AXI_AWADDR=0, S_AXI_WDATA=0, S_AXI_ARADDR=0;
    reg [2:0] S_AXI_AWPROT=0, S_AXI_ARPROT=0;
    reg [3:0] S_AXI_WSTRB=0;
    reg S_AXI_AWVALID=0, S_AXI_WVALID=0, S_AXI_BREADY=0;
    reg S_AXI_ARVALID=0, S_AXI_RREADY=0;
    wire S_AXI_AWREADY, S_AXI_WREADY, S_AXI_BVALID, S_AXI_ARREADY, S_AXI_RVALID;
    wire [1:0] S_AXI_BRESP, S_AXI_RRESP;
    wire [31:0] S_AXI_RDATA;
    reg [63:0] s_axis_tdata=0;
    reg [7:0] s_axis_tkeep=0;
    reg s_axis_tvalid=0, s_axis_tlast=0;
    wire s_axis_tready;
    wire [63:0] m_axis_tdata;
    wire [7:0] m_axis_tkeep;
    wire m_axis_tvalid, m_axis_tlast;
    reg m_axis_tready=1;

    // REAL BD adapter, with no identity/geometry testbench override anywhere.
    conv_axis_wrapper_bd dut (.*);
    integer checks=0;
    reg [127:0] observed_id;
    reg [31:0] word_value;

    task automatic read_word(input [31:0] offset, output [31:0] value);
        reg [31:0] held;
        begin
            @(negedge clk);
            S_AXI_ARADDR=32'h43c00000+offset;
            S_AXI_ARVALID=1;
            do @(posedge clk); while (S_AXI_ARREADY !== 1'b1);
            @(negedge clk);
            S_AXI_ARVALID=0;
            S_AXI_ARADDR=32'hffffffff;
            do @(posedge clk); while (S_AXI_RVALID !== 1'b1);
            held=S_AXI_RDATA;
            if (S_AXI_RRESP !== 2'b00) $fatal(1,"M7_FAIL read response %h",offset);
            repeat (3) begin
                @(posedge clk);
                if (S_AXI_RVALID !== 1'b1 || S_AXI_RRESP !== 2'b00 ||
                    S_AXI_RDATA !== held) $fatal(1,"M7_FAIL unstable read");
            end
            value=held;
            @(negedge clk);
            S_AXI_RREADY=1;
            @(posedge clk);
            @(negedge clk);
            S_AXI_RREADY=0;
            checks=checks+1;
        end
    endtask

    task automatic expect_word(input [31:0] address, input [31:0] expected);
        reg [31:0] value;
        begin
            read_word(address,value);
            if (value !== expected)
                $fatal(1,"M7_FAIL addr=%h actual=%h expected=%h",address,value,expected);
        end
    endtask

    task automatic discovery;
        begin
            expect_word('h4100,'h43564831);
            expect_word('h4104,'h00010000);
            expect_word('h4108,'h000001ff);
            expect_word('h4120,EXPECT_W);
            expect_word('h4124,EXPECT_H);
            expect_word('h4128,EXPECT_N);
            expect_word('h412c,EXPECT_K);
            expect_word('h4130,'h10180808);
            expect_word('h4134,EXPECT_N==5 ? 'h1916 : 'h1915);
            expect_word('h4138,(EXPECT_W+EXPECT_N-1)*(EXPECT_H+EXPECT_N-1));
            expect_word('h413c,2*EXPECT_W*EXPECT_H*EXPECT_K);
            expect_word('h4160,22);
            for (integer i=0;i<4;i=i+1) begin
                read_word('h4150+4*i,word_value);
                observed_id[32*i +: 32]=word_value;
            end
            if (observed_id !== EXPECT_ID || observed_id === 128'b0)
                $fatal(1,"M7_FAIL integrated ID=%032h expected=%032h",observed_id,EXPECT_ID);
            if (EXPECT_K==16 && observed_id===128'h4d344e334b385733322d323630393131)
                $fatal(1,"M7_FAIL B32 inherited legacy A32 ID");
            expect_word('h410c,'h101);
            expect_word('h4140,0);
            expect_word('h4144,0);
            expect_word('h4148,0);
            expect_word('h414c,0);
        end
    endtask

    initial begin
        repeat (8) @(negedge clk);
        resetn=1;
        repeat (8) @(negedge clk);
        discovery();
        @(negedge clk); resetn=0;
        repeat (5) @(negedge clk);
        resetn=1;
        repeat (8) @(negedge clk);
        discovery();
        if (checks!=42) $fatal(1,"M7_FAIL incomplete discovery coverage %0d",checks);
        if (m_axis_tvalid !== 0 || s_axis_tready !== 0)
            $fatal(1,"M7_FAIL unexpected stream activity before START");
        $display("M7_RTL_PASS W=%0d H=%0d N=%0d K=%0d ID=%032h checks=%0d",
                 EXPECT_W,EXPECT_H,EXPECT_N,EXPECT_K,observed_id,checks);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1,"M7_WATCHDOG discovery timeout");
    end
endmodule

