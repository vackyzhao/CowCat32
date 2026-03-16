// coverage_monitor.v
// Functional coverage collector for LobsterPawn NoC adapter + NoD path.
// Implemented in plain Verilog-2001 (no SystemVerilog) for iverilog compatibility.
//
// Coverage bins tracked:
//
//  Group A: Flit Type Coverage (TX side)
//    A1. HEAD flit transmitted
//    A2. TAIL flit transmitted
//    A3. HEAD immediately followed by TAIL (single-gap 2-flit packet)
//
//  Group B: Routing Coverage
//    B1. Packet injected at (0,0)
//    B2. Packet injected at (4,4)
//    B3. Packet destined for (0,0)
//    B4. Packet destined for (4,4)
//    B5. Same-node loopback: src == dst (X and Y match)
//    B6. Max-distance: (0,0)→(4,4) or (4,4)→(0,0)
//
//  Group C: Flow Control Coverage
//    C1. TX valid asserted but ready LOW (backpressure seen on TX)
//    C2. RX valid asserted but ready LOW (backpressure seen on RX)
//    C3. Consecutive packets back-to-back on same port (gap < 5 cycles)
//
//  Group D: RX-side Coverage
//    D1. Packet received at (0,0) local port
//    D2. Packet received at (4,4) local port
//    D3. RX buffer held for >10 cycles before ack (slow consumer)
//
//  Group E: Register Access Coverage
//    E1. Write to NOC_TX_DATA
//    E2. Write to NOC_TX_DST  (triggers send)
//    E3. Read  from NOC_RX_DATA
//    E4. Read  from NOC_RX_STATUS
//    E5. Write to NOC_RX_ACK

// Macro must be defined before first use (iverilog processes top-to-bottom)
`define COV_BIN(name, count) \
    begin \
        total_bins = total_bins + 1; \
        if ((count) > 0) hit_bins = hit_bins + 1; \
        $display("    [%s] %-40s count=%0d", \
                 ((count) > 0) ? "HIT " : "MISS", name, count); \
    end

`include "param.vh"

module coverage_monitor #(
    parameter NODE_X = 0,
    parameter NODE_Y = 0
)(
    input wire        clk,
    input wire        rstn,

    // NoD TX port (adapter → NoD)
    input wire [`DATA_WIDTH-1:0] nod_tx_data,
    input wire                   nod_tx_valid,
    input wire                   nod_tx_ready,

    // NoD RX port (NoD → adapter)
    input wire [`DATA_WIDTH-1:0] nod_rx_data,
    input wire                   nod_rx_valid,
    input wire                   nod_rx_ready,

    // Adapter bus interface
    input wire [31:0] noc_addr,
    input wire [31:0] noc_wdata,
    input wire        noc_rw,
    input wire        noc_we
);

// -----------------------------------------------------------------------
// Coverage bin registers
// -----------------------------------------------------------------------
integer cov_A1_head_tx;
integer cov_A2_tail_tx;
integer cov_A3_head_then_tail;

integer cov_B1_src_0_0;
integer cov_B2_src_4_4;
integer cov_B3_dst_0_0;
integer cov_B4_dst_4_4;
integer cov_B5_loopback;
integer cov_B6_max_dist;

integer cov_C1_tx_backpressure;
integer cov_C2_rx_backpressure;
integer cov_C3_back_to_back;

integer cov_D1_rx_at_0_0;
integer cov_D2_rx_at_4_4;
integer cov_D3_slow_consumer;

integer cov_E1_write_tx_data;
integer cov_E2_write_tx_dst;
integer cov_E3_read_rx_data;
integer cov_E4_read_rx_status;
integer cov_E5_write_rx_ack;

// -----------------------------------------------------------------------
// Internal tracking state
// -----------------------------------------------------------------------
reg prev_was_head;
integer rx_hold_cycles;
integer last_tx_cycle;
integer cur_cycle;

wire tx_fire = nod_tx_valid && nod_tx_ready;
wire rx_fire = nod_rx_valid && nod_rx_ready;

wire [1:0] tx_flit_type = nod_tx_data[`DATA_WIDTH-1:`DATA_WIDTH-2];
wire [1:0] rx_flit_type = nod_rx_data[`DATA_WIDTH-1:`DATA_WIDTH-2];

// Routing fields from HEAD flit (TX)
wire [5:0] tx_rtid = nod_tx_data[25:20];
wire [5:0] tx_srid = nod_tx_data[11:6];
wire [5:0] tx_drid = nod_tx_data[5:0];
wire [2:0] tx_dst_x = tx_rtid[5:3];
wire [2:0] tx_dst_y = tx_rtid[2:0];
wire [2:0] tx_src_x = tx_srid[5:3];
wire [2:0] tx_src_y = tx_srid[2:0];

// Routing fields from RX HEAD flit
wire [5:0] rx_srid = nod_rx_data[11:6];
wire [2:0] rx_src_x = rx_srid[5:3];
wire [2:0] rx_src_y = rx_srid[2:0];

initial begin
    cov_A1_head_tx       = 0; cov_A2_tail_tx       = 0; cov_A3_head_then_tail = 0;
    cov_B1_src_0_0       = 0; cov_B2_src_4_4       = 0;
    cov_B3_dst_0_0       = 0; cov_B4_dst_4_4       = 0;
    cov_B5_loopback      = 0; cov_B6_max_dist      = 0;
    cov_C1_tx_backpressure=0; cov_C2_rx_backpressure=0; cov_C3_back_to_back  = 0;
    cov_D1_rx_at_0_0     = 0; cov_D2_rx_at_4_4     = 0; cov_D3_slow_consumer = 0;
    cov_E1_write_tx_data = 0; cov_E2_write_tx_dst  = 0;
    cov_E3_read_rx_data  = 0; cov_E4_read_rx_status= 0; cov_E5_write_rx_ack  = 0;
    prev_was_head   = 0;
    rx_hold_cycles  = 0;
    last_tx_cycle   = -100;
    cur_cycle       = 0;
end

// -----------------------------------------------------------------------
// Cycle counter
// -----------------------------------------------------------------------
always @(posedge clk) cur_cycle = cur_cycle + 1;

// -----------------------------------------------------------------------
// Group A — Flit type coverage (TX)
// -----------------------------------------------------------------------
always @(posedge clk) begin
    if (tx_fire) begin
        if (tx_flit_type == 2'b00) begin   // HEAD
            cov_A1_head_tx = cov_A1_head_tx + 1;
            prev_was_head  = 1;
        end else if (tx_flit_type == 2'b10) begin  // TAIL
            cov_A2_tail_tx = cov_A2_tail_tx + 1;
            if (prev_was_head)
                cov_A3_head_then_tail = cov_A3_head_then_tail + 1;
            prev_was_head = 0;
        end else begin
            prev_was_head = 0;  // BODY resets the HEAD-then-TAIL streak
        end
    end
end

// -----------------------------------------------------------------------
// Group B — Routing coverage (sampled on HEAD TX fire)
// -----------------------------------------------------------------------
always @(posedge clk) begin
    if (tx_fire && tx_flit_type == 2'b00) begin
        if (tx_src_x == 0 && tx_src_y == 0) cov_B1_src_0_0 = cov_B1_src_0_0 + 1;
        if (tx_src_x == 4 && tx_src_y == 4) cov_B2_src_4_4 = cov_B2_src_4_4 + 1;
        if (tx_dst_x == 0 && tx_dst_y == 0) cov_B3_dst_0_0 = cov_B3_dst_0_0 + 1;
        if (tx_dst_x == 4 && tx_dst_y == 4) cov_B4_dst_4_4 = cov_B4_dst_4_4 + 1;
        if (tx_src_x == tx_dst_x && tx_src_y == tx_dst_y)
            cov_B5_loopback = cov_B5_loopback + 1;
        if ((tx_src_x == 0 && tx_src_y == 0 && tx_dst_x == 4 && tx_dst_y == 4) ||
            (tx_src_x == 4 && tx_src_y == 4 && tx_dst_x == 0 && tx_dst_y == 0))
            cov_B6_max_dist = cov_B6_max_dist + 1;
    end
end

// -----------------------------------------------------------------------
// Group C — Flow control coverage
// -----------------------------------------------------------------------
always @(posedge clk) begin
    // C1: TX valid but not ready (backpressure on send)
    if (nod_tx_valid && !nod_tx_ready)
        cov_C1_tx_backpressure = cov_C1_tx_backpressure + 1;

    // C2: RX valid but not ready (slow consumer backpressure)
    if (nod_rx_valid && !nod_rx_ready)
        cov_C2_rx_backpressure = cov_C2_rx_backpressure + 1;

    // C3: back-to-back packets (new HEAD within 5 cycles of last TAIL)
    if (tx_fire && tx_flit_type == 2'b00) begin
        if ((cur_cycle - last_tx_cycle) < 5)
            cov_C3_back_to_back = cov_C3_back_to_back + 1;
    end
    if (tx_fire && tx_flit_type == 2'b10)
        last_tx_cycle = cur_cycle;
end

// -----------------------------------------------------------------------
// Group D — RX-side coverage
// -----------------------------------------------------------------------
always @(posedge clk) begin
    // Track how long RX buffer is held (valid but not yet acked)
    if (nod_rx_valid && !nod_rx_ready)
        rx_hold_cycles = rx_hold_cycles + 1;
    else
        rx_hold_cycles = 0;

    if (rx_hold_cycles > 10)
        cov_D3_slow_consumer = cov_D3_slow_consumer + 1;

    // D1/D2: packet received (sample on HEAD arrival)
    if (rx_fire && rx_flit_type == 2'b00) begin
        if (NODE_X == 0 && NODE_Y == 0) cov_D1_rx_at_0_0 = cov_D1_rx_at_0_0 + 1;
        if (NODE_X == 4 && NODE_Y == 4) cov_D2_rx_at_4_4 = cov_D2_rx_at_4_4 + 1;
    end
end

// -----------------------------------------------------------------------
// Group E — Register access coverage
// -----------------------------------------------------------------------
always @(posedge clk) begin
    if (noc_we) begin
        if (noc_rw) begin
            case (noc_addr[7:0])
                8'h00: cov_E1_write_tx_data = cov_E1_write_tx_data + 1;
                8'h04: cov_E2_write_tx_dst  = cov_E2_write_tx_dst  + 1;
                8'h10: cov_E5_write_rx_ack  = cov_E5_write_rx_ack  + 1;
            endcase
        end else begin
            case (noc_addr[7:0])
                8'h08: cov_E3_read_rx_data   = cov_E3_read_rx_data   + 1;
                8'h0C: cov_E4_read_rx_status = cov_E4_read_rx_status + 1;
            endcase
        end
    end
end

// -----------------------------------------------------------------------
// Coverage report task (call at $finish)
// -----------------------------------------------------------------------
integer total_bins, hit_bins;

task print_coverage;
    integer i;
    begin
        total_bins = 0; hit_bins = 0;
        $display("");
        $display("========================================================");
        $display("  LobsterPawn NoC Functional Coverage Report");
        $display("  Monitor node: X=%0d Y=%0d", NODE_X, NODE_Y);
        $display("========================================================");

        $display("  Group A: Flit Type (TX)");
        `COV_BIN("A1 HEAD transmitted",       cov_A1_head_tx)
        `COV_BIN("A2 TAIL transmitted",       cov_A2_tail_tx)
        `COV_BIN("A3 HEAD immediately -> TAIL", cov_A3_head_then_tail)

        $display("  Group B: Routing");
        `COV_BIN("B1 src=(0,0)",              cov_B1_src_0_0)
        `COV_BIN("B2 src=(4,4)",              cov_B2_src_4_4)
        `COV_BIN("B3 dst=(0,0)",              cov_B3_dst_0_0)
        `COV_BIN("B4 dst=(4,4)",              cov_B4_dst_4_4)
        `COV_BIN("B5 loopback (src==dst)",    cov_B5_loopback)
        `COV_BIN("B6 max-distance hop",       cov_B6_max_dist)

        $display("  Group C: Flow Control");
        `COV_BIN("C1 TX backpressure cycles", cov_C1_tx_backpressure)
        `COV_BIN("C2 RX backpressure cycles", cov_C2_rx_backpressure)
        `COV_BIN("C3 back-to-back packets",   cov_C3_back_to_back)

        $display("  Group D: RX");
        `COV_BIN("D1 packet received at (0,0)", cov_D1_rx_at_0_0)
        `COV_BIN("D2 packet received at (4,4)", cov_D2_rx_at_4_4)
        `COV_BIN("D3 slow consumer (>10 cyc)", cov_D3_slow_consumer)

        $display("  Group E: Register Access");
        `COV_BIN("E1 write NOC_TX_DATA",      cov_E1_write_tx_data)
        `COV_BIN("E2 write NOC_TX_DST",       cov_E2_write_tx_dst)
        `COV_BIN("E3 read  NOC_RX_DATA",      cov_E3_read_rx_data)
        `COV_BIN("E4 read  NOC_RX_STATUS",    cov_E4_read_rx_status)
        `COV_BIN("E5 write NOC_RX_ACK",       cov_E5_write_rx_ack)

        $display("--------------------------------------------------------");
        $display("  TOTAL COVERAGE: %0d / %0d bins hit  (%0d%%)",
                 hit_bins, total_bins,
                 (hit_bins * 100) / total_bins);
        $display("========================================================");
        $display("");
    end
endtask

endmodule
