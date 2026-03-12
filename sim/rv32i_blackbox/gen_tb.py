#!/usr/bin/env python3
# Generate a self-contained Icarus-Verilog testbench that feeds RV32I machine code
# directly (no toolchain needed) and checks architectural state via hierarchical
# references into the DUT (black-box at the interface level).
#
# Focus: catch common pipeline/forwarding/memory handshake bugs.

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Tuple, Dict

XLEN = 32

# -------------------------
# RV32I encoders (subset)
# -------------------------

def mask(n, bits=32):
    return n & ((1 << bits) - 1)

def sign_extend(n, bits):
    m = 1 << (bits - 1)
    return mask((n & ((1 << bits) - 1)) ^ m) - m


def enc_i(imm, rs1, funct3, rd, opcode):
    return mask(((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode)

def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return mask((funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode)

def enc_s(imm, rs2, rs1, funct3, opcode):
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0  = imm & 0x1F
    return mask((imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode)

def enc_b(imm, rs2, rs1, funct3, opcode):
    # imm is signed, multiple of 2
    imm &= 0x1FFF
    b12   = (imm >> 12) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1  = (imm >> 1) & 0xF
    b11   = (imm >> 11) & 1
    return mask((b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode)

def enc_u(imm, rd, opcode):
    return mask((imm & 0xFFFFF000) | (rd << 7) | opcode)

def enc_j(imm, rd, opcode):
    # imm is signed, multiple of 2
    imm &= 0x1FFFFF
    b20    = (imm >> 20) & 1
    b10_1  = (imm >> 1) & 0x3FF
    b11    = (imm >> 11) & 1
    b19_12 = (imm >> 12) & 0xFF
    return mask((b20 << 31) | (b19_12 << 12) | (b11 << 20) | (b10_1 << 21) | (rd << 7) | opcode)

# Opcodes
OP_IMM = 0x13
OP     = 0x33
LOAD   = 0x03
STORE  = 0x23
BRANCH = 0x63
LUI    = 0x37
AUIPC  = 0x17
JAL    = 0x6F
JALR   = 0x67

# funct3
F3_ADD_SUB = 0b000
F3_SLL     = 0b001
F3_SLT     = 0b010
F3_SLTU    = 0b011
F3_XOR     = 0b100
F3_SRL_SRA = 0b101
F3_OR      = 0b110
F3_AND     = 0b111

F3_BEQ = 0b000
F3_BNE = 0b001
F3_BLT = 0b100
F3_BGE = 0b101

F3_LW  = 0b010
F3_SW  = 0b010


# -------------------------
# Minimal reference model
# -------------------------

@dataclass
class CPUState:
    pc: int = 0
    x: List[int] = None
    mem: Dict[int, int] = None  # word-addressed memory

    def __post_init__(self):
        if self.x is None:
            self.x = [0] * 32
        if self.mem is None:
            self.mem = {}


def step_rv32i(st: CPUState, inst: int):
    pc0 = st.pc
    opcode = inst & 0x7F
    rd = (inst >> 7) & 0x1F
    funct3 = (inst >> 12) & 0x7
    rs1 = (inst >> 15) & 0x1F
    rs2 = (inst >> 20) & 0x1F
    funct7 = (inst >> 25) & 0x7F

    def wreg(r, v):
        if r != 0:
            st.x[r] = mask(v)

    def load_w(addr):
        if addr % 4 != 0:
            raise ValueError(f"misaligned lw addr {addr:#x}")
        return st.mem.get(addr, 0)

    def store_w(addr, val):
        if addr % 4 != 0:
            raise ValueError(f"misaligned sw addr {addr:#x}")
        st.mem[addr] = mask(val)

    st.pc = mask(st.pc + 4)

    if opcode == OP_IMM:
        imm = sign_extend(inst >> 20, 12)
        a = st.x[rs1]
        if funct3 == F3_ADD_SUB:  # addi
            wreg(rd, a + imm)
        elif funct3 == F3_AND:
            wreg(rd, a & imm)
        elif funct3 == F3_OR:
            wreg(rd, a | imm)
        elif funct3 == F3_XOR:
            wreg(rd, a ^ imm)
        else:
            raise NotImplementedError(f"OP-IMM funct3 {funct3}")

    elif opcode == OP:
        a = st.x[rs1]
        b = st.x[rs2]
        if funct3 == F3_ADD_SUB:
            if funct7 == 0x20:
                wreg(rd, a - b)
            else:
                wreg(rd, a + b)
        elif funct3 == F3_AND:
            wreg(rd, a & b)
        elif funct3 == F3_OR:
            wreg(rd, a | b)
        elif funct3 == F3_XOR:
            wreg(rd, a ^ b)
        else:
            raise NotImplementedError(f"OP funct3 {funct3}")

    elif opcode == LUI:
        imm = inst & 0xFFFFF000
        wreg(rd, imm)

    elif opcode == AUIPC:
        imm = inst & 0xFFFFF000
        wreg(rd, pc0 + imm)

    elif opcode == LOAD:
        imm = sign_extend(inst >> 20, 12)
        addr = mask(st.x[rs1] + imm)
        if funct3 == F3_LW:
            wreg(rd, load_w(addr))
        else:
            raise NotImplementedError("only lw")

    elif opcode == STORE:
        imm = ((inst >> 25) << 5) | ((inst >> 7) & 0x1F)
        imm = sign_extend(imm, 12)
        addr = mask(st.x[rs1] + imm)
        if funct3 == F3_SW:
            store_w(addr, st.x[rs2])
        else:
            raise NotImplementedError("only sw")

    elif opcode == BRANCH:
        imm = ((inst >> 31) << 12) | (((inst >> 7) & 1) << 11) | (((inst >> 25) & 0x3F) << 5) | (((inst >> 8) & 0xF) << 1)
        imm = sign_extend(imm, 13)
        a = st.x[rs1]
        b = st.x[rs2]
        take = False
        if funct3 == F3_BEQ:
            take = (a == b)
        elif funct3 == F3_BNE:
            take = (a != b)
        elif funct3 == F3_BLT:
            take = (sign_extend(a, 32) < sign_extend(b, 32))
        elif funct3 == F3_BGE:
            take = (sign_extend(a, 32) >= sign_extend(b, 32))
        else:
            raise NotImplementedError("branch")
        if take:
            st.pc = mask(pc0 + imm)

    elif opcode == JAL:
        imm = ((inst >> 31) << 20) | (((inst >> 12) & 0xFF) << 12) | (((inst >> 20) & 1) << 11) | (((inst >> 21) & 0x3FF) << 1)
        imm = sign_extend(imm, 21)
        wreg(rd, pc0 + 4)
        st.pc = mask(pc0 + imm)

    elif opcode == JALR:
        imm = sign_extend(inst >> 20, 12)
        t = mask(st.x[rs1] + imm) & ~1
        wreg(rd, pc0 + 4)
        st.pc = t

    else:
        raise NotImplementedError(f"opcode {opcode:#x}")

    st.x[0] = 0


# -------------------------
# Test program generator
# -------------------------

@dataclass
class TestProgram:
    name: str
    insts: List[int]
    max_cycles: int


def build_smoke_program() -> TestProgram:
    # A short program designed to stress WB->ID hazards and store address/data
    insts = []
    # x1=5; x2=x1+3=8; x3=x2+4=12; x4=x3+1=13; x5=256
    insts.append(enc_i(5, 0, F3_ADD_SUB, 1, OP_IMM))
    insts.append(enc_i(3, 1, F3_ADD_SUB, 2, OP_IMM))
    insts.append(enc_i(4, 2, F3_ADD_SUB, 3, OP_IMM))
    insts.append(enc_i(1, 3, F3_ADD_SUB, 4, OP_IMM))
    insts.append(enc_i(256, 0, F3_ADD_SUB, 5, OP_IMM))
    # two nops (addi x0,x0,0)
    insts.append(enc_i(0, 0, F3_ADD_SUB, 0, OP_IMM))
    insts.append(enc_i(0, 0, F3_ADD_SUB, 0, OP_IMM))
    # sw x4, 0(x5)
    insts.append(enc_s(0, 4, 5, F3_SW, STORE))
    # a few nops
    for _ in range(6):
        insts.append(enc_i(0, 0, F3_ADD_SUB, 0, OP_IMM))
    return TestProgram("smoke_store", insts, max_cycles=600)


def build_branch_program() -> TestProgram:
    insts = []
    # x1=1; x2=1; if beq taken skip addi x3=99
    insts.append(enc_i(1, 0, F3_ADD_SUB, 1, OP_IMM))
    insts.append(enc_i(1, 0, F3_ADD_SUB, 2, OP_IMM))
    insts.append(enc_b(8, 2, 1, F3_BEQ, BRANCH))  # +8 bytes => skip next inst
    insts.append(enc_i(99, 0, F3_ADD_SUB, 3, OP_IMM))
    insts.append(enc_i(7, 0, F3_ADD_SUB, 3, OP_IMM))
    for _ in range(8):
        insts.append(enc_i(0, 0, F3_ADD_SUB, 0, OP_IMM))
    return TestProgram("branch_beq", insts, max_cycles=600)


def run_ref(tp: TestProgram) -> CPUState:
    st = CPUState(pc=0)
    # execute as many instructions as provided (ignore max_cycles)
    pc_to_inst = {i * 4: inst for i, inst in enumerate(tp.insts)}
    executed = 0
    while st.pc in pc_to_inst and executed < 2000:
        inst = pc_to_inst[st.pc]
        step_rv32i(st, inst)
        executed += 1
    return st


def gen_verilog(tp: TestProgram, ref: CPUState) -> str:
    # Build a TB that drives im_inst from im_addr and uses the existing dm_* handshake.
    # It checks memory word at 0x100 for smoke_store, and checks reg x3 for branch.

    rom_cases = []
    for i, inst in enumerate(tp.insts):
        rom_cases.append(f"        32'h{(i*4):08x}: im_inst = 32'h{inst:08x};")
    rom_cases.append("        default: im_inst = 32'h00000013; // nop")

    # expected checks
    checks = []
    if tp.name == "smoke_store":
        exp = ref.mem.get(0x100, 0)
        checks.append(f"        if (data_mem[32'h00000100 >> 2] !== 32'h{exp:08x}) begin")
        checks.append(f"            $display(\"FAIL: mem[0x100] exp={exp:08x} got=%h\", data_mem[32'h00000100 >> 2]);")
        checks.append("            $fatal(1);")
        checks.append("        end")
    if tp.name == "branch_beq":
        exp = ref.x[3]
        # hierarchical peek of regfile
        checks.append(f"        if (uut.ID.registers_file.regs[3] !== 32'h{exp:08x}) begin")
        checks.append(f"            $display(\"FAIL: x3 exp={exp:08x} got=%h\", uut.ID.registers_file.regs[3]);")
        checks.append("            $fatal(1);")
        checks.append("        end")

    checks_str = "\n".join(checks) if checks else "        // (no checks)"

    return f"""`timescale 1ns/1ps

module rv32i_blackbox_tb;
    reg clk;
    reg rst;
    reg dm_ack;
    reg im_ack;
    reg [31:0] im_inst;
    reg [31:0] dm_load;

    wire [31:0] dm_addr;
    wire [31:0] dm_store;
    wire [31:0] im_addr;
    wire [3:0]  dm_ctl;
    wire        mem_req;
    wire        mem_we;
    wire        mem_re;

    SynCPU uut (
        .dm_load (dm_load),
        .dm_addr (dm_addr),
        .dm_store(dm_store),
        .im_addr (im_addr),
        .im_inst (im_inst),
        .dm_ctl  (dm_ctl),
        .mem_req (mem_req),
        .mem_we  (mem_we),
        .mem_re  (mem_re),
        .clk     (clk),
        .rst     (rst),
        .dm_ack  (dm_ack),
        .im_ack  (im_ack)
    );

    // clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // instruction memory always ready
    initial begin
        im_ack = 1'b1;
    end

    // instruction ROM (combinational)
    always @(*) begin
        case (im_addr)
{chr(10).join(rom_cases)}
        endcase
    end

    // simple data memory model (word addressed)
    reg [31:0] data_mem [0:255];
    integer i;
    initial begin
        for (i=0;i<256;i=i+1) data_mem[i] = 32'h0;
    end

    localparam integer LATENCY = 3;
    reg dmem_busy;
    reg [3:0] dmem_cnt;
    reg pend_we;
    reg pend_re;
    reg [31:0] pend_addr;
    reg [31:0] pend_wdata;

    wire data_req = mem_req && (mem_we || mem_re);

    initial begin
        dm_ack    = 1'b0;
        dm_load   = 32'h0;
        dmem_busy = 1'b0;
        dmem_cnt  = 0;
        pend_we   = 1'b0;
        pend_re   = 1'b0;
        pend_addr = 32'h0;
        pend_wdata= 32'h0;
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            dm_ack    <= 1'b0;
            dm_load   <= 32'h0;
            dmem_busy <= 1'b0;
            dmem_cnt  <= 0;
        end else begin
            dm_ack <= 1'b0;
            if (!dmem_busy) begin
                if (data_req) begin
                    dmem_busy  <= 1'b1;
                    dmem_cnt   <= LATENCY;
                    pend_we    <= mem_we;
                    pend_re    <= mem_re;
                    pend_addr  <= dm_addr;
                    pend_wdata <= dm_store;
                end
            end else begin
                if (dmem_cnt != 0) begin
                    dmem_cnt <= dmem_cnt - 1;
                end else begin
                    dm_ack <= 1'b1;
                    if (pend_we) begin
                        data_mem[pend_addr[9:2]] <= pend_wdata;
                    end
                    if (pend_re) begin
                        dm_load <= data_mem[pend_addr[9:2]];
                    end
                    dmem_busy <= 1'b0;
                end
            end
        end
    end

    // reset + timeout + checks
    initial begin
        rst = 1'b0;
        #20; rst = 1'b1;

        // run
        #( {tp.max_cycles} * 10 );

        // checks
{checks_str}

        $display("PASS: {tp.name}");
        $finish;
    end
endmodule
"""


def main():
    programs = [build_smoke_program(), build_branch_program()]
    for tp in programs:
        ref = run_ref(tp)
        tb = gen_verilog(tp, ref)
        out = f"/home/zcq/CowCat32/sim/rv32i_blackbox/{tp.name}_tb.v"
        with open(out, "w", encoding="utf-8") as f:
            f.write(tb)
        print("wrote", out)


if __name__ == "__main__":
    main()
