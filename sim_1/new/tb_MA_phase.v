`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/30/2023 07:35:36 PM
// Design Name: 
// Module Name: tb_MA_phase
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
//module MA_phase(alu_out, pc, data, din_mux_sel, trim_ctl, WB_reg, clk, rst)
/*
input signed [31:0]alu_out, data;
input [31:0] pc;
input [1:0] din_mux_sel;
input [2:0] trim_ctl;
input clk, rst;
output reg [31:0] WB_reg = 0;
wire [31:0] data_out;




*/

module tb_MA_phase();
parameter 
LW = 3'b000,
LH = 3'b001,
LB = 3'b010,
LBU = 3'b011,
LHU = 3'b100;

reg [31:0] alu_out, data, pc;
reg [1:0] din_mux_sel;
reg [2:0] trim_ctl;
reg clk, rst;
wire [31:0] WB_reg;
ma_module ma_module(.alu_out(alu_out),.d2_ex(d2_ex), .pc_ex(pc_ex), .din_sel(din_sel), .trim_ctl(trim_ctl), .clk(clk), .rst(rst), .WB_reg(WB_reg));
//module MA_phase(alu_out, pc_ex, d2_ex, din_sel, trim_ctl, WB_reg, clk, rst, inst_ex, inst_ma, op_ma, b_cmp);
initial
begin
clk = 0;alu_out = 32'b1111_0000_1010_0101_1100_0011_1110_0111; d2_ex = 32'b1110_0111_1100_0011_1010_0101_0000_1111; pc_ex = 32'b0000_1111_0101_1010_0011_1100_0001_1000;
#2 rst = 1; din_sel = 1; trim_ctl = LW;
#2 rst = 1; din_sel = 2; trim_ctl = LW;
#2 rst = 1; din_sel = 3; trim_ctl = LW;
#2 rst = 1; din_sel = 1; trim_ctl = LW;
#2 rst = 1; din_sel = 1; trim_ctl = LH;
#2 rst = 1; din_sel = 1; trim_ctl = LB;
#2 rst = 1; din_sel = 1; trim_ctl = LHU;
#2 rst = 1; din_sel = 1; trim_ctl = LBU;
#2 rst = 1; din_sel = 2; trim_ctl = LW;
#2 rst = 1; din_sel = 2; trim_ctl = LH;
#2 rst = 1; din_sel = 2; trim_ctl = LB;
#2 rst = 1; din_sel = 2; trim_ctl = LHU;
#2 rst = 1; din_sel = 2; trim_ctl = LBU;
#2 rst = 1; din_sel = 3; trim_ctl = LW;
#2 rst = 1; din_sel = 3; trim_ctl = LH;
#2 rst = 1; din_sel = 3; trim_ctl = LB;
#2 rst = 1; din_sel = 3; trim_ctl = LHU;
#2 rst = 1; din_sel = 3; trim_ctl = LBU;
#10 $stop;


end

always
begin
#1 clk =~ clk;
end


endmodule
