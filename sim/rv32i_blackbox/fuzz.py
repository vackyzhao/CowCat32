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


# Opcodes
OP_IMM = 0x13
OP = 0x33
LOAD = 0x03
STORE = 0x23
BRANCH = 0x63
JAL = 0x6F
JALR = 0x67

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

    defined = [0, 5]
    reserved = {5}

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

    for _ in range(length):
        # Encourage use-after-load hazards.
        if last_load_rd is not None and rng.random() < 0.40:
            rd = choose_reg(rng, list(range(1, 32)), exclude=(last_load_rd, 5))
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
            # Forward control-flow only (no backward jumps) to guarantee termination.
            kind = rng.random()
            curr_pc = len(insts) * 4
            max_fwd = 12  # instructions
            fwd = rng.randrange(1, max_fwd + 1)
            target_idx = min(len(insts) + fwd, len(insts) + max_fwd)
            target_pc = target_idx * 4
            imm = target_pc - curr_pc

            if kind < 0.70:
                # BRANCH
                rs1 = choose_reg(rng, defined, exclude=(5,))
                rs2 = choose_reg(rng, defined, exclude=(5,))
                funct3 = rng.choice([F3_BEQ, F3_BNE, F3_BLT, F3_BGE, F3_BLTU, F3_BGEU])
                insts.append(enc_b(imm, rs2, rs1, funct3, BRANCH))
                m = {F3_BEQ:'beq',F3_BNE:'bne',F3_BLT:'blt',F3_BGE:'bge',F3_BLTU:'bltu',F3_BGEU:'bgeu'}[funct3]
                asm.append(f"{m} x{rs1}, x{rs2}, +{imm}")
            else:
                # JAL (rd may be x0 or some scratch)
                rd = rng.choice([0] + [r for r in range(1, 32) if r != 5])
                insts.append(enc_j(imm, rd, JAL))
                asm.append(f"jal x{rd}, +{imm}")
                written_regs.add(rd)
                if rd not in defined:
                    defined.append(rd)

            last_load_rd = None

        elif t < 0.26:
            # LW
            rd = rng.choice([r for r in range(1, 32) if r != 5])
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
            rs2 = choose_reg(rng, defined, exclude=(5,))
            off = rand_mem_off()
            insts.append(enc_s(off, rs2, 5, F3_SW, STORE))
            asm.append(f"sw x{rs2}, {off}(x5)")
            touched_mem.add(mem_base + off)
            last_load_rd = None

        elif t < 0.74:
            # OP-IMM ALU
            rd = rng.choice([r for r in range(1, 32) if r != 5])
            rs1 = choose_reg(rng, defined, exclude=(5,))
            k = rng.randrange(0, 6)
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
            rd = rng.choice([r for r in range(1, 32) if r != 5])
            rs1 = choose_reg(rng, defined, exclude=(5,))
            rs2 = choose_reg(rng, defined, exclude=(5,))
            k = rng.randrange(0, 6)
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
        checks.append(f"        if (data_mem[32'h{addr:08x} >> 2] !== 32'h{exp:08x}) begin")
        checks.append(f"            $display(\"FAIL: mem[0x{addr:x}] exp={exp:08x} got=%h\", data_mem[32'h{addr:08x} >> 2]);")
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

    // data memory
    reg [31:0] data_mem [0:255];
    integer i;
    initial begin
        for (i=0;i<256;i=i+1) data_mem[i] = 32'h0;
    end

    always @(*) begin
        // Avoid X-propagation from an unstable/unknown address.
        // If the DUT asserts mem_re with an unknown dm_addr, treat it as reading 0.
        if (mem_re) begin
            if (^dm_addr[9:2] === 1'bX)
                dm_load = 32'h00000000;
            else
                dm_load = data_mem[dm_addr[9:2]];
        end else begin
            dm_load = 32'h00000000;
        end
    end

    // Memory response latency
    localparam integer BASE_LATENCY = 3;
    localparam integer RANDOM_LATENCY = 1;

    integer seed;
    initial begin
        if ($value$plusargs("seed=%d", seed)) begin
            $urandom(seed);
        end
    end

    reg dmem_busy;
    reg [3:0] dmem_cnt;
    wire data_req = mem_req && (mem_we || mem_re);

    initial begin
        dm_ack    = 1'b0;
        dmem_busy = 1'b0;
        dmem_cnt  = 0;
    end

    // Update handshake on negedge to avoid same-edge sampling artifacts
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
                        dmem_cnt <= ($urandom % 7) + 1;
                    end else begin
                        dmem_cnt <= BASE_LATENCY;
                    end
                    // Commit stores at accept-time
                    if (mem_we) begin
                        data_mem[dm_addr[9:2]] <= dm_store;
                    end
                end
            end else begin
                if (dmem_cnt != 0) begin
                    dmem_cnt <= dmem_cnt - 1;
                end else begin
                    dm_ack <= 1'b1;
                    dmem_busy <= 1'b0;
                end
            end
        end
    end

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
            if (TRACE && cyc < 200) begin
                $display("[cyc=%0d] hold=%b flush=%b pc_id=%h inst_id=%h inst_ex=%h inst_ma=%h inst_wb=%h | rd=%0d reg_wrt=%b din=%h | mem_req=%b we=%b re=%b ack=%b dm_addr=%h dm_store=%h dm_load=%h dm_ctl=%b",
                         cyc,
                         uut.hold,
                         uut.flush,
                         uut.pc_id,
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
