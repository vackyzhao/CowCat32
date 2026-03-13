`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/04/06 19:34:11
// Design Name: 
// Module Name: mem
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
module im_mem(clk,im_addr,im_inst, im_ack, rst);
input clk, rst;
input [31:0] im_addr;
output  [31:0] im_inst;
output im_ack;
inst_mem i_mem(.clk(clk),.rst(rst),.wr_en(0),.rd_en(1),.addr(im_addr),.im_inst(im_inst), .ack(im_ack), .hold_dm(hold_dm));
endmodule

//ram.v
module inst_mem(
    input                   hold_dm,
    input                   clk,
    input                   rst,
    input                   wr_en,
    input                   rd_en,
    input [31:0]             addr,
    output[31:0]            im_inst,
    output reg ack,
    output count_debug
);
    reg[2:0] count_inst;
    assign count_debug = count_inst;

    reg [7:0]        bram[1023:0];    
    integer          i;   
    wire [31:0]       data;   
    assign data = {bram[addr[7:0]+3],bram[addr[7:0]+2],bram[addr[7:0]+1],bram[addr[7:0]]};
    initial
    begin
    count_inst <= 0;
    end
    always@(posedge clk or negedge rst)
    begin
        if(rst == 0) count_inst <= 0;
        else
        begin
        count_inst <= (count_inst + 1) % 4; 
        end      
    end
    always@(negedge clk or negedge rst)
    begin
        if(rst == 0) ack <= 1;
        else
        begin
        case(count_inst)
           3 : ack = 1;
           0: ack = 0;
           default: ack = 0;
        endcase
        end
    end
    always@(posedge clk or negedge rst)
    begin
 
bram[0] = 8'b1000_0011;
    bram[1] = 8'b0000_1000;
    bram[2] = 8'b0000_0000;
    bram[3] = 8'b0000_0101;
    
    bram[4] = 8'b0000_0011;
    bram[5] = 8'b0001_1001;
    bram[6] = 8'b0110_0000;
    bram[7] = 8'b0000_0100;
    
    bram[8] = 8'b1000_0011;
    bram[9] = 8'b0010_1001;
    bram[10] = 8'b1100_0000;
    bram[11] = 8'b0000_0011;
    
    bram[12] = 8'b0000_0011;
    bram[13] = 8'b0100_1010;
    bram[14] = 8'b0010_0000;
    bram[15] = 8'b0000_0011;
    
    bram[16] = 8'b1000_0011;
    bram[17] = 8'b0101_1010;
    bram[18] = 8'b1110_0000;
    bram[19] = 8'b0000_0001;
    
    bram[20] = 8'b0010_0011;
    bram[21] = 8'b0000_0000;
    bram[22] = 8'b0110_0000;
    bram[23] = 8'b0010_1001;
    
    bram[24] = 8'b0010_0011;
    bram[25] = 8'b0001_0000;
    bram[26] = 8'b0111_0000;
    bram[27] = 8'b0001_0101;
    
    bram[28] = 8'b0010_0011;
    bram[29] = 8'b0010_0000;
    bram[30] = 8'b1000_0000;
    bram[31] = 8'b0000_0001;
    
    bram[32] = 8'b1001_0011;
    bram[33] = 8'b0000_0000;
    bram[34] = 8'b1010_0001;
    bram[35] = 8'b0000_0000;
    
    bram[36] = 8'b1001_0011;
    bram[37] = 8'b0010_0001;
    bram[38] = 8'b0100_0010;
    bram[39] = 8'b0000_0001;
    
    bram[40] = 8'b1001_0011;
    bram[41] = 8'b0011_0010;
    bram[42] = 8'b1110_0011;
    bram[43] = 8'b0000_0001;
    
    bram[44] = 8'b1001_0011;
    bram[45] = 8'b0100_0011;
    bram[46] = 8'b1000_0100;
    bram[47] = 8'b0000_0010;
    
    bram[48] = 8'b1001_0011;
    bram[49] = 8'b0110_0100;
    bram[50] = 8'b0010_0101;
    bram[51] = 8'b0000_0011;
    
    bram[52] = 8'b1001_0011;
    bram[53] = 8'b0111_0101;
    bram[54] = 8'b1100_0110;
    bram[55] = 8'b0000_0011;
    
    bram[56] = 8'b1001_0011;
    bram[57] = 8'b0001_0110;
    bram[58] = 8'b0110_0111;
    bram[59] = 8'b0000_0100;
    
    bram[60] = 8'b1001_0011;
    bram[61] = 8'b0101_0111;
    bram[62] = 8'b0000_1000;
    bram[63] = 8'b0000_0101;
    
    bram[64] = 8'b1001_0011;
    bram[65] = 8'b0101_1000;
    bram[66] = 8'b1010_1001;
    bram[67] = 8'b0100_0101;
    
    bram[68] = 8'b1011_0011;
    bram[69] = 8'b0000_1001;
    bram[70] = 8'b0101_1010;
    bram[71] = 8'b0000_0001;
    
    bram[72] = 8'b1011_0011;
    bram[73] = 8'b0000_1010;
    bram[74] = 8'b0111_1011;
    bram[75] = 8'b0100_0001;
    
    bram[76] = 8'b1011_0011;
    bram[77] = 8'b0001_0000;
    bram[78] = 8'b0011_0001;
    bram[79] = 8'b0000_0000;
    
    bram[80] = 8'b0011_0011;
    bram[81] = 8'b1010_0010;
    bram[82] = 8'b0110_0010;
    bram[83] = 8'b0000_0000;
    
    bram[84] = 8'b1011_0011;
    bram[85] = 8'b0011_0011;
    bram[86] = 8'b1001_0100;
    bram[87] = 8'b0000_0000;
    
    bram[88] = 8'b0011_0011;
    bram[89] = 8'b1011_0101;
    bram[90] = 8'b1100_0101;
    bram[91] = 8'b0000_0000;
    
    bram[92] = 8'b1011_0011;
    bram[93] = 8'b0100_0110;
    bram[94] = 8'b1111_0111;
    bram[95] = 8'b0000_0000;
    
    bram[96] = 8'b0011_0011;
    bram[97] = 8'b1101_1000;
    bram[98] = 8'b0010_1000;
    bram[99] = 8'b0000_0001;
    
    bram[100] = 8'b1011_0011;
    bram[101] = 8'b0101_1001;
    bram[102] = 8'b0101_1010;
    bram[103] = 8'b0100_0001;
    
    bram[104] = 8'b1011_0011;
    bram[105] = 8'b0110_0000;
    bram[106] = 8'b0011_0001;
    bram[107] = 8'b0000_0000;
    
    bram[108] = 8'b1011_0011;
    bram[109] = 8'b0111_0010;
    bram[110] = 8'b0111_0011;
    bram[111] = 8'b0000_0000;
    
    bram[112] = 8'b0011_0011;
    bram[113] = 8'b1110_0100;
    bram[114] = 8'b1010_0100;
    bram[115] = 8'b0000_0000;
    
    bram[116] = 8'b1011_0111;
    bram[117] = 8'b1010_0000;
    bram[118] = 8'b0000_0000;
    bram[119] = 8'b0000_0000;
    
    bram[120] = 8'b0110_1111;
    bram[121] = 8'b0000_0000;
    bram[122] = 8'b1000_0000;
    bram[123] = 8'b0000_0000;
    
    bram[124] = 8'b1001_0011;
    bram[125] = 8'b1000_0000;
    bram[126] = 8'b0000_0000;
    bram[127] = 8'b0000_0000;
    
    bram[128] = 8'b1001_0011;
    bram[129] = 8'b1000_0000;
    bram[130] = 8'b0001_0000;
    bram[131] = 8'b0000_0000;
    
    bram[132] = 8'b1110_0111;
    bram[133] = 8'b0000_0000;
    bram[134] = 8'b1100_0000;
    bram[135] = 8'b0000_1000;
    
    bram[136] = 8'b1001_0011;
    bram[137] = 8'b1000_0000;
    bram[138] = 8'b0000_0000;
    bram[139] = 8'b0000_0000;
    
    bram[140] = 8'b1001_0011;
    bram[141] = 8'b1000_0000;
    bram[142] = 8'b0001_0000;
    bram[143] = 8'b0000_0000;
         
       if (rst == 0)   
         begin
           for(i=0;i<=1023;i=i+1) //reset, °´×Ö²Ù×÷
           bram[i] <= 8'b0;
         end
         end
assign im_inst = data;
endmodule
