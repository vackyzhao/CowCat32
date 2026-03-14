`timescale 1ns / 1ps

// 1-bit pipeline register with hold + active-low flush.
// Semantics match pp_register/pp_register_inst:
// - async reset (rst=0) clears to 0
// - hold has highest priority
// - flush is active-low: when flush==0, q<=set_data
module pp_register_bit(
    input  wire clk,
    input  wire rst,
    input  wire hold,
    input  wire flush,
    input  wire d,
    input  wire set_data,
    output reg  q
);

initial begin
    q <= 1'b0;
end

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        q <= 1'b0;
    end else if (hold) begin
        q <= q;
    end else if (!flush) begin
        q <= set_data;
    end else begin
        q <= d;
    end
end

endmodule
