// tb_lobsterpawn.v
// Integration testbench for LobsterPawn 2-tile SoC.
//
// This testbench bypasses the CPU program memory and directly drives the
// noc_adapter bus interface to verify the end-to-end NoD path:
//   Tile 0 adapter --[NoD (0,0)→(4,4)]--> Tile 1 adapter
//   Tile 1 adapter --[NoD (4,4)→(0,0)]--> Tile 0 adapter
//
// Each transfer is exercised as a raw bus write sequence to the NOC registers.
//
// Test sequence:
//   1. Tile 0 sends payload 0xDEAD_BEEF to tile 1
//   2. Wait for tile 1 rx_valid to assert
//   3. Tile 1 reads back the payload — verify it equals 0xDEAD_BEEF
//   4. Tile 1 sends payload 0xCAFE_1234 to tile 0
//   5. Wait for tile 0 rx_valid to assert
//   6. Tile 0 reads back the payload — verify it equals 0xCAFE_1234
//   7. Report PASS or FAIL

`timescale 1ns/1ps
`include "param.vh"

module tb_lobsterpawn;

// -----------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------
parameter CLK_HALF = 5;      // 100 MHz
parameter TIMEOUT  = 5000;   // cycles

// NOC register offsets
parameter NOC_TX_DATA   = 32'h0000_3000;
parameter NOC_TX_DST    = 32'h0000_3004;
parameter NOC_RX_DATA   = 32'h0000_3008;
parameter NOC_RX_STATUS = 32'h0000_300C;
parameter NOC_RX_ACK    = 32'h0000_3010;

// -----------------------------------------------------------------------
// Clocks and reset
// -----------------------------------------------------------------------
reg clk, rtc_clk, rst;

initial clk     = 0;
initial rtc_clk = 0;
always #CLK_HALF          clk     = ~clk;
always #(CLK_HALF * 1526) rtc_clk = ~rtc_clk; // ~32.768 kHz relative to 100 MHz

initial begin
    rst = 1;
    #33;
    rst = 0;
end

// -----------------------------------------------------------------------
// Direct adapter bus interfaces (bypassing CPU)
// Used to drive the noc_adapter without needing a running CPU program
// -----------------------------------------------------------------------

// Tile 0 adapter stimulus
reg  [31:0] t0_noc_addr,  t0_noc_wdata;
reg         t0_noc_rw,    t0_noc_we;
wire [31:0] t0_noc_rdata;
wire        t0_noc_ready;

// Tile 1 adapter stimulus
reg  [31:0] t1_noc_addr,  t1_noc_wdata;
reg         t1_noc_rw,    t1_noc_we;
wire [31:0] t1_noc_rdata;
wire        t1_noc_ready;

// NoD local port wires
wire [`DATA_WIDTH-1:0] tx_data_t0, rx_data_t0;
wire                   tx_valid_t0, tx_ready_t0;
wire                   rx_valid_t0, rx_ready_t0;

wire [`DATA_WIDTH-1:0] tx_data_t1, rx_data_t1;
wire                   tx_valid_t1, tx_ready_t1;
wire                   rx_valid_t1, rx_ready_t1;

// -----------------------------------------------------------------------
// Adapter instances (standalone, without full cpu_tile_top)
// -----------------------------------------------------------------------
noc_adapter #(.NODE_X(0), .NODE_Y(0)) u_adapter0 (
    .clk         (clk),
    .rstn        (~rst),
    .noc_addr    (t0_noc_addr),
    .noc_wdata   (t0_noc_wdata),
    .noc_rw      (t0_noc_rw),
    .noc_we      (t0_noc_we),
    .noc_rdata   (t0_noc_rdata),
    .noc_ready   (t0_noc_ready),
    .nod_tx_data  (tx_data_t0),
    .nod_tx_valid (tx_valid_t0),
    .nod_tx_ready (tx_ready_t0),
    .nod_rx_data  (rx_data_t0),
    .nod_rx_valid (rx_valid_t0),
    .nod_rx_ready (rx_ready_t0)
);

noc_adapter #(.NODE_X(4), .NODE_Y(4)) u_adapter1 (
    .clk         (clk),
    .rstn        (~rst),
    .noc_addr    (t1_noc_addr),
    .noc_wdata   (t1_noc_wdata),
    .noc_rw      (t1_noc_rw),
    .noc_we      (t1_noc_we),
    .noc_rdata   (t1_noc_rdata),
    .noc_ready   (t1_noc_ready),
    .nod_tx_data  (tx_data_t1),
    .nod_tx_valid (tx_valid_t1),
    .nod_tx_ready (tx_ready_t1),
    .nod_rx_data  (rx_data_t1),
    .nod_rx_valid (rx_valid_t1),
    .nod_rx_ready (rx_ready_t1)
);

// -----------------------------------------------------------------------
// NoD
// -----------------------------------------------------------------------
NoD #(.NODID(0)) u_nod (
    .CDCLK    (clk),
    .CDRESETn (~rst),

    .CDIDATA_X0_Y0(tx_data_t0),.CDIVALID_X0_Y0(tx_valid_t0),.CDIREADY_X0_Y0(tx_ready_t0),
    .CDODATA_X0_Y0(rx_data_t0),.CDOVALID_X0_Y0(rx_valid_t0),.CDOREADY_X0_Y0(rx_ready_t0),

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

    .CDIDATA_X4_Y4(tx_data_t1),.CDIVALID_X4_Y4(tx_valid_t1),.CDIREADY_X4_Y4(tx_ready_t1),
    .CDODATA_X4_Y4(rx_data_t1),.CDOVALID_X4_Y4(rx_valid_t1),.CDOREADY_X4_Y4(rx_ready_t1)
);

// -----------------------------------------------------------------------
// Test tasks
// -----------------------------------------------------------------------
// Bus write to an adapter — holds we for 2 cycles then releases
task adapter_write;
    input [31:0] addr;
    input [31:0] data;
    input        is_tile1;
    begin
        @(posedge clk); #1;
        if (is_tile1) begin
            t1_noc_addr = addr; t1_noc_wdata = data;
            t1_noc_rw   = 1;   t1_noc_we    = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            t1_noc_we = 0;
        end else begin
            t0_noc_addr = addr; t0_noc_wdata = data;
            t0_noc_rw   = 1;   t0_noc_we    = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            t0_noc_we = 0;
        end
    end
endtask

// Bus read from an adapter — holds for 2 cycles, samples rdata
task adapter_read;
    input  [31:0] addr;
    input         is_tile1;
    output [31:0] rdata;
    begin
        @(posedge clk); #1;
        if (is_tile1) begin
            t1_noc_addr = addr; t1_noc_rw = 0; t1_noc_we = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rdata = t1_noc_rdata;
            t1_noc_we = 0;
        end else begin
            t0_noc_addr = addr; t0_noc_rw = 0; t0_noc_we = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rdata = t0_noc_rdata;
            t0_noc_we = 0;
        end
    end
endtask

// -----------------------------------------------------------------------
// Main test
// -----------------------------------------------------------------------
integer cycle_count;
reg [31:0] read_val;
integer pass_count;

initial begin
    // Initialise bus drives
    t0_noc_addr = 0; t0_noc_wdata = 0; t0_noc_rw = 0; t0_noc_we = 0;
    t1_noc_addr = 0; t1_noc_wdata = 0; t1_noc_rw = 0; t1_noc_we = 0;
    pass_count = 0;

    // Wait for reset deassertion
    wait(!rst);
    repeat(5) @(posedge clk);

    $display("[%0t] === LobsterPawn Integration Test ===", $time);

    // ------------------------------------------------------------------
    // Test 1: Tile 0 → Tile 1, payload 0xDEAD_BEEF
    // ------------------------------------------------------------------
    $display("[%0t] TEST 1: Tile0(0,0) -> Tile1(4,4)  payload=0xDEADBEEF", $time);
    adapter_write(NOC_TX_DATA, 32'hDEAD_BEEF, 0);           // write payload
    adapter_write(NOC_TX_DST,  {26'b0, 3'd4, 3'd4}, 0);    // DST=(4,4), triggers send

    // Poll tile 1 status until rx_valid
    cycle_count = 0;
    read_val = 0;
    while (!read_val[0] && cycle_count < TIMEOUT) begin
        adapter_read(NOC_RX_STATUS, 1, read_val);
        cycle_count = cycle_count + 1;
        @(posedge clk);
    end
    if (cycle_count >= TIMEOUT) begin
        $display("[%0t] FAIL: Tile1 rx_valid never asserted", $time);
    end else begin
        adapter_read(NOC_RX_DATA, 1, read_val);
        if (read_val === 32'hDEAD_BEEF) begin
            $display("[%0t] PASS: Tile1 received 0x%08X", $time, read_val);
            pass_count = pass_count + 1;
        end else begin
            $display("[%0t] FAIL: Tile1 got 0x%08X, expected 0xDEADBEEF", $time, read_val);
        end
        adapter_write(NOC_RX_ACK, 32'h1, 1);  // clear tile 1 buffer
    end

    repeat(10) @(posedge clk);

    // ------------------------------------------------------------------
    // Test 2: Tile 1 → Tile 0, payload 0xCAFE_1234
    // ------------------------------------------------------------------
    $display("[%0t] TEST 2: Tile1(4,4) -> Tile0(0,0)  payload=0xCAFE1234", $time);
    adapter_write(NOC_TX_DATA, 32'hCAFE_1234, 1);
    adapter_write(NOC_TX_DST,  {26'b0, 3'd0, 3'd0}, 1);    // DST=(0,0)

    cycle_count = 0;
    read_val = 0;
    while (!read_val[0] && cycle_count < TIMEOUT) begin
        adapter_read(NOC_RX_STATUS, 0, read_val);
        cycle_count = cycle_count + 1;
        @(posedge clk);
    end
    if (cycle_count >= TIMEOUT) begin
        $display("[%0t] FAIL: Tile0 rx_valid never asserted", $time);
    end else begin
        adapter_read(NOC_RX_DATA, 0, read_val);
        if (read_val === 32'hCAFE_1234) begin
            $display("[%0t] PASS: Tile0 received 0x%08X", $time, read_val);
            pass_count = pass_count + 1;
        end else begin
            $display("[%0t] FAIL: Tile0 got 0x%08X, expected 0xCAFE1234", $time, read_val);
        end
        adapter_write(NOC_RX_ACK, 32'h1, 0);
    end

    repeat(10) @(posedge clk);

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    if (pass_count == 2)
        $display("[%0t] *** ALL TESTS PASSED (%0d/2) ***", $time, pass_count);
    else
        $display("[%0t] *** TESTS FAILED (%0d/2 passed) ***", $time, pass_count);

    $finish;
end

// Timeout watchdog
initial begin
    #(TIMEOUT * CLK_HALF * 2 * 10);
    $display("FATAL: global simulation timeout");
    $finish;
end

endmodule
