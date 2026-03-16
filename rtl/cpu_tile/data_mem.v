`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/04/06 22:51:03
// Design Name: 
// Module Name: data_mem
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


module data_mem(
    input                   rst,clk, 
    input [3:0]             dm_ctl     ,
    input [31:0]             addr,
    input [31:0]            dm_store,
    output[31:0]           dm_load,
    output reg             dm_ack 
);

    reg [7:0]          bram[255:0];    
    integer          i;   
   assign dm_load = {bram[addr[7:0]+3],bram[addr[7:0]+2], bram[addr[7:0]+1], bram[addr[7:0]]};
   initial
   begin
   for(i=0;i<256;i=i+1)
   begin
       bram[i] = i;
   end
   bram[80] = 10;
   end
   reg[2:0] count_data;
   initial
   begin
   count_data <= 0;
   end
   always@(negedge rst or posedge clk)
   begin
        if(rst == 0) count_data <= 0;
        else count_data <= (count_data + 1) % 4;
   end
   
   always@(negedge rst or negedge clk)
   begin
        if(rst == 0) dm_ack <= 1;
        else case(count_data)
            3 : dm_ack <= 1;
            0 : dm_ack <= 0;
            default: dm_ack <= 0;
        endcase
   end
   
    always@(negedge rst or posedge clk)
    begin
       if (!rst)   
         begin
           for(i=0;i<256;i=i+1) //reset, °´×Ö²Ù×÷
           bram[i] <= 8'b0;
         end
       else begin
            case(dm_ctl) 
            4'b0001: begin
                    bram[addr[7:0]] = dm_store[7:0];
                    bram[addr[7:0]+1] = 0;
                    bram[addr[7:0]+2] = 0;
                    bram[addr[7:0]+3] = 0;
                    end
            4'b0011: begin
                     bram[addr[7:0]] = dm_store[7:0];
                     bram[addr[7:0]+1] = dm_store[15:8];
                     bram[addr[7:0]+2] = 0;
                     bram[addr[7:0]+3] = 0;
                     end
           4'b1111: begin
                    bram[addr[7:0]] = dm_store[7:0];
                    bram[addr[7:0]+1] = dm_store[15:8];
                    bram[addr[7:0]+2] = dm_store[23:16];
                    bram[addr[7:0]+4] = dm_store[31:24];
                    end
           4'b0000: begin
                    
                    end
           default: dm_ack = 1;     
           endcase
        end    
        
    end

endmodule

