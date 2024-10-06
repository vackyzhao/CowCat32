`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/06/2023 07:38:47 PM
// Design Name: 
// Module Name: imem
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


module imem(im_addr, im_inst, clk, rst, inst);
input [31:0] im_addr, inst;
output [31:0] im_inst;
input clk, rst;

reg [7:0] mem_units [255:0];
integer j;
initial
begin

end
always@(negedge rst or clk)
begin
    
    
    
end
endmodule
