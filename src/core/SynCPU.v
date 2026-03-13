`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/05/2023 03:29:09 PM
// Design Name: 
// Module Name: SynCPU
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


module SynCPU(
    dm_load,
    dm_addr,
    dm_store,
    im_addr,
    im_inst,
    dm_ctl,
    mem_req,
    mem_we,
    mem_re,
    clk,
    rst,
    dm_ack,
    im_ack
);

// CPU IO
// clk/rst : global clock & synchronous reset
// im_*    : instruction memory port (addr out, inst in)
// dm_*    : data memory port (addr/data out, load in, request/write-mask via dm_ctl)
// *_ack   : memory handshake, used to stall the pipeline when low
input               clk, rst, dm_ack, im_ack;
input  wire [31:0]  im_inst, dm_load;
output wire [31:0]  dm_addr, dm_store, im_addr;
output wire [3:0]   dm_ctl;


// 新增：数据访存请求相关信号
output wire         mem_req;
output wire         mem_we;
output wire         mem_re;

// Internal datapath signals
// pc_*    : program counter at each stage
// inst_*  : instruction at each stage
// d1/d2   : register source operands after ID
// din     : data to write back to register file
wire [31:0] alu_out, pc_ex, d2_ma, inst_ex, pc_br, pc_id, d1, d2, inst_id, imm_ex, trim_forward;
wire [31:0] din, inst_ma, pc_ma, inst_wb, pc_wb, alu_pc;
wire [31:0] d1_id, imm_id;
wire        hold, flush_ifid, flush_idex;           // hold: stall pipeline; flush_*: inject bubbles
// WB destination register should come from the WB-stage instruction
wire [4:0]  rd       = inst_wb[11:7];


// Opcode slices for each stage's control unit (funct7[5] + funct3 + opcode[6:2])
wire [8:0] op_id = {inst_id[30], inst_id[14:12], inst_id[6:2]}; 
wire [3:0] imm_sel;
// EX_CU
wire [8:0] op_ex = {inst_ex[30], inst_ex[14:12], inst_ex[6:2]}; 
wire [2:0]A_sel, B_sel;
wire [4:0] alu_ctl;
// MA_CU
wire [8:0] op_ma = {inst_ma[30], inst_ma[14:12], inst_ma[6:2]};
wire b_cmp_ma;
wire b_cmp_ex;
wire [2:0] trim_ctl;
wire [1:0] din_sel;
wire [1:0] pc_sel;

// ---- Early JAL resolve in ID stage (avoid 1-cycle flush lag) ----
wire [4:0] opcode_id_5 = inst_id[6:2];
wire       is_jal_id   = (opcode_id_5 == 5'b11011);
// Only use early JAL redirect during stalls (fixes JAL+hold corner without perturbing normal timing).
// JALR handled later (not enabled in fuzz yet)
wire [1:0] pc_sel_id   = (is_jal_id && hold) ? 2'b10 : 2'b00;
wire [31:0] jal_target_id = pc_id + imm_id;

wire [1:0] pc_sel_final_raw = (pc_sel_id != 2'b00) ? pc_sel_id : pc_sel;
// Mask JALR target LSB to 0 per RISC-V spec.
wire is_jalr_ex = (inst_ex[6:2] == 5'b11001);
wire [31:0] jump_target_ex = is_jalr_ex ? (alu_pc & 32'hFFFF_FFFE) : alu_pc;

wire [31:0] alu_out_for_pc = (pc_sel_id != 2'b00) ? jal_target_id : jump_target_ex;

// If the pipeline is stalled, do not redirect PC or flush stage regs; wait until hold deasserts.
wire [1:0] pc_sel_final = hold ? 2'b00 : pc_sel_final_raw;

// Flush IF/ID when control flow changes; flush ID/EX only when change is resolved in EX (branches).
assign flush_ifid = (hold) ? 1'b1 : (((pc_sel_final == 2'b01) | (pc_sel_final == 2'b10)) ? 1'b0 : 1'b1);
assign flush_idex = (hold) ? 1'b1 : (((pc_sel      == 2'b01) | (pc_sel      == 2'b10)) ? 1'b0 : 1'b1);

// Keep legacy 'flush' signal for debug visibility.
wire flush = flush_ifid;
// WB_CU
wire [8:0] op_wb = {inst_wb[30], inst_wb[14:12], inst_wb[6:2]};
wire reg_wrt;
wire [4:0] inst_5 = inst_ma[6:2];
wire CU_A_sel, CU_B_sel;
//module if_module(clk, rst, pc_br, alu_out, pc_sel, im_inst,im_addr, pc_if, inst_if);
// IF: PC update + instruction fetch, flush kills fetched inst when branch/jump taken
if_module IF(
    .clk     (clk),
    .rst     (rst),
    .pc_br   (pc_br),
    .alu_out (alu_out_for_pc),
    .pc_sel  (pc_sel_final),
    .im_inst (im_inst),
    .im_addr (im_addr),
    .pc_id   (pc_id),
    .inst_id (inst_id),
    .flush   (flush_ifid),
    .hold    (hold)
);



//module id_module (clk, rst, inst_id, pc_id, din, rd, reg_wrt, inst_ex, d1, d2, pc_ex, hold, flush, imm_sel, imm_ex);
// ID: decode, register file read, imm gen; writes back din->rd when reg_wrt=1
id_module ID(
    .clk     (clk),
    .rst     (rst),
    .inst_id (inst_id),
    .pc_id   (pc_id),
    .din     (din),
    .rd      (rd),
    .reg_wrt (reg_wrt),
    .inst_ex (inst_ex),
    .d1      (d1),
    .d2      (d2),
    .pc_ex   (pc_ex),
    .flush   (flush_idex),
    .hold    (hold),
    .imm_ex  (imm_ex),
    .imm_sel (imm_sel),
    .d1_id   (d1_id),
    .imm_id  (imm_id)
);



//module ex_module (pc_ex, d1, d2,din, inst_ex, A_sel, B_sel, alu_ctl, clk, rst, pc_br, pc_ma, alu_out, d2_ma, inst_ma, flush, hold,
//trim_forward, imm_ex);
// Store-data forwarding into EX stage (for hazards like: add -> sw).
wire [4:0] opcode_ex_5 = inst_ex[6:2];
wire [4:0] rs2_ex      = inst_ex[24:20];
wire       is_store_ex = (opcode_ex_5 == 5'b01000);

wire [4:0] opcode_ma_5 = inst_ma[6:2];
wire [4:0] rd_ma_full  = inst_ma[11:7];
wire [4:0] rd_wb_full  = inst_wb[11:7];

wire reg_wrt_ma_full = (opcode_ma_5 == 5'b01100) | (opcode_ma_5 == 5'b00100) | (opcode_ma_5 == 5'b00000) |
                       (opcode_ma_5 == 5'b01101) | (opcode_ma_5 == 5'b00101) | (opcode_ma_5 == 5'b11011) | (opcode_ma_5 == 5'b11001);

wire fwd_store_from_ma = is_store_ex && reg_wrt_ma_full && (rd_ma_full != 5'b0) && (rd_ma_full == rs2_ex);
wire fwd_store_from_wb = is_store_ex && reg_wrt && (rd_wb_full != 5'b0) && (rd_wb_full == rs2_ex);

wire [31:0] store_data_ma = (opcode_ma_5 == 5'b00000) ? trim_forward : alu_out;
wire [31:0] d2_ex_fwd = fwd_store_from_ma ? store_data_ma : (fwd_store_from_wb ? din : d2);

// EX: ALU core + branch target add; A_sel/B_sel resolved after forwarding unit
ex_module EX(
    .alu_out      (alu_out),
    .d1           (d1),
    .d2           (d2_ex_fwd),
    .inst_ex      (inst_ex),
    .A_sel        (A_sel),
    .B_sel        (B_sel),
    .alu_ctl      (alu_ctl),
    .clk          (clk),
    .rst          (rst),
    .pc_br        (pc_br),
    .pc_ma        (pc_ma),
    .pc_ex        (pc_ex),
    .d2_ma        (d2_ma),
    .inst_ma      (inst_ma),
    .flush        (flush),
    .hold         (hold),
    .imm_ex       (imm_ex),
    .din          (din),
    .trim_forward (trim_forward),
    .alu_pc       (alu_pc)
);



//module ma_module(alu_out, pc_ma, dm_load, din_sel, trim_ctl, din, clk, rst, inst_ma, inst_wb, op_ma, b_cmp,d2_ma, dm_store, dm_addr, hold);
// MA: data memory access; trim_extender shapes load data; din_sel picks WB source
ma_module MA(
    .alu_out      (alu_out),
    .pc_ma        (pc_ma),
    .dm_load      (dm_load),
    .trim_ctl     (trim_ctl),
    .din          (din),
    .clk          (clk),
    .rst          (rst),
    .inst_ma      (inst_ma),
    .inst_wb      (inst_wb),
    .pc_wb        (pc_wb),
    .b_cmp        (b_cmp_ma),
    .d2_ma        (d2_ma),
    .dm_store     (dm_store),
    .dm_addr      (dm_addr),
    .op_ma        (op_ma),
    .din_sel      (din_sel),
    .hold         (hold),
    .trim_forward (trim_forward),
    .reg_wrt_wb   (reg_wrt)
);


////module ID_CU(op_id,imm_sel);
ID_CU ID_CU(
    .op_id   (op_id),
    .imm_sel (imm_sel)
);
//module EX_CU(op_ex,A_sel,B_sel,alu_ctl);
// Stage control units
// Branch compare result should come from the current EX-stage ALU output.
assign b_cmp_ex = alu_pc[0];

EX_CU EX_CU(
    .op_ex   (op_ex),
    .A_sel   (CU_A_sel),
    .B_sel   (CU_B_sel),
    .alu_ctl (alu_ctl),
    .b_cmp   (b_cmp_ex),
    .pc_sel  (pc_sel)
); 
//module MA_CU(op_ma,b_cmp,trim_ctl,din_sel,dm_ctl,pc_sel);
MA_CU MA_CU(
    .op_ma    (op_ma),
    .trim_ctl (trim_ctl),
    .din_sel  (din_sel),
    .dm_ctl   (dm_ctl),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_re   (mem_re)
); 
 //module WB_CU(op_wb,reg_wrt);
WB_CU WB_CU(
    .op_wb   (op_wb),
    .reg_wrt (reg_wrt)
);
//module hold_CU(dm_ack, im_ack, hold, clk, inst_5);
hold_CU HOLD_CU(
    .dm_ack (dm_ack),
    .im_ack (im_ack),
    .hold   (hold),
    .inst_5 (inst_5)
);
//module CU_forwarding(CU_A_sel, CU_B_sel, inst_EX, inst_MA, inst_WB, A_sel, B_sel, hold);
// Forwarding: resolves data hazards by selecting MA/WB results for EX operands
CU_forwarding CU_forwarding(
    .CU_A_sel (CU_A_sel),
    .CU_B_sel (CU_B_sel),
    .inst_EX  ({inst_ex[24:20], inst_ex[19:15], inst_ex[6:2]}),
    .inst_MA  ({inst_ma[11:7], inst_ma[6:2]}),
    .A_sel    (A_sel),
    .B_sel    (B_sel),
    .inst_WB  ({inst_wb[11:7], inst_wb[6:2]})
);
// Flush signals are computed in SynCPU (flush_ifid, flush_idex).

`ifdef TRACE_CTRL
always @(posedge clk) begin
    if (rst) begin
        $display("[ctrl] pc_id=%h inst_id=%h | pc_ex=%h inst_ex=%h A_sel=%b B_sel=%b d1=%h d2=%h imm_ex=%h alu_pc=%h | pc_sel=%b hold=%b flush_ifid=%b flush_idex=%b",
                 pc_id, inst_id, pc_ex, inst_ex, A_sel, B_sel, d1, d2, imm_ex, alu_pc, pc_sel_final, hold, flush_ifid, flush_idex);
    end
end
`endif

`ifdef TRACE_EXSEQ
always @(posedge clk) begin
    if (rst && !hold) begin
        if (inst_ex != 32'h00000013) begin
            $display("[ex] pc=%h inst=%h", pc_ex, inst_ex);
        end
    end
end
`endif

`ifdef TRACE_WB
always @(posedge clk) begin
    if (rst) begin
        if (reg_wrt && (rd != 5'b0) && !hold) begin
            $display("[wb] pc_wb=%h inst_wb=%h rd=%0d din=%h", pc_wb, inst_wb, rd, din);
        end
        if ((inst_ma[6:2] == 5'b11001) && !hold) begin // JALR in MA for visibility
            $display("[ma] pc_ma=%h inst_ma=%h", pc_ma, inst_ma);
        end
    end
end
`endif

//clk_signal(.clk(clk));
endmodule
