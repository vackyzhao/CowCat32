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

// Only forward from stages that actually write a destination register.
wire reg_wrt_ma = (opcode_MA == Rtype) | (opcode_MA == Itype) | (opcode_MA == Ltype) |
                  (opcode_MA == LUI)   | (opcode_MA == AUIPC) | (opcode_MA == JAL)  | (opcode_MA == JALR);
wire reg_wrt_wb = (opcode_WB == Rtype) | (opcode_WB == Itype) | (opcode_WB == Ltype) |
                  (opcode_WB == LUI)   | (opcode_WB == AUIPC) | (opcode_WB == JAL)  | (opcode_WB == JALR);

// Forwarding policy (priority):
//   1) From MA stage (ALU result or LOAD data)
//   2) From WB stage
// Defaults are CU-selected (pc vs reg / imm vs reg).

always @(*) begin
    // defaults
    A_sel = {2'b00, CU_A_sel};
    B_sel = {2'b00, CU_B_sel};

    if ((opcode_EX == Rtype) | (opcode_EX == Itype) | (opcode_EX == Ltype) | (opcode_EX == Stype) | (opcode_EX == Btype)) begin
        // ---- MA hazard (highest priority) ----
        if (reg_wrt_ma && (rd_MA != 5'b0)) begin
            if (rd_MA == rs1 && CU_A_sel) begin
                if (opcode_MA == Ltype) A_sel = 3'b100;      // load data (trim_forward)
                else                    A_sel = 3'b010;      // alu_forward
            end
            if (rd_MA == rs2 && !CU_B_sel) begin
                if (opcode_MA == Ltype) B_sel = 3'b100;
                else                    B_sel = 3'b010;
            end
        end

        // ---- WB hazard (only if MA didn't already select forwarding) ----
        if (reg_wrt_wb && (rd_WB != 5'b0)) begin
            if (A_sel == {2'b00, CU_A_sel} && (rd_WB == rs1) && CU_A_sel)
                A_sel = 3'b011; // din
            if (B_sel == {2'b00, CU_B_sel} && (rd_WB == rs2) && !CU_B_sel)
                B_sel = 3'b011; // din
        end
    end
end

endmodule