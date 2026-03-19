#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${OUT:-$ROOT/sim/soc/out}
mkdir -p "$OUT"

SRC=${1:-${SRC:-$ROOT/sim/soc/gpio_timer.S}}
LD=$ROOT/sim/soc/soc_link.ld

BASE=$(basename "$SRC")
BASE=${BASE%.*}

ELF=$OUT/${BASE}.elf
TMP=$OUT/${BASE}.objcopy.vh
HEX=$OUT/${BASE}.vh
IMEMV=$OUT/${BASE}.imem.v
DATAVH=$OUT/${BASE}.data.vh
DATAROMV=$OUT/${BASE}.init_data_rom.v

riscv64-unknown-elf-gcc \
  -march=rv32i -mabi=ilp32 \
  -static -mcmodel=medany -fvisibility=hidden \
  -nostdlib -nostartfiles \
  -T"$LD" \
  "$SRC" -o "$ELF"

riscv64-unknown-elf-objcopy -O verilog --verilog-data-width=4 "$ELF" "$TMP"

python3 - "$TMP" "$HEX" <<'PY'
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
        a=int(line[1:],16)
        out.append(f"@{a>>2:08x}")
        continue
    toks=line.split()
    out.append(' '.join(bswap32(t) if hex8.match(t) else t for t in toks))

dst.write_text('\n'.join(out)+"\n")
PY

python3 "$ROOT/sw/tools/wordvh_to_imem_v.py" "$HEX" "$IMEMV"
python3 "$ROOT/sw/tools/elf_to_dmem_init.py" "$ELF" "$DATAVH" "$DATAROMV"

echo "Built: $HEX"
echo "Built: $IMEMV"
echo "Built: $DATAVH"
echo "Built: $DATAROMV"
