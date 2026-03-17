#!/usr/bin/env python3
"""Generate a synthesizable-ish Verilog imem ROM from a word-indexed .vh.

Input format: word-indexed $readmemh style produced by objcopy_vh_to_wordvh.py
  @00000000
  deadbeef 00112233 ...

Output: a self-contained Verilog module with an initialized reg array.

Usage:
  wordvh_to_imem_v.py <in_word.vh> <out_imem.v>

Notes:
- The generated file can be large for big programs.
- Many FPGA flows prefer vendor ROM/BRAM init files (MIF/COE). This is a
  portable baseline for simulation and simple synth.
"""

from __future__ import annotations

import sys
import re
from pathlib import Path

HEX8 = re.compile(r"^[0-9A-Fa-f]{8}$")


def parse_wordvh(text: str):
    addr = 0
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith('@'):
            addr = int(line[1:], 16)
            continue
        for tok in line.split():
            if not HEX8.match(tok):
                continue
            yield addr, int(tok, 16)
            addr += 1


def main(inp: Path, outp: Path):
    words = list(parse_wordvh(inp.read_text()))
    max_addr = max((a for a, _ in words), default=0)
    depth_hint = max_addr + 1

    lines = []
    lines.append('`timescale 1ns/1ps')
    lines.append('')
    lines.append('// AUTO-GENERATED. Do not edit by hand.')
    lines.append(f'// Source: {inp.as_posix()}')
    lines.append('')
    lines.append('module imem_rom_gen #(')
    lines.append(f'    parameter integer DEPTH_WORDS = {max(depth_hint,1)},')
    lines.append('    parameter integer ADDR_LSB    = 2')
    lines.append(') (')
    lines.append('    input  wire [31:0] addr,')
    lines.append('    output wire [31:0] rdata')
    lines.append(');')
    lines.append('')
    lines.append('    reg [31:0] mem [0:DEPTH_WORDS-1];')
    lines.append('    integer i;')
    lines.append('    initial begin')
    lines.append("        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin")
    lines.append('            mem[i] = 32\'h0000_006f; // JAL x0,0 (park)')
    lines.append('        end')
    for a, v in words:
        lines.append(f"        mem[32'h{a:08x}] = 32'h{v:08x};")
    lines.append('    end')
    lines.append('')
    lines.append('    wire [$clog2(DEPTH_WORDS)-1:0] widx = addr[ADDR_LSB +: $clog2(DEPTH_WORDS)];')
    lines.append('    assign rdata = mem[widx];')
    lines.append('')
    lines.append('endmodule')
    lines.append('')

    outp.write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f'Usage: {sys.argv[0]} <in_word.vh> <out_imem.v>', file=sys.stderr)
        raise SystemExit(2)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
