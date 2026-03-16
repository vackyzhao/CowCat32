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
    case(inst_5)
        5'b00000  :  hold = ((im_ack | dm_ack) == 1) ? 0 : 1;
        5'b01000  :  hold = ((im_ack | dm_ack) == 1) ? 0 : 1;
        default   :  hold = (im_ack == 0) ?  1 : 0;
        //       case(hold)
             //0 : q <= d;
            // 1 : q <= q;
    endcase
end
endmodule
