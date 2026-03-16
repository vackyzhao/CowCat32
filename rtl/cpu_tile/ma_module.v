`timescale 1ns / 1ps
`define NOP 32'b0000_0000_0000_000000_000_00000_0010011
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/30/2023 04:31:47 PM
// Design Name: 
// Module Name: MA_phase
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
/*
module trim_extender(trim_ctl, data_out,data);
input [2:0] trim_ctl;
input [31:0] data;
output reg [31:0] data_out;

*/

module ma_module(alu_out, pc_ma, dm_load, din_sel, trim_ctl, din, clk, rst, inst_ma, inst_wb, op_ma, b_cmp,d2_ma, dm_store, dm_addr, hold, trim_forward);
output wire[8:0] op_ma;
output wire b_cmp;
input [31:0]alu_out, dm_load, inst_ma,d2_ma;
input [31:0] pc_ma;
input [1:0] din_sel;
input [2:0] trim_ctl;
input clk, rst, hold;
output [31:0] din; 
output [31:0] inst_wb, trim_forward;
output wire[31:0] dm_addr, dm_store;
wire [31:0] trim_out, din_temp;
assign b_cmp = alu_out[0];
assign op_ma = {inst_ma[30], inst_ma[14:12], inst_ma[6:2]};
assign dm_store = d2_ma;
assign dm_addr = alu_out;
assign trim_forward = trim_out;
wire flush;
pp_register din_pp(.d(din_temp), .q(din),.set_data(32'b0), .clk(clk), .rst(rst), .flush(1), .hold(hold));
pp_register inst_wb_pp(.d(inst_ma), .q(inst_wb),.set_data(32'b0), .clk(clk), .rst(rst), .flush(1), .hold(hold));
//parameter 
//LW = 3'b000,
//LH = 3'b001,
//LB = 3'b010,
//LBU = 3'b011,
//LHU = 3'b100;
trim_extender trim_extender(.trim_ctl(trim_ctl), .trim_out(trim_out), .trim_in(dm_load)); 
din_MUX din_MUX(.alu_out(alu_out), .din_sel(din_sel), .pc_ma(pc_ma), .trim_out(trim_out), .din(din_temp)); //module din_MUX(alu_out, din_sel, pc_ma, trim_out, din);

endmodule
