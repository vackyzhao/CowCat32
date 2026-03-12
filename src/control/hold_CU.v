`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/11/2023 07:56:18 PM
// Design Name: 
// Module Name: halt_CU
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


module hold_CU(dm_ack, im_ack, hold, inst_5);
input dm_ack, im_ack; //both im_ack and dm_ack both arrive and leave at the negedge of the clk
output reg hold;
input [4:0] inst_5; //from inst_ma
reg buffer;
always@(*)
begin
    // For memory ops (LOAD/STORE), stall until data memory acks.
    // For other ops, stall only if instruction memory acks are modeled.
    case(inst_5)
        5'b00000  :  hold = (dm_ack == 0); // LOAD
        5'b01000  :  hold = (dm_ack == 0); // STORE
        default   :  hold = (im_ack == 0);
    endcase
end
endmodule
