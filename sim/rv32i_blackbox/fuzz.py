#!/usr/bin/env python3
"""RV32I blackbox random differential test (straight-line, LW/SW + ALU subset).

Generates a self-contained Verilog testbench (no toolchain) that:
- Feeds a random straight-line program via an instruction ROM
- Uses an in-TB word-addressed memory with randomized response latency
- Compares DUT architectural state (regs + memory window) against a Python ref model

Failures are reproducible by reusing the same seed.
"""

from __future__ import annotations

import argparse
import os
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

XLEN = 32

# -------------------------
# RV32I encoders (subset)
# -------------------------

def mask(n: int, bits: int = 32) -> int:
    return n & ((1 << bits) - 1)


def sign_extend(n: int, bits: int) -> int:
    m = 1 << (bits - 1)
    return mask((n & ((1 << bits) - 1)) ^ m) - m


def enc_i(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return mask(((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode)


def enc_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return mask((funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode)


def enc_s(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return mask((imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode)


def enc_b(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    # imm is signed, multiple of 2
    imm &= 0x1FFF
    b12 = (imm >> 12) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    b11 = (imm >> 11) & 1
    return mask((b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode)


def enc_j(imm: int, rd: int, opcode: int) -> int:
    # imm is signed, multiple of 2
    imm &= 0x1FFFFF
    b20 = (imm >> 20) & 1
    b10_1 = (imm >> 1) & 0x3FF
    b11 = (imm >> 11) & 1
    b19_12 = (imm >> 12) & 0xFF
    return mask((b20 << 31) | (b19_12 << 12) | (b11 << 20) | (b10_1 << 21) | (rd << 7) | opcode)


def enc_u(imm20: int, rd: int, opcode: int) -> int:
    # imm20 occupies bits [31:12]
    return mask(((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode)


# Opcodes
OP_IMM = 0x13
OP = 0x33
LOAD = 0x03
STORE = 0x23
BRANCH = 0x63
JAL = 0x6F
JALR = 0x67
LUI = 0x37
AUIPC = 0x17

# funct3
F3_ADD_SUB = 0b000
F3_SLL = 0b001
F3_SLT = 0b010
F3_SLTU = 0b011
F3_XOR = 0b100
F3_SRL_SRA = 0b101
F3_OR = 0b110
F3_AND = 0b111

F3_BEQ = 0b000
F3_BNE = 0b001
F3_BLT = 0b100
F3_BGE = 0b101
F3_BLTU = 0b110
F3_BGEU = 0b111

F3_LW = 0b010
F3_SW = 0b010

NOP = 0x00000013  # addi x0,x0,0


# -------------------------
# Minimal reference model
# -------------------------

@dataclass
class CPUState:
    pc: int = 0
    x: List[int] | None = None
    mem: Dict[int, int] | None = None  # word-addressed memory

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

    def wreg(r: int, v: int):
        if r != 0:
            st.x[r] = mask(v)

    def load_w(addr: int) -> int:
        if addr % 4 != 0:
            raise ValueError(f"misaligned lw addr {addr:#x}")
        return st.mem.get(addr, 0)

    def store_w(addr: int, val: int):
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
        elif funct3 == F3_SLT:
            wreg(rd, 1 if (sign_extend(a, 32) < sign_extend(imm, 32)) else 0)
        elif funct3 == F3_SLTU:
            wreg(rd, 1 if ((a & 0xFFFF_FFFF) < (imm & 0xFFFF_FFFF)) else 0)
        elif funct3 == F3_SLL:
            shamt = (inst >> 20) & 0x1F
            wreg(rd, a << shamt)
        elif funct3 == F3_SRL_SRA:
            shamt = (inst >> 20) & 0x1F
            if (inst >> 30) & 1:
                sa = sign_extend(a, 32)
                wreg(rd, sa >> shamt)
            else:
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
        elif funct3 == F3_SLT:
            wreg(rd, 1 if (sign_extend(a, 32) < sign_extend(b, 32)) else 0)
        elif funct3 == F3_SLTU:
            wreg(rd, 1 if ((a & 0xFFFF_FFFF) < (b & 0xFFFF_FFFF)) else 0)
        elif funct3 == F3_SLL:
            wreg(rd, a << (b & 0x1F))
        elif funct3 == F3_SRL_SRA:
            shamt = b & 0x1F
            if funct7 == 0x20:
                sa = sign_extend(a, 32)
                wreg(rd, sa >> shamt)
            else:
                wreg(rd, (a & 0xFFFF_FFFF) >> shamt)
        else:
            raise NotImplementedError(f"OP funct3 {funct3}")

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
        elif funct3 == F3_BLTU:
            take = ((a & 0xFFFF_FFFF) < (b & 0xFFFF_FFFF))
        elif funct3 == F3_BGEU:
            take = ((a & 0xFFFF_FFFF) >= (b & 0xFFFF_FFFF))
        else:
            raise NotImplementedError(f"BRANCH funct3 {funct3}")
        if take:
            st.pc = mask(pc0 + imm)

    elif opcode == JAL:
        imm = ((inst >> 31) << 20) | (((inst >> 12) & 0xFF) << 12) | (((inst >> 20) & 1) << 11) | (((inst >> 21) & 0x3FF) << 1)
        imm = sign_extend(imm, 21)
        wreg(rd, pc0 + 4)
        st.pc = mask(pc0 + imm)

    elif opcode == JALR:
        imm = sign_extend(inst >> 20, 12)
        t = mask(st.x[rs1] + imm)
        wreg(rd, pc0 + 4)
        st.pc = mask(t & ~1)

    elif opcode == LUI:
        imm = inst & 0xFFFFF000
        wreg(rd, imm)

    elif opcode == AUIPC:
        imm = inst & 0xFFFFF000
        wreg(rd, pc0 + imm)

    else:
        raise NotImplementedError(f"opcode {opcode:#x}")


# -------------------------
# Program generation
# -------------------------

def choose_reg(rng: random.Random, defined: List[int], exclude: Tuple[int, ...] = ()) -> int:
    pool = [r for r in defined if r not in exclude and r != 0]
    if not pool:
        # fallback to a non-zero reg
        pool = [r for r in range(1, 32) if r not in exclude]
    return rng.choice(pool)


def gen_program(seed: int, length: int, mem_base: int, mem_words: int, enable_ctrl: bool) -> Tuple[List[int], List[str], List[int], List[int]]:
    rng = random.Random(seed)

    insts: List[int] = []
    asm: List[str] = []
    written_regs: set[int] = set()
    touched_mem: set[int] = set()  # word addresses

    # Use x5 as mem base pointer (reserved: generator never writes x5 again).
    insts.append(enc_i(mem_base, 0, F3_ADD_SUB, 5, OP_IMM))
    asm.append(f"addi x5, x0, {mem_base}")
    written_regs.add(5)

    # Keep a fixed, aligned non-zero reg as a safety base for comparisons/branches
    # to avoid shifting/sign-extending weirdness causing accidental illegal behavior.
    insts.append(enc_i(0x200, 0, F3_ADD_SUB, 31, OP_IMM))
    asm.append("addi x31, x0, 0x200")
    written_regs.add(31)

    defined = [0, 5, 31]
    reserved = {5, 31}

    # Seed a few regs with known values (avoid all-zeros program)
    for r in [1, 2, 3, 4, 6, 7, 8]:
        imm = rng.randrange(-2048, 2048)
        insts.append(enc_i(imm, 0, F3_ADD_SUB, r, OP_IMM))
        asm.append(f"addi x{r}, x0, {imm}")
        written_regs.add(r)
        if r not in defined:
            defined.append(r)

    def rand_imm12():
        return rng.randrange(-2048, 2048)

    def rand_shamt():
        return rng.randrange(0, 32)

    def rand_mem_off():
        # Keep offsets within 12-bit immediate and aligned.
        off = rng.randrange(0, mem_words) * 4
        assert -2048 <= off <= 2047
        return off

    last_load_rd = None
    # PCs that must not be used as control-flow targets (e.g., 2nd half of a macro-instruction pair)
    forbidden_targets: set[int] = set()

    # Generate (length) instructions. When control-flow is enabled, we only emit forward redirects.
    for i in range(length):
        # Encourage use-after-load hazards.
        if last_load_rd is not None and rng.random() < 0.40:
            rd = choose_reg(rng, list(range(1, 32)), exclude=(last_load_rd, 5, 31))
            rs1 = last_load_rd
            imm = rand_imm12()
            insts.append(enc_i(imm, rs1, F3_ADD_SUB, rd, OP_IMM))
            asm.append(f"addi x{rd}, x{rs1}, {imm}")
            written_regs.add(rd)
            if rd not in defined:
                defined.append(rd)
            last_load_rd = None
            continue

        t = rng.random()

        if enable_ctrl and t < 0.10:
            # Forward control-flow only (no backward jumps) and keep target within program.
            kind = rng.random()
            curr_pc = len(insts) * 4
            max_fwd = 12  # instructions

            # bytes after full generation + drain(16) + terminator(1)
            remaining_words = (length - i)
            max_pc = (len(insts) + remaining_words + 16 + 1) * 4
            max_legal_fwd = (max_pc - curr_pc) // 4 - 1

            if max_legal_fwd > 0:
                fwd = rng.randrange(1, min(max_fwd, max_legal_fwd) + 1)
                target_pc = curr_pc + fwd * 4
                # Avoid targets that land in the middle of a macro-instruction pair.
                if target_pc in forbidden_targets:
                    insts.append(NOP)
                    asm.append("nop")
                    last_load_rd = None
                    continue
                imm = target_pc - curr_pc

                if kind < 0.50:
                    rs1 = choose_reg(rng, defined, exclude=(5, 31))
                    rs2 = 31
                    funct3 = rng.choice([F3_BEQ, F3_BNE, F3_BLT, F3_BGE, F3_BLTU, F3_BGEU])
                    insts.append(enc_b(imm, rs2, rs1, funct3, BRANCH))
                    m = {F3_BEQ:'beq',F3_BNE:'bne',F3_BLT:'blt',F3_BGE:'bge',F3_BLTU:'bltu',F3_BGEU:'bgeu'}[funct3]
                    asm.append(f"{m} x{rs1}, x{rs2}, +{imm}")
                elif kind < 0.80:
                    rd = rng.choice([0] + [r for r in range(1, 32) if r not in (5, 31)])
                    insts.append(enc_j(imm, rd, JAL))
                    asm.append(f"jal x{rd}, +{imm}")
                    written_regs.add(rd)
                    if rd not in defined:
                        defined.append(rd)
                else:
                    # JALR bring-up B: compute target into a base register, then jalr through it.
                    # This stresses forwarding/hold/flush interaction on rs1.
                    # Constrain to forward targets within encodable imm12 for `addi`.
                    ra = rng.choice([r for r in range(1, 32) if r not in (5, 31)])

                    # Choose a forward aligned target within the program.
                    tgt = target_pc & ~3
                    if tgt <= curr_pc:
                        # no legal forward target -> fall back to NOP
                        insts.append(NOP)
                        asm.append("nop")
                    else:
                        written_regs.add(ra)
                        if ra not in defined:
                            defined.append(ra)

                        if tgt <= 2047:
                            # Short form: addi ra, x0, tgt ; jalr x0, 0(ra)
                            insts.append(enc_i(tgt, 0, F3_ADD_SUB, ra, OP_IMM))
                            asm.append(f"addi x{ra}, x0, {tgt}")

                            # Mark this PC as an illegal jump target for other control-flow to avoid
                            # landing on the jalr without executing the addi.
                            forbidden_targets.add(curr_pc + 4)

                            rd = 0
                            insts.append(enc_i(0, ra, F3_ADD_SUB, rd, JALR))
                            asm.append(f"jalr x{rd}, 0(x{ra})")
                        else:
                            # Long form: lui/addi/jalr to reach full program range.
                            # Compute (tgt) into ra using standard split.
                            imm20 = (tgt + 0x800) >> 12
                            lo12 = sign_extend(tgt - (imm20 << 12), 12)

                            insts.append(enc_u(imm20, ra, LUI))
                            asm.append(f"lui x{ra}, {imm20}")

                            insts.append(enc_i(lo12, ra, F3_ADD_SUB, ra, OP_IMM))
                            asm.append(f"addi x{ra}, x{ra}, {lo12}")

                            # forbid landing on the addi or jalr without executing the lui
                            forbidden_targets.add(curr_pc + 4)
                            forbidden_targets.add(curr_pc + 8)

                            rd = 0
                            insts.append(enc_i(0, ra, F3_ADD_SUB, rd, JALR))
                            asm.append(f"jalr x{rd}, 0(x{ra})")

                last_load_rd = None
                continue

        elif t < 0.26:
            # LW
            rd = rng.choice([r for r in range(1, 32) if r not in (5, 31)])
            off = rand_mem_off()
            insts.append(enc_i(off, 5, F3_LW, rd, LOAD))
            asm.append(f"lw x{rd}, {off}(x5)")
            written_regs.add(rd)
            touched_mem.add(mem_base + off)
            if rd not in defined:
                defined.append(rd)
            last_load_rd = rd

        elif t < 0.50:
            # SW
            rs2 = choose_reg(rng, defined, exclude=(5, 31))
            off = rand_mem_off()
            insts.append(enc_s(off, rs2, 5, F3_SW, STORE))
            asm.append(f"sw x{rs2}, {off}(x5)")
            touched_mem.add(mem_base + off)
            last_load_rd = None

        elif t < 0.74:
            # OP-IMM ALU
            rd = rng.choice([r for r in range(1, 32) if r not in (5, 31)])
            rs1 = choose_reg(rng, defined, exclude=(5, 31))
            k = rng.randrange(0, 8)
            if k == 0:
                imm = rand_imm12()
                insts.append(enc_i(imm, rs1, F3_ADD_SUB, rd, OP_IMM))
                asm.append(f"addi x{rd}, x{rs1}, {imm}")
            elif k == 1:
                imm = rand_imm12()
                insts.append(enc_i(imm, rs1, F3_AND, rd, OP_IMM))
                asm.append(f"andi x{rd}, x{rs1}, {imm}")
            elif k == 2:
                imm = rand_imm12()
                insts.append(enc_i(imm, rs1, F3_OR, rd, OP_IMM))
                asm.append(f"ori x{rd}, x{rs1}, {imm}")
            elif k == 3:
                imm = rand_imm12()
                insts.append(enc_i(imm, rs1, F3_XOR, rd, OP_IMM))
                asm.append(f"xori x{rd}, x{rs1}, {imm}")
            elif k == 4:
                imm = rand_imm12()
                insts.append(enc_i(imm, rs1, F3_SLT, rd, OP_IMM))
                asm.append(f"slti x{rd}, x{rs1}, {imm}")
            elif k == 5:
                imm = rand_imm12()
                insts.append(enc_i(imm, rs1, F3_SLTU, rd, OP_IMM))
                asm.append(f"sltiu x{rd}, x{rs1}, {imm}")
            elif k == 6:
                sh = rand_shamt()
                insts.append(enc_i(sh, rs1, F3_SLL, rd, OP_IMM))
                asm.append(f"slli x{rd}, x{rs1}, {sh}")
            else:
                sh = rand_shamt()
                is_sra = rng.random() < 0.5
                imm = sh | (0x400 if is_sra else 0)
                insts.append(enc_i(imm, rs1, F3_SRL_SRA, rd, OP_IMM))
                asm.append(f"{'srai' if is_sra else 'srli'} x{rd}, x{rs1}, {sh}")
            written_regs.add(rd)
            if rd not in defined:
                defined.append(rd)
            last_load_rd = None

        else:
            # OP ALU
            rd = rng.choice([r for r in range(1, 32) if r not in (5, 31)])
            rs1 = choose_reg(rng, defined, exclude=(5, 31))
            rs2 = choose_reg(rng, defined, exclude=(5, 31))
            k = rng.randrange(0, 8)
            if k == 0:
                insts.append(enc_r(0x00, rs2, rs1, F3_ADD_SUB, rd, OP))
                asm.append(f"add x{rd}, x{rs1}, x{rs2}")
            elif k == 1:
                insts.append(enc_r(0x20, rs2, rs1, F3_ADD_SUB, rd, OP))
                asm.append(f"sub x{rd}, x{rs1}, x{rs2}")
            elif k == 2:
                insts.append(enc_r(0x00, rs2, rs1, F3_AND, rd, OP))
                asm.append(f"and x{rd}, x{rs1}, x{rs2}")
            elif k == 3:
                insts.append(enc_r(0x00, rs2, rs1, F3_OR, rd, OP))
                asm.append(f"or x{rd}, x{rs1}, x{rs2}")
            elif k == 4:
                insts.append(enc_r(0x00, rs2, rs1, F3_XOR, rd, OP))
                asm.append(f"xor x{rd}, x{rs1}, x{rs2}")
            elif k == 5:
                insts.append(enc_r(0x00, rs2, rs1, F3_SLT, rd, OP))
                asm.append(f"slt x{rd}, x{rs1}, x{rs2}")
            elif k == 6:
                insts.append(enc_r(0x00, rs2, rs1, F3_SLTU, rd, OP))
                asm.append(f"sltu x{rd}, x{rs1}, x{rs2}")
            else:
                which = rng.randrange(0, 3)
                if which == 0:
                    insts.append(enc_r(0x00, rs2, rs1, F3_SLL, rd, OP))
                    asm.append(f"sll x{rd}, x{rs1}, x{rs2}")
                elif which == 1:
                    insts.append(enc_r(0x00, rs2, rs1, F3_SRL_SRA, rd, OP))
                    asm.append(f"srl x{rd}, x{rs1}, x{rs2}")
                else:
                    insts.append(enc_r(0x20, rs2, rs1, F3_SRL_SRA, rd, OP))
                    asm.append(f"sra x{rd}, x{rs1}, x{rs2}")
            written_regs.add(rd)
            if rd not in defined:
                defined.append(rd)
            last_load_rd = None

    # Drain pipeline
    for _ in range(16):
        insts.append(NOP)
        asm.append("nop")

    # Stable terminator: infinite self-loop so PC never falls off ROM.
    insts.append(enc_j(0, 0, JAL))
    asm.append("jal x0, +0")

    # ---- Post-fixup: prevent control-flow landing on the 2nd half of an addi+jarl macro pair ----
    def is_addi_x0(inst: int) -> bool:
        return (inst & 0x7f) == OP_IMM and ((inst >> 12) & 0x7) == F3_ADD_SUB and ((inst >> 15) & 0x1f) == 0

    def is_addi_rr(inst: int, rd: int) -> bool:
        return (inst & 0x7f) == OP_IMM and ((inst >> 12) & 0x7) == F3_ADD_SUB and ((inst >> 7) & 0x1f) == rd and ((inst >> 15) & 0x1f) == rd

    def is_lui_rd(inst: int, rd: int) -> bool:
        return (inst & 0x7f) == LUI and ((inst >> 7) & 0x1f) == rd

    def is_jalr_x0_rs1(inst: int, rs1: int) -> bool:
        return (inst & 0x7f) == JALR and ((inst >> 12) & 0x7) == F3_ADD_SUB and ((inst >> 7) & 0x1f) == 0 and ((inst >> 15) & 0x1f) == rs1 and (((inst >> 20) & 0xfff) == 0)

    forbidden: set[int] = set()
    macro_pairs: list[tuple[int,int,int,int]] = []  # (kind, idx0, rd, target)
    # kind: 2=addi+jarl, 3=lui+addi+jarl

    for idx in range(len(insts) - 2):
        a = insts[idx]
        b = insts[idx + 1]
        c = insts[idx + 2]

        # 2-inst macro: addi rd,x0,imm ; jalr x0,0(rd)
        rd = (a >> 7) & 0x1f
        if is_addi_x0(a) and rd != 0 and is_jalr_x0_rs1(b, rd):
            forbidden.add((idx + 1) * 4)  # PC of jalr
            imm12 = (a >> 20) & 0xfff
            imm = (imm12 & 0x7ff) - (imm12 & 0x800)
            macro_pairs.append((2, idx, rd, imm & 0xffff_ffff))
            continue

        # 3-inst macro: lui rd,imm20 ; addi rd,rd,imm12 ; jalr x0,0(rd)
        rd_b = (b >> 7) & 0x1f
        if rd_b != 0 and is_lui_rd(a, rd_b) and is_addi_rr(b, rd_b) and is_jalr_x0_rs1(c, rd_b):
            pc_addi = (idx + 1) * 4
            pc_jalr = (idx + 2) * 4
            forbidden.add(pc_addi)
            forbidden.add(pc_jalr)

            imm20 = (a >> 12) & 0xfffff
            imm12 = (b >> 20) & 0xfff
            lo12 = (imm12 & 0x7ff) - (imm12 & 0x800)
            target = ((imm20 << 12) + lo12) & 0xffff_ffff
            macro_pairs.append((3, idx, rd_b, target))

    def sext(val: int, bits: int) -> int:
        sign = 1 << (bits - 1)
        return (val & (sign - 1)) - (val & sign)

    def imm_b(inst: int) -> int:
        imm = ((inst >> 31) & 0x1) << 12
        imm |= ((inst >> 7) & 0x1) << 11
        imm |= ((inst >> 25) & 0x3f) << 5
        imm |= ((inst >> 8) & 0xf) << 1
        return sext(imm, 13)

    def imm_j(inst: int) -> int:
        imm = ((inst >> 31) & 0x1) << 20
        imm |= ((inst >> 12) & 0xff) << 12
        imm |= ((inst >> 20) & 0x1) << 11
        imm |= ((inst >> 21) & 0x3ff) << 1
        return sext(imm, 21)

    # Fixup 1: JAL/BRANCH must not target the 2nd half (jalr) of a macro pair.
    for idx, inst in enumerate(insts):
        pc = idx * 4
        opc = inst & 0x7f
        if opc == BRANCH:
            tgt = (pc + imm_b(inst)) & 0xffff_ffff
            if tgt in forbidden:
                insts[idx] = NOP
                asm[idx] = "nop"
        elif opc == JAL:
            tgt = (pc + imm_j(inst)) & 0xffff_ffff
            if tgt in forbidden:
                insts[idx] = NOP
                asm[idx] = "nop"

    # Fixup 2: JALR macro targets must also not land on forbidden PCs.
    # If they do, bump the target forward by 4 until safe.
    for kind, idx0, rd, tgt in macro_pairs:
        if tgt in forbidden:
            new_tgt = tgt
            if kind == 2:
                # kind2 uses addi imm12 absolute target: must stay within [0..2047]
                while new_tgt in forbidden and new_tgt <= 2044:
                    new_tgt += 4
            else:
                # kind3 uses lui+addi so can reach larger range (still within program size)
                while new_tgt in forbidden and new_tgt <= 0x7fff:
                    new_tgt = (new_tgt + 4) & 0xffff_ffff

            if new_tgt in forbidden or (kind == 2 and new_tgt > 2047):
                # give up: neutralize this macro
                insts[idx0] = NOP
                asm[idx0] = "nop"
                insts[idx0+1] = NOP
                asm[idx0+1] = "nop"
                if kind == 3:
                    insts[idx0+2] = NOP
                    asm[idx0+2] = "nop"
            else:
                if kind == 2:
                    insts[idx0] = enc_i(new_tgt, 0, F3_ADD_SUB, rd, OP_IMM)
                    asm[idx0] = f"addi x{rd}, x0, {new_tgt}"
                else:
                    imm20 = (new_tgt + 0x800) >> 12
                    lo12 = sign_extend(new_tgt - (imm20 << 12), 12)
                    insts[idx0] = enc_u(imm20, rd, LUI)
                    asm[idx0] = f"lui x{rd}, {imm20}"
                    insts[idx0+1] = enc_i(lo12, rd, F3_ADD_SUB, rd, OP_IMM)
                    asm[idx0+1] = f"addi x{rd}, x{rd}, {lo12}"

    regs_to_check = sorted(r for r in written_regs if r != 0)
    mem_words_touched = sorted(touched_mem)
    return insts, asm, regs_to_check, mem_words_touched


def run_ref(insts: List[int], max_steps: int = 200000) -> CPUState:
    """Execute with instruction fetch by PC so control-flow works.

    Stops when PC exits the ROM range or max_steps is hit.
    """
    st = CPUState(pc=0)
    steps = 0
    rom_bytes = len(insts) * 4
    while steps < max_steps:
        pc = st.pc & 0xFFFF_FFFF
        if pc >= rom_bytes:
            break
        inst = insts[pc >> 2]
        step_rv32i(st, inst)
        steps += 1
    st.x[0] = 0
    return st


def gen_tb(name: str, insts: List[int], ref: CPUState, max_cycles: int, mem_base: int, mem_words: int, regs_to_check: List[int]) -> str:
    # ROM cases
    rom_cases: List[str] = []
    pc = 0
    for inst in insts:
        rom_cases.append(f"        32'h{pc:08x}: im_inst = 32'h{inst:08x};")
        pc += 4

    # Checks
    checks: List[str] = []

    def check_reg(i: int):
        exp = ref.x[i] & 0xFFFF_FFFF
        checks.append(f"        if (uut.ID.registers_file.regs[{i}] !== 32'h{exp:08x}) begin")
        checks.append(f"            $display(\"FAIL: x{i} exp={exp:08x} got=%h\", uut.ID.registers_file.regs[{i}]);")
        checks.append("            $fatal(1);")
        checks.append("        end")

    # Only check registers we wrote in the generated program.
    for i in regs_to_check:
        if i != 0:
            check_reg(i)

    def check_mem_word(addr: int):
        exp = ref.mem.get(addr, 0) & 0xFFFF_FFFF
        checks.append(f"        if (dmem.mem[32'h{addr:08x} >> 2] !== 32'h{exp:08x}) begin")
        checks.append(f"            $display(\"FAIL: mem[0x{addr:x}] exp={exp:08x} got=%h\", dmem.mem[32'h{addr:08x} >> 2]);")
        checks.append("            $fatal(1);")
        checks.append("        end")

    for w in range(mem_words):
        check_mem_word(mem_base + 4 * w)

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
{os.linesep.join(rom_cases)}
        default: im_inst = 32'h00000013; // nop
        endcase
    end

    // ===== data memory model (shared) =====
    dmem_model #(
        .DEPTH_WORDS  (256),
        .ADDR_LSB     (2),
        .ADDR_MSB     (9),
        .BASE_LATENCY (3)
    ) dmem (
        .clk      (clk),
        .rst      (rst),
        .mem_req  (mem_req),
        .mem_we   (mem_we),
        .mem_re   (mem_re),
        .dm_addr  (dm_addr),
        .dm_store (dm_store),
        .dm_ctl   (dm_ctl),
        .dm_ack   (dm_ack),
        .dm_load  (dm_load)
    );

    // ========= tracing =========
    integer TRACE;
    integer cyc;

    initial begin
        cyc = 0;
        TRACE = 0;
        if ($test$plusargs("trace")) TRACE = 1;
        if (TRACE) begin
            $dumpfile("/tmp/{name}.vcd");
            $dumpvars(0, rv32i_blackbox_tb);
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            cyc <= 0;
        end else begin
            cyc <= cyc + 1;
            if (TRACE) begin
                // Event-triggered tracing to keep logs readable.
                if ((cyc < 200) || mem_req || uut.reg_wrt) begin
                    $display("[cyc=%0d] hold=%b flush=%b pc_id=%h pc_ex=%h pc_ma=%h | inst_id=%h inst_ex=%h inst_ma=%h inst_wb=%h | rd=%0d reg_wrt=%b din=%h | mem_req=%b we=%b re=%b ack=%b dm_addr=%h dm_store=%h dm_load=%h dm_ctl=%b",
                             cyc,
                             uut.hold,
                             uut.flush,
                             uut.pc_id,
                             uut.pc_ex,
                             uut.pc_ma,
                             uut.inst_id,
                             uut.inst_ex,
                             uut.inst_ma,
                             uut.inst_wb,
                             uut.rd,
                             uut.reg_wrt,
                             uut.din,
                             mem_req, mem_we, mem_re, dm_ack,
                             dm_addr, dm_store, dm_load, dm_ctl);
                end
            end
            if (cyc > {max_cycles}) begin
                $display("FAIL: timeout after %0d cycles", cyc);
                $fatal(1);
            end
        end
    end

    initial begin
        rst = 1'b0;
        #20; rst = 1'b1;

        #( {max_cycles} * 10 );

        // checks
{checks_str}

        $display("PASS: {name}");
        $finish;
    end
endmodule
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--len", dest="length", type=int, default=300)
    ap.add_argument("--name", type=str, default="fuzz_straight")
    ap.add_argument("--out", type=str, required=True, help="output .v path")
    ap.add_argument("--asm-out", type=str, required=True, help="output .S path")
    ap.add_argument("--hex-out", type=str, required=True, help="output hex words path")
    ap.add_argument("--mem-base", type=lambda s: int(s, 0), default=0x100)
    ap.add_argument("--mem-words", type=int, default=64)
    ap.add_argument("--ctrl", action="store_true", help="enable control-flow (branches/jumps)")
    args = ap.parse_args()

    insts, asm, regs_to_check, _touched = gen_program(args.seed, args.length, args.mem_base, args.mem_words, args.ctrl)
    ref = run_ref(insts)

    # Conservative bound: random dmem stalls can stretch execution significantly.
    max_cycles = max(500, (len(insts) + 80) * 20)
    tb = gen_tb(f"{args.name}_seed{args.seed}", insts, ref, max_cycles, args.mem_base, args.mem_words, regs_to_check)

    Path(args.out).write_text(tb, encoding="utf-8")
    Path(args.asm_out).write_text("\n".join(asm) + "\n", encoding="utf-8")
    Path(args.hex_out).write_text("\n".join(f"{w:08x}" for w in insts) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
