`timescale 1ns/1ps

// Simple byte-write-enabled SRAM model (1RW).
// - Byte-addressed interface
// - Asynchronous read (combinational) for simple bring-up.
//   (On FPGA BRAM you may replace with synchronous read implementation.)
module sram_1rw #(
    parameter integer DEPTH_WORDS = 131072,  // 512 KiB
    parameter integer ADDR_LSB    = 2
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        req,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,

    output wire [31:0] rdata,
    output wire        ack
);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
    end

    wire [$clog2(DEPTH_WORDS)-1:0] widx = addr[ADDR_LSB +: $clog2(DEPTH_WORDS)];

    // combinational read
    assign rdata = mem[widx];

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

    // write on accept
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            // no-op
        end else if (req && we) begin
            mem[widx] <= apply_wmask(mem[widx], wdata, wstrb);
        end
    end

    // zero-wait-state model
    assign ack = req;

endmodule
