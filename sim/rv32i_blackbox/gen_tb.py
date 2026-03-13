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

F3_ADDI = 0b000
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
        elif funct3 == F3_SLL:
            shamt = (inst >> 20) & 0x1F
            wreg(rd, a << shamt)
        elif funct3 == F3_SRL_SRA:
            shamt = (inst >> 20) & 0x1F
            if (inst >> 30) & 1:
                # srai
                sa = sign_extend(a, 32)
                wreg(rd, sa >> shamt)
            else:
                # srli
                wreg(rd, (a & 0xFFFF_FFFF) >> shamt)
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
        elif funct3 == F3_SLL:
            shamt = b & 0x1F
            wreg(rd, a << shamt)
        elif funct3 == F3_SRL_SRA:
            shamt = b & 0x1F
            if funct7 == 0x20:
                sa = sign_extend(a, 32)
                wreg(rd, sa >> shamt)
            else:
                wreg(rd, (a & 0xFFFF_FFFF) >> shamt)
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


def nop():
    return enc_i(0, 0, F3_ADD_SUB, 0, OP_IMM)


def build_smoke_program() -> TestProgram:
    """Basic store smoke + WB->ID hazard."""
    insts = []
    # x1=5; x2=x1+3=8; x3=x2+4=12; x4=x3+1=13; x5=256
    insts += [
        enc_i(5, 0, F3_ADD_SUB, 1, OP_IMM),
        enc_i(3, 1, F3_ADD_SUB, 2, OP_IMM),
        enc_i(4, 2, F3_ADD_SUB, 3, OP_IMM),
        enc_i(1, 3, F3_ADD_SUB, 4, OP_IMM),
        enc_i(256, 0, F3_ADD_SUB, 5, OP_IMM),
        nop(),
        nop(),
        enc_s(0, 4, 5, F3_SW, STORE),
    ]
    insts += [nop()] * 8
    return TestProgram("smoke_store", insts, max_cycles=800)


def build_branch_program() -> TestProgram:
    """BEQ taken path + flush."""
    insts = []
    insts += [
        enc_i(1, 0, F3_ADD_SUB, 1, OP_IMM),
        enc_i(1, 0, F3_ADD_SUB, 2, OP_IMM),
        enc_b(8, 2, 1, F3_BEQ, BRANCH),  # +8 bytes => skip next inst
        enc_i(99, 0, F3_ADD_SUB, 3, OP_IMM),
        enc_i(7, 0, F3_ADD_SUB, 3, OP_IMM),
    ]
    insts += [nop()] * 10
    return TestProgram("branch_beq", insts, max_cycles=800)


def build_branch_dep_program() -> TestProgram:
    """Branch depends on result from immediately previous instruction (forwarding to branch compare)."""
    insts = []
    # x1=5; x2=5
    insts.append(enc_i(5, 0, F3_ADD_SUB, 1, OP_IMM))
    insts.append(enc_i(5, 0, F3_ADD_SUB, 2, OP_IMM))
    # x3 = x1 ^ x2 = 0 (produced right before branch)
    insts.append(enc_r(0x00, 2, 1, F3_XOR, 3, OP))
    # beq x3, x0, +8  (should be taken)
    insts.append(enc_b(8, 0, 3, F3_BEQ, BRANCH))
    # wrong-path: x4=111
    insts.append(enc_i(111, 0, F3_ADD_SUB, 4, OP_IMM))
    # target: x4=7
    insts.append(enc_i(7, 0, F3_ADD_SUB, 4, OP_IMM))
    insts += [nop()] * 20
    return TestProgram("branch_dep", insts, max_cycles=1500)


def build_store_data_fwd_program() -> TestProgram:
    """Store data comes from previous ALU result (forwarding into store data path)."""
    insts = []
    insts.append(enc_i(256, 0, F3_ADD_SUB, 5, OP_IMM))       # x5=0x100
    insts.append(enc_i(0x10, 0, F3_ADD_SUB, 1, OP_IMM))      # x1=0x10
    insts.append(enc_i(0x22, 0, F3_ADD_SUB, 2, OP_IMM))      # x2=0x22
    insts.append(enc_r(0x00, 2, 1, F3_XOR, 3, OP))           # x3=x1^x2=0x32
    insts.append(enc_s(0, 3, 5, F3_SW, STORE))               # sw x3,0(x5)
    insts.append(enc_i(0, 5, F3_LW, 4, LOAD))                # lw x4,0(x5)
    insts += [nop()] * 40
    return TestProgram("store_data_fwd", insts, max_cycles=2500)


def build_store_base_fwd_program() -> TestProgram:
    """Store base (rs1) depends on previous result."""
    insts = []
    insts.append(enc_i(0x80, 0, F3_ADD_SUB, 1, OP_IMM))      # x1=0x80
    insts.append(enc_i(0x80, 1, F3_ADD_SUB, 5, OP_IMM))      # x5=x1+0x80=0x100 (depends)
    insts.append(enc_i(0x2A, 0, F3_ADD_SUB, 2, OP_IMM))      # x2=0x2a
    insts.append(enc_s(0, 2, 5, F3_SW, STORE))               # sw x2,0(x5)
    insts.append(enc_i(0, 5, F3_LW, 3, LOAD))                # lw x3,0(x5)
    insts += [nop()] * 50
    return TestProgram("store_base_fwd", insts, max_cycles=3000)


def build_branch_not_taken_dep_program() -> TestProgram:
    """Branch not taken, dependent compare (ensures no accidental flush)."""
    insts = []
    insts.append(enc_i(1, 0, F3_ADD_SUB, 1, OP_IMM))         # x1=1
    insts.append(enc_i(2, 0, F3_ADD_SUB, 2, OP_IMM))         # x2=2
    insts.append(enc_r(0x00, 2, 1, F3_XOR, 3, OP))           # x3=1^2=3
    insts.append(enc_b(8, 0, 3, F3_BEQ, BRANCH))             # beq x3,x0 (not taken)
    insts.append(enc_i(7, 0, F3_ADD_SUB, 4, OP_IMM))         # should execute
    insts += [nop()] * 30
    return TestProgram("branch_not_taken_dep", insts, max_cycles=2000)


def build_flush_wrongpath_wb_program() -> TestProgram:
    """JAL should flush wrong-path instruction so it must not write back."""
    insts = []
    insts.append(enc_i(0, 0, F3_ADD_SUB, 1, OP_IMM))         # x1=0
    insts.append(enc_j(8, 10, JAL))                          # jump over next
    insts.append(enc_i(99, 0, F3_ADD_SUB, 1, OP_IMM))        # wrong-path write (must be flushed)
    insts.append(enc_i(7, 0, F3_ADD_SUB, 1, OP_IMM))         # correct-path
    insts += [nop()] * 40
    return TestProgram("flush_wrongpath_wb", insts, max_cycles=2000)


def build_double_branch_program() -> TestProgram:
    """Two back-to-back branches with dependencies (flush/pc update stress)."""
    insts = []
    # x1=0; x2=0
    insts.append(enc_i(0, 0, F3_ADD_SUB, 1, OP_IMM))
    insts.append(enc_i(0, 0, F3_ADD_SUB, 2, OP_IMM))
    # beq x1,x2, +8 (taken)
    insts.append(enc_b(8, 2, 1, F3_BEQ, BRANCH))
    # wrong-path: x3=111
    insts.append(enc_i(111, 0, F3_ADD_SUB, 3, OP_IMM))
    # target: set x1=1
    insts.append(enc_i(1, 0, F3_ADD_SUB, 1, OP_IMM))
    # second branch depends on updated x1
    insts.append(enc_b(8, 0, 1, F3_BNE, BRANCH))  # bne x1,x0 => taken
    insts.append(enc_i(222, 0, F3_ADD_SUB, 4, OP_IMM))        # wrong-path
    insts.append(enc_i(7, 0, F3_ADD_SUB, 4, OP_IMM))          # target
    insts += [nop()] * 60
    return TestProgram("double_branch", insts, max_cycles=3000)


def build_mem_back_to_back_program() -> TestProgram:
    """Back-to-back memory ops with random stall (request/hold robustness)."""
    insts = []
    insts.append(enc_i(256, 0, F3_ADD_SUB, 5, OP_IMM))        # x5=0x100
    insts.append(enc_i(1, 0, F3_ADD_SUB, 1, OP_IMM))          # x1=1
    insts.append(enc_i(2, 0, F3_ADD_SUB, 2, OP_IMM))          # x2=2
    insts.append(enc_i(3, 0, F3_ADD_SUB, 3, OP_IMM))          # x3=3
    # 3 stores back-to-back
    insts.append(enc_s(0, 1, 5, F3_SW, STORE))
    insts.append(enc_s(4, 2, 5, F3_SW, STORE))
    insts.append(enc_s(8, 3, 5, F3_SW, STORE))
    # 3 loads back-to-back
    insts.append(enc_i(0, 5, F3_LW, 6, LOAD))
    insts.append(enc_i(4, 5, F3_LW, 7, LOAD))
    insts.append(enc_i(8, 5, F3_LW, 8, LOAD))
    insts += [nop()] * 100
    return TestProgram("mem_back_to_back", insts, max_cycles=5000)


def build_structural_hazard_program() -> TestProgram:
    """Mix of mem + branch + alu to stress simultaneous hazards."""
    insts = []
    insts.append(enc_i(256, 0, F3_ADD_SUB, 5, OP_IMM))        # base
    insts.append(enc_i(5, 0, F3_ADD_SUB, 1, OP_IMM))
    insts.append(enc_s(0, 1, 5, F3_SW, STORE))
    insts.append(enc_i(0, 5, F3_LW, 2, LOAD))                 # x2=5
    insts.append(enc_i(1, 2, F3_ADD_SUB, 3, OP_IMM))          # x3=6 (load-use)
    insts.append(enc_b(8, 3, 1, F3_BNE, BRANCH))              # bne x3,x1 (taken)
    insts.append(enc_i(111, 0, F3_ADD_SUB, 4, OP_IMM))        # wrong-path
    insts.append(enc_i(7, 0, F3_ADD_SUB, 4, OP_IMM))          # target
    insts += [nop()] * 100
    return TestProgram("structural_hazard", insts, max_cycles=6000)


def build_load_store_program() -> TestProgram:
    """Load followed immediately by store of loaded value (load->store hazard)."""
    insts = []
    insts.append(enc_i(256, 0, F3_ADD_SUB, 5, OP_IMM))       # x5=0x100
    insts.append(enc_i(0x2A, 0, F3_ADD_SUB, 1, OP_IMM))      # x1=0x2a
    insts += [nop()] * 4
    insts.append(enc_s(0, 1, 5, F3_SW, STORE))               # sw x1,0(x5)
    insts += [nop()] * 4
    insts.append(enc_i(0, 5, F3_LW, 2, LOAD))                # lw x2,0(x5)
    insts.append(enc_s(4, 2, 5, F3_SW, STORE))               # sw x2,4(x5) (immediate)
    insts.append(enc_i(4, 5, F3_LW, 3, LOAD))                # lw x3,4(x5)
    insts += [nop()] * 60
    return TestProgram("load_store", insts, max_cycles=3000)


def build_jalr_dep_program() -> TestProgram:
    """JALR target base depends on previous instruction (forwarding into JALR target)."""
    insts = []
    # x1 = 0x1c (target)
    insts.append(enc_i(0x1C, 0, F3_ADD_SUB, 1, OP_IMM))
    # x2 = x1 + 4 = 0x20
    insts.append(enc_i(4, 1, F3_ADD_SUB, 2, OP_IMM))
    # jalr x10, 0(x2) -> jump to 0x20
    insts.append(enc_i(0, 2, 0b000, 10, JALR))
    # wrong-path
    insts.append(enc_i(0x55, 0, F3_ADD_SUB, 3, OP_IMM))
    insts.append(enc_i(0x66, 0, F3_ADD_SUB, 3, OP_IMM))
    # 0x14 filler
    insts.append(nop())
    insts.append(nop())
    # 0x20 target: x3=9
    insts.append(enc_i(9, 0, F3_ADD_SUB, 3, OP_IMM))
    insts += [nop()] * 60
    return TestProgram("jalr_dep", insts, max_cycles=3000)


def build_load_use_program() -> TestProgram:
    """Load-use hazard: lw -> dependent addi immediately."""
    insts = []
    # Initialize base and memory.
    insts.append(enc_i(256, 0, F3_ADD_SUB, 5, OP_IMM))       # x5 = 0x100
    insts.append(enc_i(0x2A, 0, F3_ADD_SUB, 1, OP_IMM))      # x1 = 0x2a
    # Avoid store-data/store-base hazards here: insert bubbles so this test isolates
    # load-use + memory stall behavior rather than store forwarding.
    insts += [nop()] * 4
    insts.append(enc_s(0, 1, 5, F3_SW, STORE))               # sw x1, 0(x5)
    insts += [nop()] * 4

    # lw then immediate use
    insts.append(enc_i(0, 5, F3_LW, 2, LOAD))                # x2 = mem[0x100]
    insts.append(enc_i(1, 2, F3_ADD_SUB, 3, OP_IMM))         # x3 = x2 + 1 (hazard)
    insts += [nop()] * 30
    return TestProgram("load_use", insts, max_cycles=2000)


def build_jal_jalr_program() -> TestProgram:
    """JAL/JALR basic correctness, with a finite control-flow (no infinite loop)."""
    insts = []
    # 0x00: x1 = 0
    insts.append(enc_i(0, 0, F3_ADD_SUB, 1, OP_IMM))
    # 0x04: jal x10, +12  (to 0x10)
    insts.append(enc_j(12, 10, JAL))
    # 0x08: should be flushed/skip
    insts.append(enc_i(123, 0, F3_ADD_SUB, 1, OP_IMM))
    # 0x0c: should be skipped too
    insts.append(enc_i(124, 0, F3_ADD_SUB, 1, OP_IMM))
    # 0x10: x1 = 7
    insts.append(enc_i(7, 0, F3_ADD_SUB, 1, OP_IMM))
    # 0x14: x5 = 0x20 (return target)
    insts.append(enc_i(0x20, 0, F3_ADD_SUB, 5, OP_IMM))
    # 0x18: jalr x11, 0(x5) -> jump to 0x20; x11 gets 0x1c
    insts.append(enc_i(0, 5, 0b000, 11, JALR))
    # 0x1c: filler (should not execute if jalr works)
    insts.append(enc_i(200, 0, F3_ADD_SUB, 2, OP_IMM))
    # 0x20: x2 = 9
    insts.append(enc_i(9, 0, F3_ADD_SUB, 2, OP_IMM))
    insts += [nop()] * 40
    return TestProgram("jal_jalr", insts, max_cycles=2000)


def build_alu_program() -> TestProgram:
    """ALU dependency chain to stress forwarding (no NOPs)."""
    insts = []
    insts.append(enc_i(0x55, 0, F3_ADD_SUB, 1, OP_IMM))       # x1=0x55
    insts.append(enc_i(0x0F, 0, F3_ADD_SUB, 2, OP_IMM))       # x2=0x0f
    insts.append(enc_r(0x00, 2, 1, F3_XOR, 3, OP))            # x3=x1^x2
    insts.append(enc_r(0x00, 2, 3, F3_OR,  4, OP))            # x4=x3|x2
    insts.append(enc_r(0x00, 1, 4, F3_AND, 5, OP))            # x5=x4&x1
    # shifts
    insts.append(enc_i(1, 5, F3_SLL, 6, OP_IMM))              # x6 = x5 << 1 (slli)
    insts.append(enc_i((0x20<<5)|1, 6, F3_SRL_SRA, 7, OP_IMM))# x7 = x6 >>> 1 (srai shamt=1)
    insts.append(enc_r(0x00, 2, 7, F3_SRL_SRA, 8, OP))        # x8 = x7 >> (x2&31) (srl)
    insts += [nop()] * 60
    return TestProgram("alu_basic", insts, max_cycles=3500)


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
    # Checks are per-program (memory and/or registers) using hierarchical peek into uut.

    rom_cases = []
    for i, inst in enumerate(tp.insts):
        rom_cases.append(f"        32'h{(i*4):08x}: im_inst = 32'h{inst:08x};")
    rom_cases.append("        default: im_inst = 32'h00000013; // nop")

    # expected checks
    checks = []

    def check_reg(reg_idx: int):
        exp = ref.x[reg_idx]
        checks.append(f"        if (uut.ID.registers_file.regs[{reg_idx}] !== 32'h{exp:08x}) begin")
        checks.append(f"            $display(\"FAIL: x{reg_idx} exp={exp:08x} got=%h\", uut.ID.registers_file.regs[{reg_idx}]);")
        checks.append("            $fatal(1);")
        checks.append("        end")

    def check_mem_word(addr: int):
        exp = ref.mem.get(addr, 0)
        checks.append(f"        if (data_mem[32'h{addr:08x} >> 2] !== 32'h{exp:08x}) begin")
        checks.append(f"            $display(\"FAIL: mem[0x{addr:x}] exp={exp:08x} got=%h\", data_mem[32'h{addr:08x} >> 2]);")
        checks.append("            $fatal(1);")
        checks.append("        end")

    if tp.name == "smoke_store":
        check_mem_word(0x100)

    elif tp.name == "branch_beq":
        check_reg(3)

    elif tp.name == "load_use":
        check_mem_word(0x100)
        check_reg(2)
        check_reg(3)

    elif tp.name == "alu_basic":
        check_reg(3)
        check_reg(4)
        check_reg(5)
        check_reg(6)
        check_reg(7)
        check_reg(8)

    elif tp.name == "jal_jalr":
        check_reg(1)
        check_reg(2)
        check_reg(10)
        check_reg(11)

    elif tp.name == "branch_dep":
        check_reg(4)

    elif tp.name == "store_data_fwd":
        check_mem_word(0x100)
        check_reg(4)

    elif tp.name == "load_store":
        check_mem_word(0x100)
        check_mem_word(0x104)
        check_reg(3)

    elif tp.name == "jalr_dep":
        check_reg(3)
        check_reg(10)

    elif tp.name == "store_base_fwd":
        check_mem_word(0x100)
        check_reg(3)

    elif tp.name == "branch_not_taken_dep":
        check_reg(4)

    elif tp.name == "flush_wrongpath_wb":
        check_reg(1)
        check_reg(10)

    elif tp.name == "double_branch":
        check_reg(4)

    elif tp.name == "mem_back_to_back":
        check_mem_word(0x100)
        check_mem_word(0x104)
        check_mem_word(0x108)
        check_reg(6)
        check_reg(7)
        check_reg(8)

    elif tp.name == "structural_hazard":
        check_reg(4)

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

    // Memory response latency. Default: randomized per-transaction delay.
    // Disable with +nostall for debugging.
    localparam integer BASE_LATENCY = 3;
    integer RANDOM_LATENCY;

    integer seed;
    initial begin
        RANDOM_LATENCY = 1;
        if ($test$plusargs("nostall")) RANDOM_LATENCY = 0;
        if ($value$plusargs("seed=%d", seed)) begin
            $urandom(seed);
        end
    end
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

    // Combinational read data: once an address is latched, dm_load is stable even
    // before the ack pulse (more realistic for a synchronous handshake TB).
    always @(*) begin
        // Always provide read data for the currently-addressed word.
        // Handshake timing is modeled via dm_ack/hold.
        dm_load = data_mem[dm_addr[9:2]];
    end

    // Update the memory handshake on the *negedge* so dm_ack is stable before the
    // CPU samples it on the next posedge (avoids same-edge sampling artifacts).
    always @(negedge clk or negedge rst) begin
        if (!rst) begin
            dm_ack    <= 1'b0;
            dmem_busy <= 1'b0;
            dmem_cnt  <= 0;
        end else begin
            dm_ack <= 1'b0;
            if (!dmem_busy) begin
                if (data_req) begin
                    dmem_busy  <= 1'b1;
                    if (RANDOM_LATENCY) begin
                        // 1..7 cycles pseudo-random delay
                        dmem_cnt <= ($urandom % 7) + 1;
                    end else begin
                        dmem_cnt <= BASE_LATENCY;
                    end
                    pend_we    <= mem_we;
                    pend_re    <= mem_re;
                    pend_addr  <= dm_addr;
                    pend_wdata <= dm_store;

                    // For blackbox pipeline testing, commit stores at accept-time so
                    // subsequent loads observe the value (avoids testbench ordering artifacts).
                    if (mem_we) begin
                        data_mem[dm_addr[9:2]] <= dm_store;
                    end
                end
            end else begin
                if (dmem_cnt != 0) begin
                    dmem_cnt <= dmem_cnt - 1;
                end else begin
                    // Response handshake (one-cycle pulse)
                    dm_ack <= 1'b1;
                    dmem_busy <= 1'b0;
                end
            end
        end
    end

    // ========= tracing =========
    localparam integer TRACE = 1;
    integer cyc;

    initial begin
        cyc = 0;
        if (TRACE) begin
            $dumpfile("/tmp/{tp.name}.vcd");
            $dumpvars(0, rv32i_blackbox_tb);
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            cyc <= 0;
        end else begin
            cyc <= cyc + 1;
            if (TRACE && cyc < 200) begin
                // Print a short window; for longer traces use VCD.
                $display("[cyc=%0d] hold=%b flush=%b pc_id=%h inst_id=%h inst_ex=%h inst_ma=%h inst_wb=%h | A_sel=%b B_sel=%b | rd=%0d reg_wrt=%b din=%h | mem_req=%b we=%b re=%b ack=%b dm_addr=%h dm_store=%h dm_load=%h dm_ctl=%b",
                         cyc,
                         uut.hold,
                         uut.flush,
                         uut.pc_id,
                         uut.inst_id,
                         uut.inst_ex,
                         uut.inst_ma,
                         uut.inst_wb,
                         uut.A_sel,
                         uut.B_sel,
                         uut.rd,
                         uut.reg_wrt,
                         uut.din,
                         mem_req, mem_we, mem_re, dm_ack,
                         dm_addr, dm_store, dm_load, dm_ctl);
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
    programs = [
        build_smoke_program(),
        build_branch_program(),
        build_branch_dep_program(),
        build_load_use_program(),
        build_load_store_program(),
        build_alu_program(),
        build_store_data_fwd_program(),
        build_store_base_fwd_program(),
        build_branch_not_taken_dep_program(),
        build_flush_wrongpath_wb_program(),
        build_double_branch_program(),
        build_mem_back_to_back_program(),
        build_structural_hazard_program(),
        build_jal_jalr_program(),
        build_jalr_dep_program(),
    ]
    for tp in programs:
        ref = run_ref(tp)
        tb = gen_verilog(tp, ref)
        out = f"/home/zcq/CowCat32/sim/rv32i_blackbox/{tp.name}_tb.v"
        with open(out, "w", encoding="utf-8") as f:
            f.write(tb)
        print("wrote", out)


if __name__ == "__main__":
    main()
