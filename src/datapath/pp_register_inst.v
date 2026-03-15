`timescale 1ns / 1ps
`define NOP 32'b0000_0000_0000_000000_000_00000_0010011

// Pipeline register for instructions with explicit reset/flush set values.
// This matches the port pattern used in src/core/ex_module.v and ma_module.v.
module pp_register_inst(
    input        clk,
    input        hold,
    input        rst,
    input        flush,
    input [31:0] d,
    input [31:0] rst_set_data,
    input [31:0] flush_set_data,
    output reg [31:0] q
);

initial begin
    q <= `NOP;
end

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        q <= rst_set_data;
    end else if (!flush) begin
        q <= flush_set_data;
    end else begin
        if (!hold)
            q <= d;
        else
            q <= q;
    end
end

endmodule
