#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
RT=$ROOT/third_party/riscv-tests
ENV=$ROOT/sim/rv32i_blackbox/riscv_tests
OUT=$ENV/out
mkdir -p "$OUT"

JOBS=${JOBS:-8}
QUIET_TRACE=${QUIET_TRACE:-1}
NO_VCD=${NO_VCD:-1}

# 1) Build TB once
# Build TB once (reuse tb.out across jobs)
SKIP_TB_BUILD=0 NO_VCD=1 QUIET_TRACE=1 TRACE_OUT="$OUT/commit_build_only.log" "$ENV/run_one.sh" add >/dev/null 2>&1 || true

# 2) Collect tests
mapfile -t tests < <(cd "$RT/isa/rv32ui" && ls -1 *.S | sed 's/\.S$//')

# 3) Run in parallel (each job compiles its own ELF/HEX, but reuses tb.out)
run_one_job() {
  local t="$1"
  local log="$OUT/rv32ui-${t}.par.log"
  local trace="$OUT/commit_${t}.par.log"
  local seed=$(( (RANDOM << 16) ^ RANDOM ))
  SKIP_TB_BUILD=1 QUIET_TRACE="$QUIET_TRACE" NO_VCD="$NO_VCD" SEED="$seed" TRACE_OUT="$trace" \
    "$ENV/run_one.sh" "$t" >"$log" 2>&1
}
export -f run_one_job
export ROOT RT ENV OUT QUIET_TRACE NO_VCD

# Run all tests; do not stop early on failures.
set +e
printf '%s\n' "${tests[@]}" | xargs -P "$JOBS" -I{} bash -lc 'run_one_job "$@"; exit 0' _ {}
set -e

# 4) Summary
: > "$OUT/rv32ui_parallel_summary.txt"
pass=0
fail=0
for t in "${tests[@]}"; do
  log="$OUT/rv32ui-${t}.par.log"
  if grep -q "PASS" "$log"; then
    echo "$t PASS" >> "$OUT/rv32ui_parallel_summary.txt"
    pass=$((pass+1))
  else
    echo "$t FAIL" >> "$OUT/rv32ui_parallel_summary.txt"
    fail=$((fail+1))
  fi
 done

echo "DONE(parallel): $pass passed, $fail failed"
