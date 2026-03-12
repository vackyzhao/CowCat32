#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

python3 sim/rv32i_blackbox/gen_tb.py >/dev/null

TB_DIR="sim/rv32i_blackbox"

# Number of randomized memory-stall runs per TB (seeded)
RUNS_PER_TB=${RUNS_PER_TB:-5}

fails=0
passes=0

for tb in "$TB_DIR"/*_tb.v; do
  name="$(basename "$tb" .v)"
  echo "== $name =="

  iverilog -g2012 -o /tmp/rvtest.out \
    "$tb" \
    src/core/*.v src/control/*.v src/datapath/*.v

  for ((i=0;i<RUNS_PER_TB;i++)); do
    seed=$((1000 + i))
    if vvp -n /tmp/rvtest.out +seed=$seed >/tmp/rvtest.log 2>&1; then
      tail -n 1 /tmp/rvtest.log
      passes=$((passes+1))
    else
      echo "FAIL seed=$seed"
      tail -n 30 /tmp/rvtest.log
      fails=$((fails+1))
    fi
  done

  echo

done

echo "PASS_RUNS=$passes FAIL_RUNS=$fails"
exit $fails
