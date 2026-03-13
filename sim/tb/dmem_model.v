`timescale 1ns/1ps

// Generic data-memory model with mem_req/we/re handshake + randomized response latency.
//
// - Word-addressed memory (dm_addr is byte address; index uses [ADDR_MSB:ADDR_LSB])
// - Store commits at accept-time (when data_req seen) to make the blackbox TB
//   robust against ack timing artifacts.
// - dm_ack is a one-cycle pulse, generated on negedge clk so it is stable for
//   the next posedge sampling.
//
// Plusargs:
//   +seed=<int>    : seed for $urandom
//   +nostall       : disable randomized latency (use BASE_LATENCY)
//
module dmem_model #(
    parameter integer DEPTH_WORDS  = 256,
    parameter integer ADDR_LSB     = 2,
    parameter integer ADDR_MSB     = 9,
    parameter integer BASE_LATENCY = 3
) (
    input  wire        clk,
    input  wire        rst,

    // request side
    input  wire        mem_req,
    input  wire        mem_we,
    input  wire        mem_re,
    input  wire [31:0] dm_addr,
    input  wire [31:0] dm_store,
    input  wire [3:0]  dm_ctl,

    // response side
    output reg         dm_ack,
    output reg  [31:0] dm_load
);

    // memory array
    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer i;
    initial begin
        for (i=0;i<DEPTH_WORDS;i=i+1) mem[i] = 32'h0;
    end

    wire [ADDR_MSB-ADDR_LSB:0] widx = dm_addr[ADDR_MSB:ADDR_LSB];

    // combinational read data (stable while address stable)
    always @(*) begin
        dm_load = mem[widx];
    end

    integer seed;
    integer RANDOM_LATENCY;
    initial begin
        RANDOM_LATENCY = 1;
        if ($test$plusargs("nostall")) RANDOM_LATENCY = 0;
        if ($value$plusargs("seed=%d", seed)) begin
            $urandom(seed);
        end
    end

    reg dmem_busy;
    reg [3:0] dmem_cnt;

    wire data_req = mem_req && (mem_we || mem_re);

    function [31:0] apply_wmask;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0]  be;
        reg [31:0] m;
        begin
            m = { {8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}} };
            apply_wmask = (oldv & ~m) | (newv & m);
        end
    endfunction

    initial begin
        dm_ack    = 1'b0;
        dmem_busy = 1'b0;
        dmem_cnt  = 0;
    end

    always @(negedge clk or negedge rst) begin
        if (!rst) begin
            dm_ack    <= 1'b0;
            dmem_busy <= 1'b0;
            dmem_cnt  <= 0;
        end else begin
            dm_ack <= 1'b0;
            if (!dmem_busy) begin
                if (data_req) begin
                    dmem_busy <= 1'b1;
                    if (RANDOM_LATENCY) begin
                        dmem_cnt <= ($urandom % 7) + 1;
                    end else begin
                        dmem_cnt <= BASE_LATENCY;
                    end

                    // Commit stores at accept-time.
                    if (mem_we) begin
                        mem[widx] <= apply_wmask(mem[widx], dm_store, dm_ctl);
                    end
                end
            end else begin
                if (dmem_cnt != 0) begin
                    dmem_cnt <= dmem_cnt - 1;
                end else begin
                    dm_ack <= 1'b1;
                    dmem_busy <= 1'b0;
                end
            end
        end
    end

endmodule
