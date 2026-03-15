`timescale 1ns / 1ps
`define NOP 32'b0000_0000_0000_000000_000_00000_0010011
module if_module(clk, rst, pc_br, alu_out, pc_sel, im_inst,im_addr, pc_id, inst_id, flush, hold);
    input clk;
    input rst, flush, hold;
    input [31:0] pc_br;    // Branch
    input [31:0] alu_out;        // Jump
    input [1:0] pc_sel;
    
    input [31:0] im_inst;
    wire [31:0] pc;
    output [31:0] im_addr;
    assign im_addr = pc;
    output [31:0] pc_id;
    output [31:0] inst_id;

pc_reg PC_module(
    .clk(clk),
    .rst(rst),
    .pc_br(pc_br),
    .alu_out(alu_out),
    .pc_sel(pc_sel),
    .pc(pc),
    .hold(hold),
    .flush(flush)
);
pp_register inst_id_pp(.q(inst_id),.set_data(`NOP), .d(im_inst), .flush(flush), .hold(hold), .rst(rst), .clk(clk));
pp_register pc_id_pp(.q(pc_id), .d(pc),.set_data(32'b0), .flush(flush), .hold(hold), .rst(rst), .clk(clk));
endmodule