#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

SEEDS=${SEEDS:-50}
SEED0=${SEED0:-1000}
LEN=${LEN:-300}
MEM_BASE=${MEM_BASE:-0x100}
MEM_WORDS=${MEM_WORDS:-64}

WORK_DIR=${WORK_DIR:-/tmp/rv32i_fuzz}
FAIL_DIR=${FAIL_DIR:-sim/rv32i_blackbox/fails}

mkdir -p "$WORK_DIR" "$FAIL_DIR"

passes=0
fails=0

for ((i=0;i<SEEDS;i++)); do
  seed=$((SEED0 + i))
  name="fuzz_straight_seed${seed}"
  tb="$WORK_DIR/${name}_tb.v"
  asm="$WORK_DIR/${name}.S"
  hex="$WORK_DIR/${name}.hex"
  log="$WORK_DIR/${name}.log"

  ctrl_args=()
  if [ "${CTRL:-0}" = "1" ]; then
    ctrl_args+=(--ctrl)
  fi

  python3 sim/rv32i_blackbox/fuzz.py \
    --seed "$seed" --len "$LEN" --name fuzz_straight \
    --out "$tb" --asm-out "$asm" --hex-out "$hex" \
    --mem-base "$MEM_BASE" --mem-words "$MEM_WORDS" \
    "${ctrl_args[@]}" >/dev/null

  if iverilog -g2012 -o /tmp/rvfuzz.out \
      "$tb" \
      sim/tb/*.v \
      src/core/*.v src/control/*.v src/datapath/*.v \
      >/dev/null 2>&1; then

    if vvp -n /tmp/rvfuzz.out +seed=$seed >"$log" 2>&1; then
      tail -n 1 "$log"
      passes=$((passes+1))
    else
      echo "FAIL seed=$seed"
      tail -n 40 "$log"
      outdir="$FAIL_DIR/$name"
      mkdir -p "$outdir"
      cp -a "$tb" "$asm" "$hex" "$log" "$outdir/"
      fails=$((fails+1))
    fi
  else
    echo "FAIL: compile seed=$seed"
    outdir="$FAIL_DIR/$name"
    mkdir -p "$outdir"
    cp -a "$tb" "$asm" "$hex" "$outdir/"
    fails=$((fails+1))
  fi

done

echo "PASS_RUNS=$passes FAIL_RUNS=$fails"
exit $fails
