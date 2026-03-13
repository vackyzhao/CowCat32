`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/06/2023 01:26:38 PM
// Design Name: 
// Module Name: tb_CPU
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
module tb_CPU(); //module SynCPU(dm_load, dm_addr, dm_store, im_addr, im_inst, dm_ctl);
wire [31:0]dm_load, dm_addr, dm_store, im_addr;
wire [31:0] im_inst;
wire [3:0] dm_ctl;
reg clk, rst;
/*
module data_mem(
    input                   rst,
    input                   wr_en,
    input [7:0]             addr,
    inout [31:0]            data_io
);*/
SynCPU sim_CPU(.dm_load(dm_load), .dm_addr(dm_addr), .dm_store(dm_store), .im_addr(im_addr), .dm_ctl(dm_ctl), .clk(clk), .im_inst(im_inst), .rst(rst));
inst_mem tb_imem(.clk(clk), .im_addr(im_addr), .im_inst(im_inst)); //module inst_mem(clk,im_addr,im_inst);
data_mem tb_dmem(.rst(rst), .clk(clk), .dm_ctl(dm_ctl), .addr(dm_addr), .dm_store(dm_store), .dm_load(dm_load));
/*
module data_mem(
    input                   rst,clk, 
    input [3:0]             dm_ctl     ,
    input [31:0]             addr,
    input [31:0]            dm_store,
    output reg [31:0]           dm_load
    
);
*/
initial
begin
clk = 0; rst = 1;  //addi 114
//#2 im_inst = 32'b0000000_00001_00010_000_00011_0110011; //add 114+514
#67 rst = 1;
#10 $stop;

end

always
begin
#1    clk = ~clk;
end



endmodule
