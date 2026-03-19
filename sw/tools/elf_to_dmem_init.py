#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

WORD_RE = re.compile(r"^[0-9A-Fa-f]{8}$")


def run(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True)


def symbol_map(elf: Path, prefix: str) -> dict[str, int]:
    nm = shutil.which(f"{prefix}nm") or shutil.which("riscv64-unknown-elf-nm")
    if not nm:
        raise SystemExit("riscv nm not found")
    out = run([nm, "-n", str(elf)])
    m: dict[str, int] = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and all(c in "0123456789abcdefABCDEF" for c in parts[0]):
            m[parts[2]] = int(parts[0], 16)
    return m


def section_bin(elf: Path, section: str, prefix: str, tmpdir: Path) -> bytes:
    objcopy = shutil.which(f"{prefix}objcopy") or shutil.which("riscv64-unknown-elf-objcopy")
    if not objcopy:
        raise SystemExit("riscv objcopy not found")
    outp = tmpdir / f"{section.strip('.').replace('.', '_')}.bin"
    subprocess.run([objcopy, "-O", "binary", f"--only-section={section}", str(elf), str(outp)], check=True)
    return outp.read_bytes() if outp.exists() else b""


def bytes_to_words_le(data: bytes) -> list[int]:
    if not data:
        return []
    pad = (-len(data)) % 4
    if pad:
        data += b"\x00" * pad
    words: list[int] = []
    for i in range(0, len(data), 4):
        chunk = data[i:i+4]
        words.append(int.from_bytes(chunk, "little"))
    return words


def write_wordvh(words: list[int], outp: Path):
    toks = [f"{w:08x}" for w in words]
    lines = ["@00000000"]
    for i in range(0, len(toks), 4):
        lines.append(" ".join(toks[i:i+4]))
    outp.write_text("\n".join(lines) + "\n")


def write_verilog(words: list[int], src_hex: Path, outp: Path):
    depth = max(len(words), 4)
    lines = []
    lines.append("`timescale 1ns/1ps")
    lines.append("")
    lines.append("// AUTO-GENERATED. Do not edit by hand.")
    lines.append(f"// Source: {src_hex.as_posix()}")
    lines.append("")
    lines.append("module init_data_rom_gen #(")
    lines.append(f"    parameter integer DEPTH_WORDS = {depth}")
    lines.append(") (")
    lines.append("    input  wire [31:0] word_index,")
    lines.append("    output wire [31:0] rdata")
    lines.append(");")
    lines.append("")
    lines.append("    reg [31:0] mem [0:DEPTH_WORDS-1];")
    lines.append("    integer i;")
    lines.append("    initial begin")
    lines.append("        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin")
    lines.append("            mem[i] = 32'h0000_0000;")
    lines.append("        end")
    for i, w in enumerate(words):
        lines.append(f"        mem[32'h{i:08x}] = 32'h{w:08x};")
    lines.append("    end")
    lines.append("")
    lines.append("    wire [$clog2(DEPTH_WORDS)-1:0] ridx = word_index[$clog2(DEPTH_WORDS)-1:0];")
    lines.append("    assign rdata = mem[ridx];")
    lines.append("")
    lines.append("endmodule")
    lines.append("")
    outp.write_text("\n".join(lines))


def main():
    if len(sys.argv) not in (3, 4):
        print(f"Usage: {sys.argv[0]} <elf> <out_data.vh> [out_init_data_rom.v]", file=sys.stderr)
        raise SystemExit(2)

    elf = Path(sys.argv[1])
    out_hex = Path(sys.argv[2])
    out_v = Path(sys.argv[3]) if len(sys.argv) == 4 else None
    prefix = Path(shutil.which("riscv64-unknown-elf-objcopy") or "").name.replace("objcopy", "")

    syms = symbol_map(elf, prefix)
    ro_start = syms.get("__rodata_start", 0)
    ro_end   = syms.get("__rodata_end", ro_start)
    data_start = syms.get("__data_start", 0)
    data_end   = syms.get("__data_end", data_start)

    with tempfile.TemporaryDirectory() as td:
        tmpdir = Path(td)
        ro_bytes = section_bin(elf, ".rodata", prefix, tmpdir)
        data_bytes = section_bin(elf, ".data", prefix, tmpdir)

    ro_words = bytes_to_words_le(ro_bytes)
    data_words = bytes_to_words_le(data_bytes)

    words = [
        ro_start,
        len(ro_words),
        data_start,
        len(data_words),
        *ro_words,
        *data_words,
    ]

    write_wordvh(words, out_hex)
    if out_v is not None:
        write_verilog(words, out_hex, out_v)


if __name__ == "__main__":
    main()
