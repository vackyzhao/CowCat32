`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/05/2023 08:07:36 PM
// Design Name: 
// Module Name: din_MUX
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


module din_MUX(alu_out, din_sel, pc_ma, trim_out, din);
input [31:0] alu_out, pc_ma, trim_out;
input [1:0] din_sel;
output reg [31:0] din;
always@(*)
begin
    case(din_sel)
    1 : din = pc_ma + 4;
    2 : din = alu_out;
    3 : din = trim_out;
    default din = 32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx;
    endcase
    end

endmodule
