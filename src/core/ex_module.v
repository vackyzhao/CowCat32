`timescale 1ns / 1ps
`define NOP 32'b0000_0000_0000_000000_000_00000_0010011
module ex_module (pc_ex, d1, d2,din, inst_ex, inst_valid_ex, A_sel, B_sel, alu_ctl, clk, rst, pc_br, pc_ma, alu_out, d2_ma, inst_ma, inst_valid_ma, flush, hold,
trim_forward, imm_ex, alu_pc);
                  input [31:0]imm_ex;
                  input [31:0]pc_ex;
                  input [31:0]d1;
                  input [31:0]d2;
                  input [31:0]din;
                  input [31:0]inst_ex;
                  input        inst_valid_ex;
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
                  output        inst_valid_ma;
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
// NOTE: On control transfers (branch/jump), we only want to flush the *instruction*
// in the downstream stage, not clobber data/pc pipeline registers that are needed
// for correct writeback (e.g., JAL link address).
pp_register pc_ma_pp(clk, hold, pc_ma, pc_ex, rst, 1'b1, 32'b0); // no data flush

pp_register_inst inst_ma_pp(
    .clk(clk),
    .hold(hold),
    .rst(rst),
    // Do not flush the instruction that generated the control transfer;
    // flushing is only for younger wrong-path instructions.
    .flush(1'b1),
    .d(inst_ex),
    .rst_set_data(`NOP),
    .flush_set_data(`NOP),
    .q(inst_ma)
);

pp_register_bit inst_valid_ma_pp(
    .clk      (clk),
    .rst      (rst),
    .hold     (hold),
    .flush    (1'b1),
    .d        (inst_valid_ex),
    .set_data (1'b0),
    .q        (inst_valid_ma)
);

pp_register alu_out_pp(clk, hold, alu_out, alu_out_temp, rst, 1'b1, 32'b0);
pp_register d2_ma_pp(clk, hold, d2_ma, d2, rst, 1'b1, 32'b0);

`ifdef DEBUG_EX
always @(posedge clk) begin
    if (rst && !hold) begin
        if (inst_ex[6:2] == 5'b01000) begin // STORE
            $display("[%0t] EX STORE: pc=%h rs1=x%0d rs2=x%0d d1=%h d2=%h imm=%h alu_out=%h",
                     $time, pc_ex, inst_ex[19:15], inst_ex[24:20], d1, d2, imm_ex, alu_out_temp);
        end
    end
end
`endif

endmodule
