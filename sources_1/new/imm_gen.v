`timescale 1ns / 1ps

/*
 The format for imm_sel:
 I   x001
 IS  x010 (this is for SLLI, SRLI, and SRA)
 S   x011
 B   x100
 U   x101
 J   x110
 imm_sel[3] is 1 iff the imm is unsigned
 */

`define Itype       3'b001
`define IStype      3'b010
`define Stype       3'b011
`define Btype       3'b100
`define Utype       3'b101
`define Jtype       3'b110

module imm_gen (input [31:0]inst,
                input [3:0]imm_sel,
                output reg[31:0]imm);
always @(*)
begin
    if (imm_sel[2:0] == 3'b000 || imm_sel[2:0] == 3'b111)
        imm = {32{1'b0}};
    else
    begin
        if (imm_sel[2:0] == `Utype)
            imm[31:20] = inst[31:20];
        else if (imm_sel[3])
            imm[31:20] = {12{1'b0}};
        else
            imm[31:20] = {12{inst[31]}};
        
        if (imm_sel[2:0] == `Utype || imm_sel[2:0] == `Jtype)
            imm[19:12] = inst[19:12];
        else if (imm_sel[3])
        begin
            if (imm_sel[2:0] == `Btype)
                imm[19:12] = {{7{1'b0}},inst[31]};
            else
                imm[19:12] = {8{1'b0}};
        end
        else
            imm[19:12] = {8{inst[31]}};
        
        if (imm_sel[2:0] == `Btype)
            imm[11] = inst[7];
        else if (imm_sel[2:0] == `Utype)
            imm[11] = 1'b0;
        else if (imm_sel[2:0] == `Jtype)
            imm[11] = inst[20];
        else
            imm[11] = inst[31];
        
        if (imm_sel[2:0] == `IStype || imm_sel[2:0] == `Utype)
            imm[10:5] = {6{1'b0}};
        else
            imm[10:5] = inst[30:25];
        
        if (imm_sel[2:0] == `Utype)
            imm[4:1] = {4{1'b0}};
        else if (imm_sel[2:0] == `Stype || imm_sel[2:0] == `Btype)
            imm[4:1] = inst[11:8];
        else
            imm[4:1] = inst[24:21];
        
        if (imm_sel[2:0] == `Stype)
            imm[0] = inst[7];
        else if (imm_sel[2:0] == `Itype || imm_sel[2:0] == `IStype)
            imm[0] = inst[20];
        else
            imm[0] = 1'b0;
        
    end
end
endmodule
