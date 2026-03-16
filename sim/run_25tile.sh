#!/usr/bin/env bash
# run_25tile.sh — compile and simulate the 25-tile functional test
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
SIM="$REPO/sim"
NOD="$REPO/rtl/nod"
ADAP="$REPO/rtl/noc_adapter"

echo "=== Compiling 25-tile functional testbench ==="
iverilog -g2001 -I"$NOD" \
    -o "$SIM/25tile.vvp" \
    "$SIM/tb_25tile.v" \
    "$NOD/NoD.v" "$NOD/router.v" "$NOD/x_router.v" "$NOD/y_router.v" \
    "$NOD/alloc_two.v" "$NOD/alloc_three.v" "$NOD/link_two.v" "$NOD/link_three.v" \
    "$NOD/mtx_arbiter.v" "$NOD/fifo_NoD_wrapper.v" "$NOD/SyncFIFO_RTL.v" \
    "$ADAP/flit_tx.v" "$ADAP/flit_rx.v" "$ADAP/noc_adapter.v"

echo "=== Running simulation ==="
vvp "$SIM/25tile.vvp"
