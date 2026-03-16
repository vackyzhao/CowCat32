#!/usr/bin/env bash
# run_coverage.sh — compile and run the coverage testbench
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
SIM="$REPO/sim"
NOD="$REPO/rtl/nod"
ADAP="$REPO/rtl/noc_adapter"

echo "=== Compiling coverage testbench ==="
iverilog -g2001 -I"$NOD" \
    -o "$SIM/cov.vvp" \
    "$SIM/tb_coverage.v" \
    "$SIM/coverage_monitor.v" \
    "$NOD/NoD.v" "$NOD/router.v" "$NOD/x_router.v" "$NOD/y_router.v" \
    "$NOD/alloc_two.v" "$NOD/alloc_three.v" "$NOD/link_two.v" "$NOD/link_three.v" \
    "$NOD/mtx_arbiter.v" "$NOD/fifo_NoD_wrapper.v" "$NOD/SyncFIFO_RTL.v" \
    "$ADAP/flit_tx.v" "$ADAP/flit_rx.v" "$ADAP/noc_adapter.v"

echo "=== Running coverage simulation ==="
vvp "$SIM/cov.vvp"
