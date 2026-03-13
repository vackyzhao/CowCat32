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

input dm_ack, im_ack;
input [4:0] inst_5;   // from inst_ma
output reg hold;

always @(*) begin
    case (inst_5)
        // LOAD / STORE: both instruction fetch and data memory access must be ready
        5'b00000,
        5'b01000: hold = ~ (im_ack & dm_ack);

        // Other instructions: only instruction memory matters
        default:  hold = ~ im_ack;
    endcase
end

endmodule