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
wire [31:0] din, inst_ma, pc_ma, inst_wb, alu_pc;
wire        hold, flush;           // hold: stall pipeline; flush: inject bubble into stage regs
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
wire b_cmp;
wire [2:0] trim_ctl;
wire [1:0] din_sel;
wire [1:0] pc_sel;
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
    .alu_out (alu_pc),
    .pc_sel  (pc_sel),
    .im_inst (im_inst),
    .im_addr (im_addr),
    .pc_id   (pc_id),
    .inst_id (inst_id),
    .flush   (flush),
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
    .flush   (flush),
    .hold    (hold),
    .imm_ex  (imm_ex),
    .imm_sel (imm_sel)
);



//module ex_module (pc_ex, d1, d2,din, inst_ex, A_sel, B_sel, alu_ctl, clk, rst, pc_br, pc_ma, alu_out, d2_ma, inst_ma, flush, hold,
//trim_forward, imm_ex);
// EX: ALU core + branch target add; A_sel/B_sel resolved after forwarding unit
ex_module EX(
    .alu_out      (alu_out),
    .d1           (d1),
    .d2           (d2),
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
    .inst_wb      (inst_wb),
    .inst_ma      (inst_ma),
    .b_cmp        (b_cmp),
    .d2_ma        (d2_ma),
    .dm_store     (dm_store),
    .dm_addr      (dm_addr),
    .op_ma        (op_ma),
    .din_sel      (din_sel),
    .hold         (hold),
    .trim_forward (trim_forward)
);


////module ID_CU(op_id,imm_sel);
ID_CU ID_CU(
    .op_id   (op_id),
    .imm_sel (imm_sel)
);
//module EX_CU(op_ex,A_sel,B_sel,alu_ctl);
// Stage control units
EX_CU EX_CU(
    .op_ex   (op_ex),
    .A_sel   (CU_A_sel),
    .B_sel   (CU_B_sel),
    .alu_ctl (alu_ctl),
    .b_cmp   (b_cmp),
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
//module  CU_flush(pc_sel_in, flush);
// Flush: assert when pc_sel != sequential so IF/ID pipeline regs inject bubble
CU_flush CU_flush(
    .pc_sel (pc_sel),
    .flush  (flush)
);

//clk_signal(.clk(clk));
endmodule
