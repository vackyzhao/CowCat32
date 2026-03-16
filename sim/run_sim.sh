#!/usr/bin/env bash
# run_sim.sh — compile and simulate the LobsterPawn integration testbench
# Usage: bash sim/run_sim.sh [--wave]

set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
SIM_DIR="$REPO/sim"
RTL_NOD="$REPO/rtl/nod"
RTL_ADAP="$REPO/rtl/noc_adapter"

WAVE_FLAG=""
if [[ "$1" == "--wave" ]]; then
    WAVE_FLAG="-DVCD_DUMP"
fi

echo "=== Compiling LobsterPawn integration testbench ==="
iverilog -g2001 $WAVE_FLAG \
    -I"$RTL_NOD" \
    -o "$SIM_DIR/sim.vvp" \
    "$SIM_DIR/tb_lobsterpawn.v" \
    "$RTL_NOD/NoD.v" \
    "$RTL_NOD/router.v" \
    "$RTL_NOD/x_router.v" \
    "$RTL_NOD/y_router.v" \
    "$RTL_NOD/alloc_two.v" \
    "$RTL_NOD/alloc_three.v" \
    "$RTL_NOD/link_two.v" \
    "$RTL_NOD/link_three.v" \
    "$RTL_NOD/mtx_arbiter.v" \
    "$RTL_NOD/fifo_NoD_wrapper.v" \
    "$RTL_NOD/SyncFIFO_RTL.v" \
    "$RTL_ADAP/flit_tx.v" \
    "$RTL_ADAP/flit_rx.v" \
    "$RTL_ADAP/noc_adapter.v"

echo "=== Running simulation ==="
vvp "$SIM_DIR/sim.vvp"
