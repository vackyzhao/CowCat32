`define NOP 32'b0000_0000_0000_000000_000_00000_0010011
module id_module (clk, rst, inst_id, pc_id, inst_valid_id, din, rd, reg_wrt, inst_ex, inst_valid_ex, d1, d2, pc_ex, hold, flush, imm_sel, imm_ex,
                  d1_id, imm_id);
    input               clk;
    input               rst;
    input               hold;
    input               flush;
    input wire[31:0]    inst_id;
    input wire[31:0]    pc_id;
    input               inst_valid_id;
    input wire[31:0]    din;
    input wire[4:0]     rd;
    input               reg_wrt;
    input [3:0]         imm_sel;
    output [31:0] inst_ex;
    output        inst_valid_ex;
    output [31:0] imm_ex;

    // Expose ID-stage values for early jump target compute (JAL/JALR)
    output [31:0] d1_id;
    output [31:0] imm_id;

    wire[4:0] rs1;
    wire[4:0] rs2;
    wire[31:0] d1_temp, d2_temp;
    output [31:0] d1;
    output [31:0] d2;
    output [31:0] pc_ex;

    assign rs1 = inst_id[19:15];
    assign rs2 = inst_id[24:20];
    wire[31:0] imm;
pp_register d1_pp(.rst(rst), .clk(clk),.set_data(32'b0), .hold(hold), .flush(flush), .d(d1_temp), .q(d1));
pp_register d2_pp(.rst(rst), .clk(clk), .set_data(32'b0),.hold(hold), .flush(flush), .d(d2_temp), .q(d2));
// Do not flush PC value into EX on redirects; EX instruction is flushed separately.
pp_register pc_ex_pp(.rst(rst), .clk(clk), .set_data(32'b0), .hold(hold), .flush(1'b1), .d(pc_id), .q(pc_ex));
pp_register_inst inst_ex_pp(
    .clk(clk),
    .hold(hold),
    .rst(rst),
    .flush(flush),
    .d(inst_id),
    .rst_set_data(`NOP),
    .flush_set_data(`NOP),
    .q(inst_ex)
);

pp_register_bit inst_valid_ex_pp(
    .clk      (clk),
    .rst      (rst),
    .hold     (hold),
    .flush    (flush),
    .d        (inst_valid_id),
    .set_data (1'b0),
    .q        (inst_valid_ex)
);

pp_register imm_pp(.rst(rst), .clk(clk), .set_data(32'b0),.hold(hold), .flush(flush), .d(imm), .q(imm_ex));



reg_file registers_file(
    .clk_regs(clk),
    .rst(rst),
    .rs1(rs1),
    .rs2(rs2),
    .din(din),
    .rd(rd),
    .reg_wrt(reg_wrt),
    .d1_temp(d1_temp),
    .d2_temp(d2_temp)
);

assign d1_id  = d1_temp;
assign imm_id = imm;

imm_gen imm_gen(.inst(inst_id),
                .imm_sel(imm_sel),
                .imm(imm));
/*always@(negedge rst or posedge clk)
begin
    if(rst==0)
    begin
        inst_id <= 0;
        pc_id <= 0;
        d1 <= 0;
        d2 <= 0;
    end
    else
    begin
    inst_id <= inst_if;
    pc_id <= pc_if;  
    d1 <= d1_temp;
    d2 <= d2_temp;  
    end   
    
end
*/
    
endmodule