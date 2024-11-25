`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/30/2023 05:19:34 PM
// Design Name: 
// Module Name: trim_extender
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module trim_extender(trim_ctl, trim_out,trim_in);
input [2:0] trim_ctl;
input [31:0] trim_in;
output reg[31:0] trim_out = 0;
parameter 
LW = 3'b000,
LH = 3'b001,
LB = 3'b010,
LBU = 3'b011,
LHU = 3'b100;

always@(*)
begin
    case(trim_ctl)
    LW: trim_out = trim_in;
    LH: trim_out = {{16{trim_in[16]}}, trim_in[15:0]};
    LB: trim_out = {{24{trim_in[7]}}, trim_in[7:0]};
    LBU: trim_out = $unsigned({{16{1'b0}},trim_in[15:0]});
    LHU: trim_out = $unsigned({{24{1'b0}},trim_in[7:0]});
    default : trim_out = 32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx;
    endcase
end


endmodule
