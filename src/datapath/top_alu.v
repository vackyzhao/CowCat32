`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 03/29/2023 09:13:18 PM
// Design Name: ALU
// Module Name: top_alu
// Project Name: CPI 5 CPU
// Target Devices: None
// Tool Versions: Vivado 2017.4
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module top_alu(pc,
               d1,
               d2,
               imm,
               alu_forward,
               din,
               A_sel,
               B_sel,
               alu_ctl,
               alu_out,
               trim_forward);
    input [31:0] pc, d1, d2, imm, alu_forward, din, trim_forward;
    input [2:0]A_sel, B_sel;
    input [4:0] alu_ctl;
    output [31:0] alu_out;
    wire [31:0] alu_a, alu_b;
    alu_mux alu_mux(.pc(pc),.d1(d1), .d2(d2),.imm(imm), .alu_forward(alu_forward),.din(din),.A_sel(A_sel),.B_sel(B_sel),.A_out(alu_a),.B_out(alu_b), .trim_forward(trim_forward));
    alu alu(.alu_a(alu_a),.alu_b(alu_b),.alu_out(alu_out),.alu_ctl(alu_ctl));
    
endmodule
