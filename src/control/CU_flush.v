`timescale 1ns / 1ps
module  CU_flush(pc_sel, flush);
    input [1:0] pc_sel;
    output flush;
    assign flush = ((pc_sel == 2'b01) | (pc_sel == 2'b10)) ? 1'b0 : 1'b1;
endmodule