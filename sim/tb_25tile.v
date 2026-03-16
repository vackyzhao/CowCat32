// tb_25tile.v
// Functional test: 25 noc_adapters connected to all NoD local ports.
//
// Test plan:
//   Each tile (X,Y) sends one packet to tile ((X+1)%5, (Y+1)%5) — diagonal shift.
//   This exercises all 25 TX ports and all 25 RX ports in one test.
//   Then a second round: every tile sends to the diagonally opposite tile.
//   Pass condition: every tile receives exactly the expected payload.
//
// Architecture:
//   - 25 noc_adapter instances inside lobsterpawn_25tile_top
//   - Testbench drives each adapter's bus interface via flat register arrays
//   - All 25 adapters share clock/reset from testbench

`timescale 1ns/1ps
`include "param.vh"

module tb_25tile;

// -----------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------
parameter N          = 5;
parameter NUM_TILES  = 25;
parameter CLK_HALF   = 5;
parameter TIMEOUT    = 3000;

// NOC register offsets (relative, not absolute — adapter uses addr[7:0])
parameter NOC_TX_DATA   = 8'h00;
parameter NOC_TX_DST    = 8'h04;
parameter NOC_RX_DATA   = 8'h08;
parameter NOC_RX_STATUS = 8'h0C;
parameter NOC_RX_ACK    = 8'h10;

// -----------------------------------------------------------------------
// Clock & reset
// -----------------------------------------------------------------------
reg clk, rst;
initial clk = 0;
always #CLK_HALF clk = ~clk;
initial begin rst = 1; #33; rst = 0; end

// -----------------------------------------------------------------------
// Per-tile bus interface (flat arrays indexed by tile_id = X*5+Y)
// -----------------------------------------------------------------------
reg  [31:0] bus_addr  [0:NUM_TILES-1];
reg  [31:0] bus_wdata [0:NUM_TILES-1];
reg         bus_rw    [0:NUM_TILES-1];
reg         bus_we    [0:NUM_TILES-1];
wire [31:0] bus_rdata [0:NUM_TILES-1];
wire        bus_ready [0:NUM_TILES-1];

// NoD port wires (flat, indexed by tile_id)
wire [`DATA_WIDTH-1:0] tx_data [0:NUM_TILES-1];
wire [`DATA_WIDTH-1:0] rx_data [0:NUM_TILES-1];
wire                   tx_valid[0:NUM_TILES-1];
wire                   tx_ready[0:NUM_TILES-1];
wire                   rx_valid[0:NUM_TILES-1];
wire                   rx_ready[0:NUM_TILES-1];

// -----------------------------------------------------------------------
// 25 noc_adapter instances  (Verilog-2001: no generate+array port connect,
// so we instantiate all 25 explicitly)
// -----------------------------------------------------------------------
`define TILE(ID, NX, NY) \
    noc_adapter #(.NODE_X(NX), .NODE_Y(NY)) u_adap_``ID ( \
        .clk(clk), .rstn(~rst), \
        .noc_addr (bus_addr [ID]), .noc_wdata(bus_wdata[ID]), \
        .noc_rw   (bus_rw   [ID]), .noc_we   (bus_we   [ID]), \
        .noc_rdata(bus_rdata[ID]), .noc_ready(bus_ready[ID]), \
        .nod_tx_data (tx_data [ID]), .nod_tx_valid(tx_valid[ID]), .nod_tx_ready(tx_ready[ID]), \
        .nod_rx_data (rx_data [ID]), .nod_rx_valid(rx_valid[ID]), .nod_rx_ready(rx_ready[ID]) \
    )

`TILE( 0, 0, 0); `TILE( 1, 0, 1); `TILE( 2, 0, 2); `TILE( 3, 0, 3); `TILE( 4, 0, 4);
`TILE( 5, 1, 0); `TILE( 6, 1, 1); `TILE( 7, 1, 2); `TILE( 8, 1, 3); `TILE( 9, 1, 4);
`TILE(10, 2, 0); `TILE(11, 2, 1); `TILE(12, 2, 2); `TILE(13, 2, 3); `TILE(14, 2, 4);
`TILE(15, 3, 0); `TILE(16, 3, 1); `TILE(17, 3, 2); `TILE(18, 3, 3); `TILE(19, 3, 4);
`TILE(20, 4, 0); `TILE(21, 4, 1); `TILE(22, 4, 2); `TILE(23, 4, 3); `TILE(24, 4, 4);

// -----------------------------------------------------------------------
// NoD — connect all 25 ports
// -----------------------------------------------------------------------
NoD #(.NODID(0)) u_nod (
    .CDCLK(clk), .CDRESETn(~rst),
    .CDIDATA_X0_Y0(tx_data[ 0]),.CDIVALID_X0_Y0(tx_valid[ 0]),.CDIREADY_X0_Y0(tx_ready[ 0]),
    .CDODATA_X0_Y0(rx_data[ 0]),.CDOVALID_X0_Y0(rx_valid[ 0]),.CDOREADY_X0_Y0(rx_ready[ 0]),
    .CDIDATA_X0_Y1(tx_data[ 1]),.CDIVALID_X0_Y1(tx_valid[ 1]),.CDIREADY_X0_Y1(tx_ready[ 1]),
    .CDODATA_X0_Y1(rx_data[ 1]),.CDOVALID_X0_Y1(rx_valid[ 1]),.CDOREADY_X0_Y1(rx_ready[ 1]),
    .CDIDATA_X0_Y2(tx_data[ 2]),.CDIVALID_X0_Y2(tx_valid[ 2]),.CDIREADY_X0_Y2(tx_ready[ 2]),
    .CDODATA_X0_Y2(rx_data[ 2]),.CDOVALID_X0_Y2(rx_valid[ 2]),.CDOREADY_X0_Y2(rx_ready[ 2]),
    .CDIDATA_X0_Y3(tx_data[ 3]),.CDIVALID_X0_Y3(tx_valid[ 3]),.CDIREADY_X0_Y3(tx_ready[ 3]),
    .CDODATA_X0_Y3(rx_data[ 3]),.CDOVALID_X0_Y3(rx_valid[ 3]),.CDOREADY_X0_Y3(rx_ready[ 3]),
    .CDIDATA_X0_Y4(tx_data[ 4]),.CDIVALID_X0_Y4(tx_valid[ 4]),.CDIREADY_X0_Y4(tx_ready[ 4]),
    .CDODATA_X0_Y4(rx_data[ 4]),.CDOVALID_X0_Y4(rx_valid[ 4]),.CDOREADY_X0_Y4(rx_ready[ 4]),
    .CDIDATA_X1_Y0(tx_data[ 5]),.CDIVALID_X1_Y0(tx_valid[ 5]),.CDIREADY_X1_Y0(tx_ready[ 5]),
    .CDODATA_X1_Y0(rx_data[ 5]),.CDOVALID_X1_Y0(rx_valid[ 5]),.CDOREADY_X1_Y0(rx_ready[ 5]),
    .CDIDATA_X1_Y1(tx_data[ 6]),.CDIVALID_X1_Y1(tx_valid[ 6]),.CDIREADY_X1_Y1(tx_ready[ 6]),
    .CDODATA_X1_Y1(rx_data[ 6]),.CDOVALID_X1_Y1(rx_valid[ 6]),.CDOREADY_X1_Y1(rx_ready[ 6]),
    .CDIDATA_X1_Y2(tx_data[ 7]),.CDIVALID_X1_Y2(tx_valid[ 7]),.CDIREADY_X1_Y2(tx_ready[ 7]),
    .CDODATA_X1_Y2(rx_data[ 7]),.CDOVALID_X1_Y2(rx_valid[ 7]),.CDOREADY_X1_Y2(rx_ready[ 7]),
    .CDIDATA_X1_Y3(tx_data[ 8]),.CDIVALID_X1_Y3(tx_valid[ 8]),.CDIREADY_X1_Y3(tx_ready[ 8]),
    .CDODATA_X1_Y3(rx_data[ 8]),.CDOVALID_X1_Y3(rx_valid[ 8]),.CDOREADY_X1_Y3(rx_ready[ 8]),
    .CDIDATA_X1_Y4(tx_data[ 9]),.CDIVALID_X1_Y4(tx_valid[ 9]),.CDIREADY_X1_Y4(tx_ready[ 9]),
    .CDODATA_X1_Y4(rx_data[ 9]),.CDOVALID_X1_Y4(rx_valid[ 9]),.CDOREADY_X1_Y4(rx_ready[ 9]),
    .CDIDATA_X2_Y0(tx_data[10]),.CDIVALID_X2_Y0(tx_valid[10]),.CDIREADY_X2_Y0(tx_ready[10]),
    .CDODATA_X2_Y0(rx_data[10]),.CDOVALID_X2_Y0(rx_valid[10]),.CDOREADY_X2_Y0(rx_ready[10]),
    .CDIDATA_X2_Y1(tx_data[11]),.CDIVALID_X2_Y1(tx_valid[11]),.CDIREADY_X2_Y1(tx_ready[11]),
    .CDODATA_X2_Y1(rx_data[11]),.CDOVALID_X2_Y1(rx_valid[11]),.CDOREADY_X2_Y1(rx_ready[11]),
    .CDIDATA_X2_Y2(tx_data[12]),.CDIVALID_X2_Y2(tx_valid[12]),.CDIREADY_X2_Y2(tx_ready[12]),
    .CDODATA_X2_Y2(rx_data[12]),.CDOVALID_X2_Y2(rx_valid[12]),.CDOREADY_X2_Y2(rx_ready[12]),
    .CDIDATA_X2_Y3(tx_data[13]),.CDIVALID_X2_Y3(tx_valid[13]),.CDIREADY_X2_Y3(tx_ready[13]),
    .CDODATA_X2_Y3(rx_data[13]),.CDOVALID_X2_Y3(rx_valid[13]),.CDOREADY_X2_Y3(rx_ready[13]),
    .CDIDATA_X2_Y4(tx_data[14]),.CDIVALID_X2_Y4(tx_valid[14]),.CDIREADY_X2_Y4(tx_ready[14]),
    .CDODATA_X2_Y4(rx_data[14]),.CDOVALID_X2_Y4(rx_valid[14]),.CDOREADY_X2_Y4(rx_ready[14]),
    .CDIDATA_X3_Y0(tx_data[15]),.CDIVALID_X3_Y0(tx_valid[15]),.CDIREADY_X3_Y0(tx_ready[15]),
    .CDODATA_X3_Y0(rx_data[15]),.CDOVALID_X3_Y0(rx_valid[15]),.CDOREADY_X3_Y0(rx_ready[15]),
    .CDIDATA_X3_Y1(tx_data[16]),.CDIVALID_X3_Y1(tx_valid[16]),.CDIREADY_X3_Y1(tx_ready[16]),
    .CDODATA_X3_Y1(rx_data[16]),.CDOVALID_X3_Y1(rx_valid[16]),.CDOREADY_X3_Y1(rx_ready[16]),
    .CDIDATA_X3_Y2(tx_data[17]),.CDIVALID_X3_Y2(tx_valid[17]),.CDIREADY_X3_Y2(tx_ready[17]),
    .CDODATA_X3_Y2(rx_data[17]),.CDOVALID_X3_Y2(rx_valid[17]),.CDOREADY_X3_Y2(rx_ready[17]),
    .CDIDATA_X3_Y3(tx_data[18]),.CDIVALID_X3_Y3(tx_valid[18]),.CDIREADY_X3_Y3(tx_ready[18]),
    .CDODATA_X3_Y3(rx_data[18]),.CDOVALID_X3_Y3(rx_valid[18]),.CDOREADY_X3_Y3(rx_ready[18]),
    .CDIDATA_X3_Y4(tx_data[19]),.CDIVALID_X3_Y4(tx_valid[19]),.CDIREADY_X3_Y4(tx_ready[19]),
    .CDODATA_X3_Y4(rx_data[19]),.CDOVALID_X3_Y4(rx_valid[19]),.CDOREADY_X3_Y4(rx_ready[19]),
    .CDIDATA_X4_Y0(tx_data[20]),.CDIVALID_X4_Y0(tx_valid[20]),.CDIREADY_X4_Y0(tx_ready[20]),
    .CDODATA_X4_Y0(rx_data[20]),.CDOVALID_X4_Y0(rx_valid[20]),.CDOREADY_X4_Y0(rx_ready[20]),
    .CDIDATA_X4_Y1(tx_data[21]),.CDIVALID_X4_Y1(tx_valid[21]),.CDIREADY_X4_Y1(tx_ready[21]),
    .CDODATA_X4_Y1(rx_data[21]),.CDOVALID_X4_Y1(rx_valid[21]),.CDOREADY_X4_Y1(rx_ready[21]),
    .CDIDATA_X4_Y2(tx_data[22]),.CDIVALID_X4_Y2(tx_valid[22]),.CDIREADY_X4_Y2(tx_ready[22]),
    .CDODATA_X4_Y2(rx_data[22]),.CDOVALID_X4_Y2(rx_valid[22]),.CDOREADY_X4_Y2(rx_ready[22]),
    .CDIDATA_X4_Y3(tx_data[23]),.CDIVALID_X4_Y3(tx_valid[23]),.CDIREADY_X4_Y3(tx_ready[23]),
    .CDODATA_X4_Y3(rx_data[23]),.CDOVALID_X4_Y3(rx_valid[23]),.CDOREADY_X4_Y3(rx_ready[23]),
    .CDIDATA_X4_Y4(tx_data[24]),.CDIVALID_X4_Y4(tx_valid[24]),.CDIREADY_X4_Y4(tx_ready[24]),
    .CDODATA_X4_Y4(rx_data[24]),.CDOVALID_X4_Y4(rx_valid[24]),.CDOREADY_X4_Y4(rx_ready[24])
);

// -----------------------------------------------------------------------
// Initialise all bus interfaces
// -----------------------------------------------------------------------
integer _i;
initial begin
    for (_i = 0; _i < NUM_TILES; _i = _i + 1) begin
        bus_addr [_i] = 0;
        bus_wdata[_i] = 0;
        bus_rw   [_i] = 0;
        bus_we   [_i] = 0;
    end
end

// -----------------------------------------------------------------------
// Bus tasks (operate on a specific tile_id)
// -----------------------------------------------------------------------
task tile_write;
    input integer tid;
    input [7:0]   offset;
    input [31:0]  data;
    begin
        @(posedge clk); #1;
        bus_addr [tid] = {24'b0, offset};
        bus_wdata[tid] = data;
        bus_rw   [tid] = 1;
        bus_we   [tid] = 1;
        @(posedge clk); @(posedge clk); #1;
        bus_we[tid] = 0;
    end
endtask

task tile_read;
    input  integer tid;
    input  [7:0]   offset;
    output [31:0]  rdata;
    begin
        @(posedge clk); #1;
        bus_addr[tid] = {24'b0, offset};
        bus_rw  [tid] = 0;
        bus_we  [tid] = 1;
        @(posedge clk); @(posedge clk); #1;
        rdata = bus_rdata[tid];
        bus_we[tid] = 0;
    end
endtask

// Send from tile (src_x,src_y) to tile (dst_x,dst_y) with given payload
task send_from;
    input integer src_id;
    input [2:0]   dst_x, dst_y;
    input [31:0]  payload;
    begin
        tile_write(src_id, NOC_TX_DATA, payload);
        tile_write(src_id, NOC_TX_DST, {26'b0, dst_x, dst_y});
    end
endtask

// Poll tile until rx_valid, then read payload and ack
task recv_at;
    input  integer dst_id;
    output [31:0]  payload;
    integer cnt;
    reg [31:0] status;
    begin
        cnt = 0; status = 0;
        while (!status[0] && cnt < TIMEOUT) begin
            tile_read(dst_id, NOC_RX_STATUS, status);
            cnt = cnt + 1;
        end
        if (!status[0]) begin
            $display("  [TIMEOUT] tile %0d never got rx_valid", dst_id);
            payload = 32'hDEAD_DEAD;
        end else begin
            tile_read(dst_id, NOC_RX_DATA, payload);
            tile_write(dst_id, NOC_RX_ACK, 32'h1);
        end
    end
endtask

// -----------------------------------------------------------------------
// Test infrastructure
// -----------------------------------------------------------------------
integer pass_cnt, fail_cnt, round;
reg [31:0] got, expected_val;

task check_rx;
    input integer  dst_id;
    input [31:0]   exp;
    input integer  src_id;
    begin
        recv_at(dst_id, got);
        if (got === exp) begin
            $display("  PASS  tile%02d <- tile%02d  payload=0x%08X", dst_id, src_id, got);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  tile%02d <- tile%02d  got=0x%08X expected=0x%08X",
                     dst_id, src_id, got, exp);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// -----------------------------------------------------------------------
// Helper: tile_id ↔ (X,Y) conversion
// -----------------------------------------------------------------------
function [2:0] tid_x; input integer t; tid_x = t / N; endfunction
function [2:0] tid_y; input integer t; tid_y = t % N; endfunction
function integer tid;  input integer x; input integer y; tid = x*N+y; endfunction

// -----------------------------------------------------------------------
// Main test sequence
// -----------------------------------------------------------------------
integer src, dst_x, dst_y, dst_id, si;

initial begin
    pass_cnt = 0; fail_cnt = 0;
    wait(!rst); repeat(5) @(posedge clk);

    $display("=====================================================");
    $display("  LobsterPawn 25-Tile Functional Test");
    $display("  Topology: 5x5 NoD mesh, 25 noc_adapters");
    $display("=====================================================");

    // =================================================================
    // ROUND 1: Diagonal shift — tile(X,Y) → tile((X+1)%5,(Y+1)%5)
    //   Exercises all 25 TX ports and all 25 RX ports simultaneously.
    //   Payload encodes sender: 0xA0_00_00_<src_id>
    // =================================================================
    $display("");
    $display("[Round 1] Diagonal shift: each tile -> ((X+1)%%5, (Y+1)%%5)");

    // Fire all 25 sends concurrently (sequential in sim, but adapter
    // queues each immediately without waiting for prior receipt)
    for (si = 0; si < NUM_TILES; si = si + 1) begin
        dst_x = (tid_x(si) + 1) % N;
        dst_y = (tid_y(si) + 1) % N;
        send_from(si, dst_x[2:0], dst_y[2:0], 32'hA000_0000 | si);
    end

    // Collect all 25 receipts
    for (si = 0; si < NUM_TILES; si = si + 1) begin
        // tile si receives from tile ((X-1+5)%5, (Y-1+5)%5)
        src = tid(((tid_x(si)+4)%N), ((tid_y(si)+4)%N));
        check_rx(si, 32'hA000_0000 | src, src);
    end

    repeat(20) @(posedge clk);

    // =================================================================
    // ROUND 2: Diagonal opposite — tile(X,Y) → tile(4-X, 4-Y)
    //   Every packet crosses the full mesh. Max hop count = 8 (4+4).
    //   Payload: 0xB0_00_00_<src_id>
    // =================================================================
    $display("");
    $display("[Round 2] Opposite corners: each tile -> (4-X, 4-Y)");

    for (si = 0; si < NUM_TILES; si = si + 1) begin
        dst_x = 4 - tid_x(si);
        dst_y = 4 - tid_y(si);
        send_from(si, dst_x[2:0], dst_y[2:0], 32'hB000_0000 | si);
    end

    for (si = 0; si < NUM_TILES; si = si + 1) begin
        src = tid(4 - tid_x(si), 4 - tid_y(si));
        check_rx(si, 32'hB000_0000 | src, src);
    end

    repeat(20) @(posedge clk);

    // =================================================================
    // ROUND 3: Ring along Y — tile(X,Y) → tile(X, (Y+1)%5)
    //   Tests Y-dimension routing across all columns simultaneously.
    //   Payload: 0xC0_00_00_<src_id>
    // =================================================================
    $display("");
    $display("[Round 3] Y-ring: each tile -> (X, (Y+1)%%5)");

    for (si = 0; si < NUM_TILES; si = si + 1) begin
        dst_x = tid_x(si);
        dst_y = (tid_y(si) + 1) % N;
        send_from(si, dst_x[2:0], dst_y[2:0], 32'hC000_0000 | si);
    end

    for (si = 0; si < NUM_TILES; si = si + 1) begin
        src = tid(tid_x(si), (tid_y(si)+4)%N);
        check_rx(si, 32'hC000_0000 | src, src);
    end

    repeat(20) @(posedge clk);

    // =================================================================
    // ROUND 4: Ring along X — tile(X,Y) → tile((X+1)%5, Y)
    //   Tests X-dimension routing. Payload: 0xD0_00_00_<src_id>
    // =================================================================
    $display("");
    $display("[Round 4] X-ring: each tile -> ((X+1)%%5, Y)");

    for (si = 0; si < NUM_TILES; si = si + 1) begin
        dst_x = (tid_x(si) + 1) % N;
        dst_y = tid_y(si);
        send_from(si, dst_x[2:0], dst_y[2:0], 32'hD000_0000 | si);
    end

    for (si = 0; si < NUM_TILES; si = si + 1) begin
        src = tid((tid_x(si)+4)%N, tid_y(si));
        check_rx(si, 32'hD000_0000 | src, src);
    end

    repeat(20) @(posedge clk);

    // =================================================================
    // ROUND 5: Broadcast to centre — all tiles → tile(2,2)
    //   One-by-one (sequential) since tile 12 has one RX buffer.
    //   Tests convergent traffic to the same destination.
    //   Payload: 0xE0_00_00_<src_id>
    // =================================================================
    $display("");
    $display("[Round 5] Converge to centre tile(2,2): all 25 tiles send sequentially");

    for (si = 0; si < NUM_TILES; si = si + 1) begin
        if (si != 12) begin  // skip centre sending to itself
            send_from(si, 3'd2, 3'd2, 32'hE000_0000 | si);
            recv_at(12, got);
            if (got === (32'hE000_0000 | si)) begin
                $display("  PASS  tile12 <- tile%02d  payload=0x%08X", si, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  tile12 <- tile%02d  got=0x%08X expected=0x%08X",
                         si, got, 32'hE000_0000 | si);
                fail_cnt = fail_cnt + 1;
            end
        end
    end

    repeat(20) @(posedge clk);

    // =================================================================
    // Summary
    // =================================================================
    $display("");
    $display("=====================================================");
    $display("  RESULT: %0d PASS  %0d FAIL  (total=%0d)",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    if (fail_cnt == 0)
        $display("  *** ALL TESTS PASSED ***");
    else
        $display("  *** FAILURES DETECTED ***");
    $display("=====================================================");
    $finish;
end

// Watchdog
initial begin
    #(20_000_000);
    $display("FATAL: global simulation timeout");
    $finish;
end

endmodule
