#!/usr/bin/env bash
set -euo pipefail

TEST=${1:-add}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RT=$ROOT/third_party/riscv-tests
ENV=$ROOT/sim/rv32i_blackbox/riscv_tests
OUT=$ROOT/sim/rv32i_blackbox/riscv_tests/out
mkdir -p "$OUT"

SRC="$RT/isa/rv32ui/${TEST}.S"
if [ ! -f "$SRC" ]; then
  echo "No such test: $SRC" >&2
  exit 2
fi

ELF="$OUT/rv32ui-${TEST}.elf"
HEX="$OUT/rv32ui-${TEST}.vh"
IMEMV="$OUT/rv32ui-${TEST}.imem.v"

# Compile
riscv64-unknown-elf-gcc \
  -march=rv32i -mabi=ilp32 \
  -static -mcmodel=medany -fvisibility=hidden \
  -nostdlib -nostartfiles \
  -I"$ENV" \
  -I"$RT/isa/macros/scalar" \
  -I"$RT/isa" \
  -T"$ENV/link.ld" \
  "$SRC" -o "$ELF"

# Convert to verilog readmemh format (32-bit words)
# NOTE: objcopy verilog output is byte-swapped for our 32-bit instruction fetch.
# We post-process to little-endian words so mem[word] matches the CPU's 32-bit inst.
TMP_HEX="$OUT/rv32ui-${TEST}.objcopy.vh"
riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=4 "$ELF" "$TMP_HEX"

python3 - "$TMP_HEX" "$HEX" <<'PY'
import re, sys
from pathlib import Path
src=Path(sys.argv[1])
dst=Path(sys.argv[2])
hex8=re.compile(r"^[0-9A-Fa-f]{8}$")

def bswap32(s:str)->str:
    v=int(s,16)
    b0=(v>>0)&0xff
    b1=(v>>8)&0xff
    b2=(v>>16)&0xff
    b3=(v>>24)&0xff
    w=(b0<<24)|(b1<<16)|(b2<<8)|b3
    return f"{w:08x}"

out=[]
for line in src.read_text().splitlines():
    line=line.strip()
    if not line:
        continue
    if line.startswith('@'):
        # objcopy verilog uses byte addresses in '@'. Our memories are word-indexed.
        a=int(line[1:],16)
        if a % 4 != 0:
            # Keep odd addresses (shouldn't happen with --verilog-data-width=4)
            # but still map by floor-div.
            pass
        out.append(f"@{a>>2:08x}")
        continue
    toks=line.split()
    out.append(' '.join(bswap32(t) if hex8.match(t) else t for t in toks))

dst.write_text('\n'.join(out)+"\n")
PY

python3 "$ROOT/sw/tools/wordvh_to_imem_v.py" "$HEX" "$IMEMV"

# Build and run TB
TB="$ENV/rv32i_riscvtests_tb.v"
if [ "${SKIP_TB_BUILD:-0}" != "1" ]; then
  iverilog -g2012 -o "$OUT/tb.out" \
    "$TB" \
    "$ROOT/src/core"/*.v "$ROOT/src/control"/*.v "$ROOT/src/datapath"/*.v \
    "$ROOT/sim/tb"/*.v
fi

TRACE_OUT=${TRACE_OUT:-/tmp/commit.log}
QUIET=${QUIET_TRACE:-1}
args=(+hex="$HEX" +trace="$TRACE_OUT")
if [ -n "${SEED:-}" ]; then args+=("+seed=$SEED"); fi
if [ "$QUIET" = "1" ]; then args+=(+quiet_trace); fi
if [ "${NO_VCD:-0}" = "1" ]; then args+=(+novcd); fi
if [ -n "${VCD_OUT:-}" ]; then args+=("+vcd=$VCD_OUT"); fi

vvp -n "$OUT/tb.out" "${args[@]}"
