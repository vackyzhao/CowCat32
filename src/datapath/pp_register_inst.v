`timescale 1ns / 1ps
`define NOP  32'b0000_0000_0000_000000_000_00000_0010011

module pp_register_inst(
    input         clk,
    input         hold,
    input         rst,
    input         flush,
    input  [31:0] d,
    input  [31:0] rst_set_data,
    input  [31:0] flush_set_data,
    output reg [31:0] q
);

initial begin
    q <= rst_set_data;
end

always @(posedge clk or negedge rst) begin
    if (!rst)
        q <= rst_set_data;
    else if (flush == 0)
        q <= flush_set_data;
    else if (!hold)
        q <= d;
end

endmodule