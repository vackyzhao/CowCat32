`timescale 1ns / 1ps
`define NOP 32'b0000_0000_0000_000000_000_00000_0010011
module ex_module (pc_ex, d1, d2,din, inst_ex, A_sel, B_sel, alu_ctl, clk, rst, pc_br, pc_ma, alu_out, d2_ma, inst_ma, flush, hold,
trim_forward, imm_ex, alu_pc);
                  input [31:0]imm_ex;
                  input [31:0]pc_ex;
                  input [31:0]d1;
                  input [31:0]d2;
                  input [31:0]din;
                  input [31:0]inst_ex;
                  //input [3:0]imm_sel;
                  input [2:0]A_sel;
                  input [2:0]B_sel;
                  input [4:0] alu_ctl;
                  input clk;
                  input rst;
                  input flush;
                  input hold;
                  output [31:0]pc_br;
                  output [31:0]pc_ma;
                  output [31:0]alu_out;
                  output [31:0]d2_ma;
                  output [31:0]inst_ma;
                  input [31:0] trim_forward;
                  output [31:0] alu_pc;

wire[31:0] pc_br_temp, alu_out_temp;
assign alu_pc = alu_out_temp;
//input  [31:0] d1, d2, imm, pc, alu_back, din, trim_forward; alu_mux
/*imm_gen imm_gen(.inst(inst_ex),
                .imm_sel(imm_sel),
               .imm(imm_out));
*/
b_adder b_adder(.pc(pc_ex),
                .imm(imm_ex),
                .pc_br(pc_br_temp));

top_alu top_alu(.pc(pc_ex),
               .d1(d1),
               .d2(d2),
               .imm(imm_ex),
               .alu_forward(alu_out),
               .din(din),
               .A_sel(A_sel),
               .B_sel(B_sel),
               .alu_ctl(alu_ctl),
               .alu_out(alu_out_temp),
               .trim_forward(trim_forward));
assign pc_br = pc_br_temp;
pp_register pc_ma_pp(clk, hold, pc_ma, pc_ex, rst, flush, 32'b0); //module pp_register(clk, hold, q, d, rst, flush, set_data);
pp_register inst_ma_pp(clk, hold, inst_ma, inst_ex, rst, flush, `NOP);
pp_register alu_out_pp(clk, hold, alu_out, alu_out_temp, rst, flush, 32'b0);
pp_register d2_ma_pp(clk, hold, d2_ma, d2, rst, flush, 32'b0);

endmodule
