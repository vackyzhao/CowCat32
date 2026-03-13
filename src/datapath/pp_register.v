`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/11/2023 08:25:06 PM
// Design Name: 
// Module Name: pp_register
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
`define NOP  32'b0000_0000_0000_000000_000_00000_0010011


module pp_register(clk, hold, q, d, rst, flush, set_data);
input clk, hold, rst, flush;
input [31:0]set_data;
input [31:0] d;
output reg [31:0] q;
initial
begin
q <= 0;
end
always@(posedge clk or negedge rst)
    begin
    if(rst == 0 )
        q <= 0;
    else if (flush == 0)
        q <= set_data;
       else begin
       case(hold)
            0 : q <= d;
            1 : q <= q;
            default : q <= q;
        endcase
        end
    end 
endmodule