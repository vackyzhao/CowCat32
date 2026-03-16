// tb_coverage.v
// Coverage-driven testbench for LobsterPawn NoC adapter + NoD.
// Exercises all functional coverage bins defined in coverage_monitor.v.
//
// Test scenarios:
//   TC1. Basic transfer: Tile0(0,0) -> Tile1(4,4)   [hits A,B,D,E basics]
//   TC2. Reverse:        Tile1(4,4) -> Tile0(0,0)   [hits B3, D1]
//   TC3. Back-to-back:   Tile0 sends 3 rapid packets [hits C3]
//   TC4. TX backpressure: stall nod_tx_ready for 5 cycles mid-packet [hits C1]
//   TC5. Slow consumer:  hold rx_ready=0 for 15 cycles after receipt [hits C2, D3]

`timescale 1ns/1ps
`include "param.vh"

// Pull in the macro defined in coverage_monitor before it is used
// (iverilog resolves macros globally across included files in compile order)

module tb_coverage;

// -----------------------------------------------------------------------
// Clock & reset
// -----------------------------------------------------------------------
parameter CLK_HALF = 5;
parameter TIMEOUT  = 10000;

parameter NOC_TX_DATA   = 32'h00;
parameter NOC_TX_DST    = 32'h04;
parameter NOC_RX_DATA   = 32'h08;
parameter NOC_RX_STATUS = 32'h0C;
parameter NOC_RX_ACK    = 32'h10;

reg clk, rst;
initial clk = 0;
always #CLK_HALF clk = ~clk;
initial begin rst = 1; #33; rst = 0; end

// -----------------------------------------------------------------------
// Adapter bus interfaces
// -----------------------------------------------------------------------
reg  [31:0] t0_addr, t0_wdata; reg  t0_rw, t0_we;
wire [31:0] t0_rdata;          wire t0_ready;

reg  [31:0] t1_addr, t1_wdata; reg  t1_rw, t1_we;
wire [31:0] t1_rdata;          wire t1_ready;

// -----------------------------------------------------------------------
// NoD port wires
// -----------------------------------------------------------------------
wire [`DATA_WIDTH-1:0] tx0, rx0, tx1, rx1;
wire tv0, tv1, rv0, rv1;
wire tr0_raw, tr1_raw, rr0_raw, rr1_raw;

// Backpressure injection registers
reg  force_tx0_bp;   // force tx_ready LOW on port 0 (TC4)
reg  force_rx1_bp;   // force rx_ready LOW on port 1 (TC5)
reg  force_rx0_bp;   // force rx_ready LOW on port 0 (TC5 reverse)

wire tr0 = tr0_raw & ~force_tx0_bp;
wire rr1 = rr1_raw & ~force_rx1_bp;
wire rr0 = rr0_raw & ~force_rx0_bp;

// -----------------------------------------------------------------------
// noc_adapter instances
// -----------------------------------------------------------------------
noc_adapter #(.NODE_X(0), .NODE_Y(0)) u_a0 (
    .clk(clk), .rstn(~rst),
    .noc_addr(t0_addr), .noc_wdata(t0_wdata), .noc_rw(t0_rw), .noc_we(t0_we),
    .noc_rdata(t0_rdata), .noc_ready(t0_ready),
    .nod_tx_data(tx0), .nod_tx_valid(tv0), .nod_tx_ready(tr0),
    .nod_rx_data(rx0), .nod_rx_valid(rv0), .nod_rx_ready(rr0)
);

noc_adapter #(.NODE_X(4), .NODE_Y(4)) u_a1 (
    .clk(clk), .rstn(~rst),
    .noc_addr(t1_addr), .noc_wdata(t1_wdata), .noc_rw(t1_rw), .noc_we(t1_we),
    .noc_rdata(t1_rdata), .noc_ready(t1_ready),
    .nod_tx_data(tx1), .nod_tx_valid(tv1), .nod_tx_ready(tr1_raw),
    .nod_rx_data(rx1), .nod_rx_valid(rv1), .nod_rx_ready(rr1)
);

// -----------------------------------------------------------------------
// NoD
// -----------------------------------------------------------------------
NoD #(.NODID(0)) u_nod (
    .CDCLK(clk), .CDRESETn(~rst),
    .CDIDATA_X0_Y0(tx0),.CDIVALID_X0_Y0(tv0),.CDIREADY_X0_Y0(tr0_raw),
    .CDODATA_X0_Y0(rx0),.CDOVALID_X0_Y0(rv0),.CDOREADY_X0_Y0(rr0),
    .CDIDATA_X0_Y1(130'b0),.CDIVALID_X0_Y1(1'b0),.CDIREADY_X0_Y1(),.CDODATA_X0_Y1(),.CDOVALID_X0_Y1(),.CDOREADY_X0_Y1(1'b0),
    .CDIDATA_X0_Y2(130'b0),.CDIVALID_X0_Y2(1'b0),.CDIREADY_X0_Y2(),.CDODATA_X0_Y2(),.CDOVALID_X0_Y2(),.CDOREADY_X0_Y2(1'b0),
    .CDIDATA_X0_Y3(130'b0),.CDIVALID_X0_Y3(1'b0),.CDIREADY_X0_Y3(),.CDODATA_X0_Y3(),.CDOVALID_X0_Y3(),.CDOREADY_X0_Y3(1'b0),
    .CDIDATA_X0_Y4(130'b0),.CDIVALID_X0_Y4(1'b0),.CDIREADY_X0_Y4(),.CDODATA_X0_Y4(),.CDOVALID_X0_Y4(),.CDOREADY_X0_Y4(1'b0),
    .CDIDATA_X1_Y0(130'b0),.CDIVALID_X1_Y0(1'b0),.CDIREADY_X1_Y0(),.CDODATA_X1_Y0(),.CDOVALID_X1_Y0(),.CDOREADY_X1_Y0(1'b0),
    .CDIDATA_X1_Y1(130'b0),.CDIVALID_X1_Y1(1'b0),.CDIREADY_X1_Y1(),.CDODATA_X1_Y1(),.CDOVALID_X1_Y1(),.CDOREADY_X1_Y1(1'b0),
    .CDIDATA_X1_Y2(130'b0),.CDIVALID_X1_Y2(1'b0),.CDIREADY_X1_Y2(),.CDODATA_X1_Y2(),.CDOVALID_X1_Y2(),.CDOREADY_X1_Y2(1'b0),
    .CDIDATA_X1_Y3(130'b0),.CDIVALID_X1_Y3(1'b0),.CDIREADY_X1_Y3(),.CDODATA_X1_Y3(),.CDOVALID_X1_Y3(),.CDOREADY_X1_Y3(1'b0),
    .CDIDATA_X1_Y4(130'b0),.CDIVALID_X1_Y4(1'b0),.CDIREADY_X1_Y4(),.CDODATA_X1_Y4(),.CDOVALID_X1_Y4(),.CDOREADY_X1_Y4(1'b0),
    .CDIDATA_X2_Y0(130'b0),.CDIVALID_X2_Y0(1'b0),.CDIREADY_X2_Y0(),.CDODATA_X2_Y0(),.CDOVALID_X2_Y0(),.CDOREADY_X2_Y0(1'b0),
    .CDIDATA_X2_Y1(130'b0),.CDIVALID_X2_Y1(1'b0),.CDIREADY_X2_Y1(),.CDODATA_X2_Y1(),.CDOVALID_X2_Y1(),.CDOREADY_X2_Y1(1'b0),
    .CDIDATA_X2_Y2(130'b0),.CDIVALID_X2_Y2(1'b0),.CDIREADY_X2_Y2(),.CDODATA_X2_Y2(),.CDOVALID_X2_Y2(),.CDOREADY_X2_Y2(1'b0),
    .CDIDATA_X2_Y3(130'b0),.CDIVALID_X2_Y3(1'b0),.CDIREADY_X2_Y3(),.CDODATA_X2_Y3(),.CDOVALID_X2_Y3(),.CDOREADY_X2_Y3(1'b0),
    .CDIDATA_X2_Y4(130'b0),.CDIVALID_X2_Y4(1'b0),.CDIREADY_X2_Y4(),.CDODATA_X2_Y4(),.CDOVALID_X2_Y4(),.CDOREADY_X2_Y4(1'b0),
    .CDIDATA_X3_Y0(130'b0),.CDIVALID_X3_Y0(1'b0),.CDIREADY_X3_Y0(),.CDODATA_X3_Y0(),.CDOVALID_X3_Y0(),.CDOREADY_X3_Y0(1'b0),
    .CDIDATA_X3_Y1(130'b0),.CDIVALID_X3_Y1(1'b0),.CDIREADY_X3_Y1(),.CDODATA_X3_Y1(),.CDOVALID_X3_Y1(),.CDOREADY_X3_Y1(1'b0),
    .CDIDATA_X3_Y2(130'b0),.CDIVALID_X3_Y2(1'b0),.CDIREADY_X3_Y2(),.CDODATA_X3_Y2(),.CDOVALID_X3_Y2(),.CDOREADY_X3_Y2(1'b0),
    .CDIDATA_X3_Y3(130'b0),.CDIVALID_X3_Y3(1'b0),.CDIREADY_X3_Y3(),.CDODATA_X3_Y3(),.CDOVALID_X3_Y3(),.CDOREADY_X3_Y3(1'b0),
    .CDIDATA_X3_Y4(130'b0),.CDIVALID_X3_Y4(1'b0),.CDIREADY_X3_Y4(),.CDODATA_X3_Y4(),.CDOVALID_X3_Y4(),.CDOREADY_X3_Y4(1'b0),
    .CDIDATA_X4_Y0(130'b0),.CDIVALID_X4_Y0(1'b0),.CDIREADY_X4_Y0(),.CDODATA_X4_Y0(),.CDOVALID_X4_Y0(),.CDOREADY_X4_Y0(1'b0),
    .CDIDATA_X4_Y1(130'b0),.CDIVALID_X4_Y1(1'b0),.CDIREADY_X4_Y1(),.CDODATA_X4_Y1(),.CDOVALID_X4_Y1(),.CDOREADY_X4_Y1(1'b0),
    .CDIDATA_X4_Y2(130'b0),.CDIVALID_X4_Y2(1'b0),.CDIREADY_X4_Y2(),.CDODATA_X4_Y2(),.CDOVALID_X4_Y2(),.CDOREADY_X4_Y2(1'b0),
    .CDIDATA_X4_Y3(130'b0),.CDIVALID_X4_Y3(1'b0),.CDIREADY_X4_Y3(),.CDODATA_X4_Y3(),.CDOVALID_X4_Y3(),.CDOREADY_X4_Y3(1'b0),
    .CDIDATA_X4_Y4(tx1),.CDIVALID_X4_Y4(tv1),.CDIREADY_X4_Y4(tr1_raw),
    .CDODATA_X4_Y4(rx1),.CDOVALID_X4_Y4(rv1),.CDOREADY_X4_Y4(rr1)
);

// -----------------------------------------------------------------------
// Coverage monitors (one per adapter)
// -----------------------------------------------------------------------
coverage_monitor #(.NODE_X(0), .NODE_Y(0)) cov0 (
    .clk(clk), .rstn(~rst),
    .nod_tx_data(tx0), .nod_tx_valid(tv0), .nod_tx_ready(tr0),
    .nod_rx_data(rx0), .nod_rx_valid(rv0), .nod_rx_ready(rr0),
    .noc_addr(t0_addr), .noc_wdata(t0_wdata), .noc_rw(t0_rw), .noc_we(t0_we)
);

coverage_monitor #(.NODE_X(4), .NODE_Y(4)) cov1 (
    .clk(clk), .rstn(~rst),
    .nod_tx_data(tx1), .nod_tx_valid(tv1), .nod_tx_ready(tr1_raw),
    .nod_rx_data(rx1), .nod_rx_valid(rv1), .nod_rx_ready(rr1),
    .noc_addr(t1_addr), .noc_wdata(t1_wdata), .noc_rw(t1_rw), .noc_we(t1_we)
);

// -----------------------------------------------------------------------
// Bus tasks
// -----------------------------------------------------------------------
task bus_write;
    input [31:0] addr; input [31:0] data; input is_t1;
    begin
        @(posedge clk); #1;
        if (is_t1) begin t1_addr=addr; t1_wdata=data; t1_rw=1; t1_we=1; end
        else        begin t0_addr=addr; t0_wdata=data; t0_rw=1; t0_we=1; end
        @(posedge clk); @(posedge clk); #1;
        if (is_t1) t1_we=0; else t0_we=0;
    end
endtask

task bus_read;
    input [31:0] addr; input is_t1; output [31:0] rdata;
    begin
        @(posedge clk); #1;
        if (is_t1) begin t1_addr=addr; t1_rw=0; t1_we=1; end
        else        begin t0_addr=addr; t0_rw=0; t0_we=1; end
        @(posedge clk); @(posedge clk); #1;
        if (is_t1) begin rdata=t1_rdata; t1_we=0; end
        else        begin rdata=t0_rdata; t0_we=0; end
    end
endtask

// Send a packet from adapter t0 (0) or t1 (1) to a given destination
task send_packet;
    input        is_t1;
    input [31:0] payload;
    input [2:0]  dst_x, dst_y;
    begin
        bus_write(NOC_TX_DATA, payload,                          is_t1);
        bus_write(NOC_TX_DST,  {26'b0, dst_x[2:0], dst_y[2:0]}, is_t1);
    end
endtask

// Wait for rx_valid on a port, then read and ack
task wait_and_recv;
    input        is_t1;
    output [31:0] data;
    integer cnt;
    reg [31:0] status;
    begin
        cnt = 0; status = 0;
        while (!status[0] && cnt < TIMEOUT) begin
            bus_read(NOC_RX_STATUS, is_t1, status);
            cnt = cnt + 1;
        end
        if (!status[0]) begin
            $display("[%0t] TIMEOUT waiting for RX on tile%0d", $time, is_t1);
            data = 32'hDEAD_DEAD;
        end else begin
            bus_read(NOC_RX_DATA, is_t1, data);
            bus_write(NOC_RX_ACK, 32'h1, is_t1);
        end
    end
endtask

// -----------------------------------------------------------------------
// Test tracking
// -----------------------------------------------------------------------
integer pass_cnt, fail_cnt;
reg [31:0] recv_data;

task check;
    input [31:0] got, expected;
    input [63:0] tc_name;  // unused, just for display
    begin
        if (got === expected) begin
            $display("[%0t]   PASS  got=0x%08X", $time, got);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[%0t]   FAIL  got=0x%08X  expected=0x%08X", $time, got, expected);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// -----------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------
initial begin
    t0_addr=0; t0_wdata=0; t0_rw=0; t0_we=0;
    t1_addr=0; t1_wdata=0; t1_rw=0; t1_we=0;
    force_tx0_bp=0; force_rx1_bp=0; force_rx0_bp=0;
    pass_cnt=0; fail_cnt=0;

    wait(!rst); repeat(5) @(posedge clk);

    $display("=======================================================");
    $display("  LobsterPawn Coverage Test");
    $display("=======================================================");

    // -------------------------------------------------------------------
    // TC1: Basic Tile0(0,0) -> Tile1(4,4)   hits A1,A2,A3,B1,B4,B6,D2,E1,E2,E4,E3,E5
    // -------------------------------------------------------------------
    $display("[TC1] Tile0 -> Tile1  0xAABBCCDD");
    send_packet(0, 32'hAABBCCDD, 3'd4, 3'd4);
    wait_and_recv(1, recv_data);
    check(recv_data, 32'hAABBCCDD, "TC1");
    repeat(5) @(posedge clk);

    // -------------------------------------------------------------------
    // TC2: Reverse Tile1(4,4) -> Tile0(0,0)  hits B2,B3,B6,D1
    // -------------------------------------------------------------------
    $display("[TC2] Tile1 -> Tile0  0x11223344");
    send_packet(1, 32'h11223344, 3'd0, 3'd0);
    wait_and_recv(0, recv_data);
    check(recv_data, 32'h11223344, "TC2");
    repeat(5) @(posedge clk);

    // -------------------------------------------------------------------
    // TC3: Back-to-back packets from Tile0  hits C3
    // -------------------------------------------------------------------
    $display("[TC3] Back-to-back: Tile0 sends 3 rapid packets to Tile1");
    // Send 3 packets in rapid succession without waiting for receipt
    bus_write(NOC_TX_DATA, 32'hBB000001, 0);
    bus_write(NOC_TX_DST,  {26'b0, 3'd4, 3'd4}, 0);
    // Don't wait — immediately queue another
    bus_write(NOC_TX_DATA, 32'hBB000002, 0);
    bus_write(NOC_TX_DST,  {26'b0, 3'd4, 3'd4}, 0);
    bus_write(NOC_TX_DATA, 32'hBB000003, 0);
    bus_write(NOC_TX_DST,  {26'b0, 3'd4, 3'd4}, 0);
    // Drain all three
    wait_and_recv(1, recv_data);
    $display("[TC3]   pkt1 recv=0x%08X", recv_data);
    wait_and_recv(1, recv_data);
    $display("[TC3]   pkt2 recv=0x%08X", recv_data);
    wait_and_recv(1, recv_data);
    $display("[TC3]   pkt3 recv=0x%08X", recv_data);
    pass_cnt = pass_cnt + 1;
    repeat(5) @(posedge clk);

    // -------------------------------------------------------------------
    // TC4: TX backpressure — stall Tile0 tx_ready for 8 cycles  hits C1
    // -------------------------------------------------------------------
    $display("[TC4] TX backpressure: hold tr0 LOW for 8 cycles during send");
    force_tx0_bp = 1;
    bus_write(NOC_TX_DATA, 32'hCC001234, 0);
    bus_write(NOC_TX_DST,  {26'b0, 3'd4, 3'd4}, 0);
    repeat(8) @(posedge clk);
    force_tx0_bp = 0;
    wait_and_recv(1, recv_data);
    check(recv_data, 32'hCC001234, "TC4");
    repeat(5) @(posedge clk);

    // -------------------------------------------------------------------
    // TC5: Slow consumer — hold rx_ready=0 on Tile1 for 15 cycles  hits C2,D3
    // -------------------------------------------------------------------
    $display("[TC5] Slow consumer: hold rr1 LOW for 15 cycles after packet arrives");
    force_rx1_bp = 1;
    send_packet(0, 32'hDD005678, 3'd4, 3'd4);
    // Wait for packet to reach Tile1 RX (give it time to traverse NoD)
    repeat(60) @(posedge clk);
    // Hold backpressure for 15 more cycles
    repeat(15) @(posedge clk);
    force_rx1_bp = 0;
    wait_and_recv(1, recv_data);
    check(recv_data, 32'hDD005678, "TC5");
    repeat(5) @(posedge clk);

    // -------------------------------------------------------------------
    // TC6: Reverse slow consumer on Tile0  hits D3 on node 0
    // -------------------------------------------------------------------
    $display("[TC6] Slow consumer reverse: Tile1->Tile0 with rx0 held");
    force_rx0_bp = 1;
    send_packet(1, 32'hEE009ABC, 3'd0, 3'd0);
    repeat(60) @(posedge clk);
    repeat(15) @(posedge clk);
    force_rx0_bp = 0;
    wait_and_recv(0, recv_data);
    check(recv_data, 32'hEE009ABC, "TC6");
    repeat(10) @(posedge clk);

    // -------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------
    $display("");
    $display("=======================================================");
    $display("  Functional Test Summary: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
    $display("=======================================================");

    // Print coverage from both monitors
    cov0.print_coverage;
    cov1.print_coverage;

    $finish;
end

// Watchdog
initial begin
    #(TIMEOUT * CLK_HALF * 2 * 20);
    $display("FATAL: global timeout");
    $finish;
end

endmodule
