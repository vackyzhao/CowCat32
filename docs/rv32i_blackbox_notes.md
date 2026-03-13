# RV32I blackbox (Icarus) – Notes & Change Log

This doc records why we changed the fuzz/TB/CPU, what each change was meant to fix, and current status.

## Baseline harness
- Testbenches use a unified `dmem_model` with `mem_req/mem_we/mem_re` handshake, `dm_ack` pulse, and random latency.
- Reference model executes RV32I subset in Python and compares architectural regs + a memory window.

## Key commits / changes

### 1) Unified data memory model across TBs
- Commit: `adcd598`
- Added `sim/tb/dmem_model.v` and compiled it into all TBs.
- Goal: all TBs share identical `mem_req/we/re + ack + random delay` behavior.

### 2) Instrumentation for path divergence
- Commit: `d457b57`
- Added `pc_wb` and `TRACE_WB/TRACE_CTRL` printing + `analyze_paths.py`.
- Goal: align DUT vs reference at **WB commit**, not EX.

### 3) HOLD semantics for memory ops
- Commit: `aadc201`
- LOAD/STORE: `hold = ~(im_ack & dm_ack)`; others: `hold = ~im_ack`.
- With TB `im_ack=1`, reduces to “wait for dm_ack”, but keeps semantics consistent.

### 4) Pipeline register priority: hold > flush
- Commit: `222d7c1`
- `pp_register(_inst)`: changed priority to `reset > hold > flush > update`.
- Goal: prevent flush from clobbering pipeline regs during stalls.

### 5) Ctrl-fuzz control-flow correctness fixes
- Commit: `3b9c197`
- Constrained control-flow targets to stay within the generated program; added a terminator loop.
- Goal: avoid “ROM fall-through / ref stops but DUT keeps running” false mismatches.

### 6) Fix invalid JALR immediate generation (imm12)
- Commit: `7cf4a28` then refined into A-mode in `3d940ab`.
- Problem: generated `jalr x0, 2048(x0)` etc. JALR imm is signed 12-bit => 2048 encodes as -2048.
- Result: reference jumped to `0xFFFF_F800` and stopped; DUT continued => false divergence.
- Fix: only generate encodable absolute imm12 targets (A-mode), otherwise emit `nop`.

### 7) Start testing JALR “mode B”
- Commit: `2ea2dab`
- Generate `addi ra, x0, tgt; jalr x0, 0(ra)`.
- Goal: stress rs1 hazards/forwarding and hold+redirect interaction in a more realistic way.

## Current status

### Ctrl-fuzz mode A (absolute jalr imm12)
- `CTRL=1 SEEDS=300 LEN=500`: **PASS_RUNS=300 FAIL_RUNS=0** (after `3d940ab`).

### Ctrl-fuzz mode B (addi+jalr)
- `CTRL=1 SEEDS=100 LEN=500`: currently seeing non-zero fails (≈20/100 in the first run).
- These are considered **real** CPU/control bugs to investigate (not test invalidity).

## Next debugging plan (mode B)
1. Use failing seeds to find the first WB divergence.
2. Focus on windows where `hold` and `pc_sel=10` (JAL/JALR) are adjacent.
3. Check: rs1 forwarding into JALR, redirect/flush timing during stalls, and whether wrong-path instructions commit.
