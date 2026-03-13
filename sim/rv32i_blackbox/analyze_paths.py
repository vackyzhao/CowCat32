#!/usr/bin/env python3
"""Analyze ctrl-fuzz failing seeds: classify divergence paths by comparing DUT WB trace vs ref model.

Usage:
  python3 sim/rv32i_blackbox/analyze_paths.py --seed 1049
  python3 sim/rv32i_blackbox/analyze_paths.py --seeds 1008 1009 ...

Assumes fail artifacts exist in sim/rv32i_blackbox/fails/fuzz_straight_seed<seed>/.
Generates a TRACE_WB log by compiling the per-seed TB with -DTRACE_WB.
"""

from __future__ import annotations

import argparse
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple, Optional

ROOT = Path(__file__).resolve().parents[2]  # CowCat32

import sys
sys.path.insert(0, str(ROOT))

# reuse the reference model from fuzz.py
from sim.rv32i_blackbox.fuzz import CPUState, step_rv32i, mask
FAILS = ROOT / "sim/rv32i_blackbox/fails"

WB_RE = re.compile(r"^\[wb\] pc_wb=([0-9a-fA-F]+) inst_wb=([0-9a-fA-F]+) rd=(\d+) din=([0-9a-fA-F]+)")
EX_RE = re.compile(r"^\[ex\] pc=([0-9a-fA-F]+) inst=([0-9a-fA-F]+)")


@dataclass
class Commit:
    pc: int
    inst: int
    rd: int
    val: int


def run(cmd: List[str], cwd: Path) -> str:
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return p.stdout


def load_hex_words(hex_path: Path) -> List[int]:
    words = []
    for ln in hex_path.read_text().splitlines():
        ln = ln.strip()
        if not ln:
            continue
        words.append(int(ln, 16) & 0xFFFF_FFFF)
    return words


def ref_commits(hex_words: List[int], max_steps: int = 2000) -> List[Commit]:
    st = CPUState()
    commits: List[Commit] = []

    for _ in range(max_steps):
        pc0 = st.pc
        idx = pc0 // 4
        if idx < 0 or idx >= len(hex_words):
            break
        inst = hex_words[idx]

        # decode whether instruction writes rd
        opcode = inst & 0x7F
        rd = (inst >> 7) & 0x1F
        writes = opcode in (0x13, 0x33, 0x03, 0x6F, 0x67, 0x37, 0x17)  # OP-IMM, OP, LOAD, JAL, JALR, LUI, AUIPC

        step_rv32i(st, inst)

        if writes and rd != 0:
            commits.append(Commit(pc=pc0, inst=inst, rd=rd, val=st.x[rd]))

    return commits


def dut_exseq(seed: int, max_lines: int = 500000) -> List[Tuple[int,int]]:
    """Sequence of instructions observed in EX when !hold (best proxy for in-order execute stream)."""
    d = FAILS / f"fuzz_straight_seed{seed}"
    tb = next(d.glob("*_tb.v"))
    out_bin = Path(f"/tmp/seed{seed}_exseq.out")

    cmd = [
        "iverilog",
        "-g2012",
        "-DTRACE_EXSEQ",
        "-o",
        str(out_bin),
        str(tb),
        "sim/tb/*.v",
        "src/core/*.v",
        "src/control/*.v",
        "src/datapath/*.v",
    ]
    compile_out = run(["bash", "-lc", " ".join(cmd)], cwd=ROOT)
    if "error" in compile_out.lower():
        raise RuntimeError(f"compile failed for seed {seed}:\n{compile_out[-1000:]}")

    run_out = run(["bash", "-lc", f"vvp -n {out_bin} +seed={seed}"], cwd=ROOT)
    seq: List[Tuple[int,int]] = []
    for ln in run_out.splitlines()[:max_lines]:
        m = EX_RE.match(ln.strip())
        if m:
            pc = int(m.group(1), 16)
            inst = int(m.group(2), 16)
            seq.append((pc, inst))
    return seq


def first_divergence_seq(ref: List[Tuple[int,int]], dut: List[Tuple[int,int]]) -> Tuple[int, Optional[Tuple[int,int]], Optional[Tuple[int,int]], str]:
    n = min(len(ref), len(dut))
    for i in range(n):
        if ref[i] != dut[i]:
            r, d = ref[i], dut[i]
            reason = []
            if r[0] != d[0]:
                reason.append("pc_mismatch")
            if r[1] != d[1]:
                reason.append("inst_mismatch")
            return i, r, d, ",".join(reason)
    if len(ref) != len(dut):
        return n, (ref[n] if n < len(ref) else None), (dut[n] if n < len(dut) else None), "length_mismatch"
    return -1, None, None, "no_divergence"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int)
    ap.add_argument("--seeds", type=int, nargs="*")
    args = ap.parse_args()
    seeds = []
    if args.seed is not None:
        seeds.append(args.seed)
    if args.seeds:
        seeds += args.seeds
    if not seeds:
        raise SystemExit("provide --seed or --seeds")

    for seed in seeds:
        d = FAILS / f"fuzz_straight_seed{seed}"
        hexp = d / f"fuzz_straight_seed{seed}.hex"
        if not hexp.exists():
            print(f"seed {seed}: missing {hexp}")
            continue
        hex_words = load_hex_words(hexp)
        # reference execute stream (pc, inst)
        ref_stream = []
        st = CPUState()
        for _ in range(10000):
            pc0 = st.pc
            idx = pc0 // 4
            if idx < 0 or idx >= len(hex_words):
                break
            inst = hex_words[idx]
            if inst != 0x00000013:
                ref_stream.append((pc0, inst))
            step_rv32i(st, inst)

        dut_stream = dut_exseq(seed)
        idx, r, d, reason = first_divergence_seq(ref_stream, dut_stream)
        print(f"seed={seed} ref_ex={len(ref_stream)} dut_ex={len(dut_stream)} diverge_at={idx} reason={reason}")
        if idx >= 0 and r and d:
            print(f"  ref: pc={r[0]:08x} inst={r[1]:08x}")
            print(f"  dut: pc={d[0]:08x} inst={d[1]:08x}")


if __name__ == "__main__":
    main()
