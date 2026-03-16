`timescale 1ns/1ps

// Dual-port SRAM for FPGA-friendly SoC bring-up.
// - IMEM: read-only port (combinational read)
// - DMEM: read/write port with byte enables (combinational read), ack=req
//
// This avoids deadlock with the current CPU hold_CU, which expects im_ack=1
// even during data transactions.
module sram_2p_imem_dmem #(
    parameter integer DEPTH_WORDS = 131072,
    parameter integer ADDR_LSB    = 2
) (
    input  wire        clk,
    input  wire        rst,

    // imem port
    input  wire [31:0] im_addr,
    output wire [31:0] im_rdata,

    // dmem port
    input  wire        dm_req,
    input  wire        dm_we,
    input  wire [31:0] dm_addr,
    input  wire [31:0] dm_wdata,
    input  wire [3:0]  dm_wstrb,
    output wire [31:0] dm_rdata,
    output wire        dm_ack
);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0013; // NOP
        end
    end

    wire [$clog2(DEPTH_WORDS)-1:0] im_widx = im_addr[ADDR_LSB +: $clog2(DEPTH_WORDS)];
    wire [$clog2(DEPTH_WORDS)-1:0] dm_widx = dm_addr[ADDR_LSB +: $clog2(DEPTH_WORDS)];

    assign im_rdata = mem[im_widx];
    assign dm_rdata = mem[dm_widx];

    function [31:0] apply_wmask;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0]  be;
        reg   [31:0] m;
        begin
            m = { {8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}} };
            apply_wmask = (oldv & ~m) | (newv & m);
        end
    endfunction

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            // no-op
        end else if (dm_req && dm_we) begin
            mem[dm_widx] <= apply_wmask(mem[dm_widx], dm_wdata, dm_wstrb);
        end
    end

    assign dm_ack = dm_req;

endmodule
