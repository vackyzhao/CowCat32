`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/03/30 16:47:26
// Design Name: 
// Module Name: ControlUnit
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
module ID_CU(op_id,imm_sel);
input [8:0] op_id;
output [3:0] imm_sel;
ControlUnit id_cu(.inst_9(op_id) , .pc_sel(), .reg_wrt(), .imm_sel(imm_sel), .A_sel(), .B_sel(), .alu_ctl(), .b_cmp(1'b0), .dm_ctl(), .trim_ctl(), .din_sel());
endmodule

module EX_CU(op_ex,A_sel,B_sel,alu_ctl, pc_sel, b_cmp);
input [8:0] op_ex;
output A_sel,B_sel;
input b_cmp;
output [4:0] alu_ctl;
output [1:0] pc_sel;
ControlUnit id_cu(.inst_9(op_ex) , .pc_sel(pc_sel), .reg_wrt(), .imm_sel(), .A_sel(A_sel), .B_sel(B_sel), .alu_ctl(alu_ctl), .b_cmp(b_cmp), .dm_ctl(), .trim_ctl(), .din_sel());
endmodule

module MA_CU(op_ma,trim_ctl,din_sel,dm_ctl);
input [8:0] op_ma;
output [2:0] trim_ctl;
output [1:0] din_sel;
output [3:0] dm_ctl;
ControlUnit id_cu(.inst_9(op_ma) , .pc_sel(), .reg_wrt(), .imm_sel(), .A_sel(), .B_sel(), .alu_ctl(), .b_cmp(0), .dm_ctl( dm_ctl), .trim_ctl(trim_ctl), .din_sel(din_sel));
endmodule

module WB_CU(op_wb,reg_wrt);
input [8:0] op_wb;
output reg_wrt;
ControlUnit id_cu(.inst_9(op_wb) , .pc_sel(), .reg_wrt(reg_wrt), .imm_sel(), .A_sel(), .B_sel(), .alu_ctl(), .b_cmp(0), .dm_ctl(), .trim_ctl(), .din_sel());
endmodule


module ControlUnit(inst_9 ,pc_sel,reg_wrt,imm_sel,A_sel,B_sel,alu_ctl,b_cmp,dm_ctl,trim_ctl,din_sel);

input [8:0] inst_9;
input b_cmp;

output [2:0] trim_ctl;
output [3:0] dm_ctl;
output [1:0] din_sel;
output [1:0] pc_sel = 0;
output reg_wrt;
output [3:0] imm_sel;
output A_sel,B_sel;
output [4:0] alu_ctl;

reg [2:0] trim_ctl;
reg [3:0] dm_ctl;
reg [1:0] din_sel;
reg [1:0] pc_sel;
reg reg_wrt;
reg [3:0] imm_sel;
reg  A_sel,B_sel;
reg [4:0] alu_ctl;

/*

signed 0
 The format for trim:[2:0]
 I   x001
 IS  x010 (this is for SLLI, SRLI, and SRA)
 S   x011
 B   x100
 U   x101
 J   x110
 
*/
//immsel

//imm_mux_ctrl
parameter I_imm= 4'b0001,
IS_imm=4'b0010,
S_imm=4'b0011,
B_imm=4'b0100,
U_imm=4'b0101,
J_imm=4'b0110,
IU_imm=4'b1001;

//trim_ctrl
parameter LW = 3'b000,
LH = 3'b001,
LB = 3'b010,
LBU = 3'b011,
LHU = 3'b100;

//alu
parameter ADD  = 5'b0000_1, 
SLT = 5'b0001_0, 
SLTU = 5'b0001_1,
AND = 5'b0010_0,
OR = 5'b0010_1,
XOR = 5'b0011_0,
SLL = 5'b0011_1,
SRL = 5'b0100_0,
SUB = 5'b0100_1,
SRA = 5'b0101_0,
BEQ = 5'b0101_1,
BNE = 5'b0110_0,
BLT = 5'b0110_1,
BLTU = 5'b0111_0,
BGE = 5'b0111_1,
BGEU = 5'b1000_0,
LUI = 5'b1000_1,
ADDU = 5'b10010;


//wire [9:0] inst_9={inst_9[8:0],b_cmp};//inst_9[9:0]={ b_cmp,inst[30], inst[14:12], inst[6:2] };
wire [14:0] CU_out;

    always@(*)begin
        //initalize output
        pc_sel=2'b0;
        reg_wrt=2'b00;
        imm_sel=4'b0000;
        A_sel=1'b0;
        B_sel=1'b0;     
        alu_ctl=5'b0000_0;
        dm_ctl=4'b0000;
        trim_ctl=3'b000;
        din_sel=2'b00;


    case(inst_9[4:0])
         //R type
        5'b01100:begin
                reg_wrt=1'b1; 
                A_sel=1'b1;                                              
                B_sel=1'b0;
                din_sel=2'b10;
                case(inst_9[7:5])
                        3'b000:begin
                                case(inst_9[8])
                                1'b0:alu_ctl=ADD;//ADD
                                1'b1:alu_ctl=SUB;//SUB
                                //default:alu_ctl=5'b00000;
                                endcase
                        end
                        3'b010:alu_ctl=SLT;//SLT
                        3'b011:alu_ctl=SLTU;//SLTU
                        3'b111:alu_ctl=AND;//AND
                        3'b110:alu_ctl=OR;//OR
                        3'b100:alu_ctl=XOR;//XOR
                        3'b001:alu_ctl=SLL;//SLL
                        3'b101:begin
                                case(inst_9[8])
                                1'b0:alu_ctl=SRL;//SRL
                                1'b1:alu_ctl=SRA;//SRA
                                //default:alu_ctl=5'b00000;
                                endcase
                        end
                        //default:alu_ctl=5'b00000;        
                endcase
                end
        //I type
        5'b00100:begin  
                reg_wrt=1'b1;                                                
                A_sel=1'b1;
                B_sel=1'b1;
                din_sel=2'b10;
                 imm_sel=I_imm;
                case(inst_9[7:5])
                        3'b000:alu_ctl=ADD;//ADDI
                        3'b010:alu_ctl=SLT;//SLTI
                        3'b011:begin
                                imm_sel=IU_imm;
                                alu_ctl=SLTU;//SLTIU                                
                        end
                        3'b111:alu_ctl=AND;//ANDI
                        3'b110:alu_ctl=OR;//ORI
                        3'b100:alu_ctl=XOR;//XORI
                        3'b001:alu_ctl=SLL;//SLLI
                        3'b101:begin
                        case(inst_9[8])
                            1'b0:alu_ctl=SRL;//SRLI
                            1'b1:alu_ctl=SRA;//SRAI
                            default:alu_ctl=5'bXXXXX;
                            endcase
                           end 
                        default:alu_ctl=5'bXXXXX;
                endcase    
                end
        //Load (I)
        5'b00000:begin
                reg_wrt=1'b1;
                imm_sel = I_imm;
                A_sel=1'b1;
                B_sel=1'b1;
                alu_ctl=ADD;
                din_sel=2'b11;
                dm_ctl = 4'b0000;
                case(inst_9[7:5])
                3'b000:trim_ctl=LB;//LB
                3'b001:trim_ctl=LH;//LH
                3'b010:trim_ctl=LW;//LW
                3'b100:begin//LBU
                        alu_ctl=ADDU;
                        trim_ctl=LBU;
                end
                3'b101:begin//LHU
                        alu_ctl=ADDU;
                        trim_ctl=LHU;
                end
                endcase            
                end
        //S type
        5'b01000:begin
                imm_sel = S_imm;
                A_sel = 1'b1;
                B_sel =  1'b1;
                din_sel=2'b00;
                alu_ctl = ADD;
                case(inst_9[7:5])
                3'b000:dm_ctl=4'b001;//SB
                3'b001:dm_ctl=4'b0011;//SH
                3'b010:dm_ctl=4'b1111;//SW
                endcase            
                end    
        //B type
        5'b11000:begin
                imm_sel=B_imm;  
                A_sel=1'b0;
                B_sel=1'b1;
                din_sel=2'b00;
                case(inst_9[7:5])
                3'b000:alu_ctl= BEQ;//BEQ
                3'b001:alu_ctl=BNE;//BNE
                3'b100:alu_ctl=BLT;//BLT
                3'b101:alu_ctl=BGE;//BGE
                3'b110:alu_ctl=BLTU;//BLTU
                3'b111:alu_ctl=BGEU;//BGEU
                endcase
                case(b_cmp)
                1'b0:pc_sel=0;
                1'b1:pc_sel=1;
                endcase
        
                end
        //LUI
        5'b01101:begin
                reg_wrt=1'b1;
                imm_sel=U_imm;
                A_sel=1'bx;
                B_sel=1'b1;
                alu_ctl=LUI;
                din_sel=2'b10;
        
                end
        //AUIPC
        5'b00101:begin
                reg_wrt=1'b1;
                imm_sel=U_imm;
                A_sel=1'b0;
                B_sel=1'b1;
                alu_ctl=LUI;
                din_sel=2'b10;
        
                end
        //JAL
        5'b11011:begin
                pc_sel=2'b10;
                reg_wrt=1'b1;
                imm_sel=J_imm;
                A_sel=1'b0;
                B_sel=1'b1;                
                din_sel=2'b01;
                alu_ctl=ADD;
                end

        //JALR
        5'b11001:begin
                pc_sel=2'b10;
                reg_wrt=1'b1;
                imm_sel=J_imm;
                A_sel=1'b1;
                B_sel=1'b1;
                alu_ctl=ADD;
                din_sel=2'b01;        
                end        
 
    endcase
    
    end  
   
    
endmodule
