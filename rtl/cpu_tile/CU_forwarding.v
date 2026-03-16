`timescale 1ns / 1ps

module CU_forwarding(CU_A_sel, CU_B_sel, inst_EX, inst_MA, inst_WB, A_sel, B_sel);
    input   CU_A_sel;
    input   CU_B_sel;
    input   [14:0]inst_EX;
    input   [9:0]inst_MA;
    input   [9:0]inst_WB;
    output  reg[2:0]A_sel;
    output  reg[2:0]B_sel;

    parameter Rtype = 5'b01100;
    parameter Itype = 5'b00100;
    parameter LUI   = 5'b01101;
    parameter AUIPC = 5'b00101;
    parameter JAL   = 5'b11011;
    parameter JALR  = 5'b11001;
    parameter Ltype = 5'b00000;
    parameter Stype = 5'b01000;
    parameter Btype = 5'b11000;


    wire    [4:0] opcode_EX;
    wire    [4:0] opcode_MA;
    wire    [4:0] opcode_WB;
    wire    [4:0] rd_MA, rd_WB;
    wire    [4:0] rs1;
    wire    [4:0] rs2;
    assign opcode_EX = inst_EX[4:0];
    assign opcode_MA = inst_MA[4:0];
    assign opcode_WB = inst_WB[4:0];
    assign rd_MA = inst_MA[9:5];
    assign rd_WB = inst_WB[9:5];   
    assign rs1 = inst_EX[9:5];
    assign rs2 = inst_EX[14:10];

wire [6:0] case_A_ma = {rd_MA, CU_A_sel};
wire [6:0] case_B_ma = {rd_MA, CU_A_sel};
wire [6:0] case_A_wb = {rd_WB, CU_A_sel};
wire [6:0] case_B_wb = {rd_WB, CU_A_sel};


always @(*) begin
    
    if ((opcode_EX == Rtype) | (opcode_EX == Itype) | (opcode_EX == Ltype) | (opcode_EX == Stype) | (opcode_EX == Btype))
    begin
        if ((opcode_MA == Rtype) | (opcode_MA == Itype) | (opcode_MA == LUI) | (opcode_MA == AUIPC) | (opcode_MA == JAL) | (opcode_MA == JALR))
       begin
            case(case_A_ma)
                {rs1, 1'b1} : A_sel = 3'b010;
                default     : A_sel = {2'b00, CU_A_sel};
            endcase
            case(case_B_ma)
                {rs2, 1'b0} : B_sel = 3'b010;
                default     : B_sel = {2'b00, CU_B_sel};
            endcase
        end
        
        else if ((opcode_WB == Rtype) | (opcode_WB == Itype) | (opcode_WB == LUI) | (opcode_WB == AUIPC) | (opcode_WB == JAL) | (opcode_WB == JALR))
        begin
            case(case_A_wb)
                {rs1, 1'b1} : A_sel = 3'b011;
                default: A_sel = {2'b00,CU_A_sel};
            endcase
            case(case_B_wb)
                {rs2, 1'b0} : B_sel = 3'b011;
                default: B_sel = {2'b00,CU_B_sel};
            endcase
        end
        else if (opcode_MA == Ltype) 
        begin
            case(case_A_ma)
                {rs1, 1'b1} : A_sel = 3'b100;
                default     : A_sel = {2'b00, CU_A_sel};
            endcase             
            case(case_B_ma)
                {rs2, 1'b0} : B_sel = 3'b100;
                default     : B_sel = {2'b00, CU_B_sel};
            endcase
        

        end
        else if (opcode_WB == Ltype)
        begin
            case(case_A_wb)
                {rs1, 1'b1} : A_sel = 3'b011;
                default: A_sel = {2'b00,CU_A_sel};
            endcase
            case(case_B_wb)
                {rs2, 1'b0} : B_sel = 3'b011;
                default: B_sel = {2'b00,CU_B_sel};
            endcase
        end
        else 
        begin
            A_sel = {1'b0, 1'b0, CU_A_sel};
            B_sel = {1'b0, 1'b0, CU_B_sel};
        end
    end
    else 
    begin
        A_sel = {1'b0, 1'b0, CU_A_sel};
        B_sel = {1'b0, 1'b0, CU_B_sel};
    end
    
end

endmodule