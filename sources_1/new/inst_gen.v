`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/02/2023 01:27:18 PM
// Design Name: 
// Module Name: IMEM
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


module inst_gen(inst, clk, immi, imms, immb, immu, immuj, func3, rst, inst_sel, rs1, rs2, rd);
input [4:0] rs1, rs2, rd; 
parameter
opcode_r = 7'b0110_011,
opcode_i = 7'b0010_011,
opcode_l = 7'b0000_011,
opcode_s = 7'b0100_011,
opcode_b = 7'b1100_011,
opcode_u = 7'b0110_111,
opcode_uj = 7'b1101_111,
func7_x = 7'b0000_000,
func7_s = 7'b0100_000;
input [2:0] func3;
input [11:0] immi, imms, immb;
input [19:0] immu, immuj;
input clk, rst;
input [3:0] inst_sel;

wire [31:0] R_inst_1 = {func7_x, rs2, rs1, func3, rd, opcode_r};
wire [31:0] R_inst_2 = {func7_s, rs2, rs1, func3, rd, opcode_r};
wire [31:0] I_inst = {immi, rs1, func3, rd, opcode_i};
wire [31:0] L_inst = {immi, rs1, func3, rd, opcode_l};
wire [31:0] S_inst = {imms[11:5], rs1, func3, imms[4:0], opcode_s};
wire [31:0] B_inst = {immb[11], immb[9:4], rs2, rs1, func3, immb[3:0], immb[10],opcode_b};
wire [31:0] U_inst = {immu, rd, opcode_u};
wire [31:0] UJ_inst = {immuj[19], immuj[9:0], immuj[10], immuj[18:11], rd, opcode_uj};
output reg[31:0] inst;
always@(negedge rst or posedge clk)
begin
    if(rst == 0)
    inst <= 0;
    else
    begin
        case(inst_sel)
            1:inst <= R_inst_1;
            2:inst <= R_inst_2;
            3:inst <= I_inst;
            4:inst <= L_inst;
            5:inst <= S_inst;
            6:inst <= B_inst;
            7:inst <= U_inst;
            8:inst <= UJ_inst;
            default inst <= 32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx;        
        endcase
    end  
end

endmodule
