# LobsterPawn

A multi-core SoC integrating multiple **CowCat32** RISC-V CPU tiles
interconnected via the **NoD** (Network-on-Die) 5×5 mesh NoC.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      LobsterPawn SoC                    │
│                                                         │
│  ┌──────────────┐      ┌─────────────────────────┐     │
│  │  CPU Tile 0  │      │                         │     │
│  │  (CowCat32)  │◄────►│                         │     │
│  │  + NoC Adpt  │      │   NoD  (5×5 XY Mesh)   │     │
│  └──────────────┘      │                         │     │
│                         │   25 local ports        │     │
│  ┌──────────────┐       │   130-bit flit width    │     │
│  │  CPU Tile 1  │◄─────►│   valid/ready handshake │     │
│  │  (CowCat32)  │       │                         │     │
│  │  + NoC Adpt  │       └─────────────────────────┘     │
│  └──────────────┘                                        │
│         ...  (up to 25 tiles, one per NoD local port)   │
└─────────────────────────────────────────────────────────┘
```

## Key Design Decisions

- **One CowCat32 tile per NoD local port** — tile at (X,Y) uses port (X,Y)
- **NoC adapter** bridges CowCat32's memory-mapped bus ↔ NoD flit interface
- **Address map**: NOC region `0x0000_3000–0x0000_3FFF` is added to
  the memory arbiter; CPU writes to this region generate NoD packets
- **Flit packetisation**: each 32-bit CPU word → 2-flit packet (HEAD + TAIL)
- **Routing**: destination encoded in bits [11:8] of the NOC address (X[2:0] and Y[2:0])

## Directory Structure

```
rtl/
  nod/          — NoD RTL (verbatim from Multi-NoC-main-claw)
  cpu_tile/     — CowCat32 RTL (verbatim from CowCat32)
  noc_adapter/  — NoC adapter: CowCat32 bus ↔ NoD flit bridge
    noc_adapter.v      — top adapter module
    flit_tx.v          — TX path: bus write → flit injection
    flit_rx.v          — RX path: incoming flits → bus read response
  top/
    lobsterpawn_top.v  — SoC top-level (2-tile demo)
    lobsterpawn_2tile_tb.v — integration testbench
sim/            — simulation output and run scripts
docs/           — architecture notes and memory map
scripts/        — helper scripts
```

## Memory Map (per tile)

| Region | Base         | End          | Peripheral      |
|--------|--------------|--------------|-----------------|
| ITCM   | 0x0000_0000  | 0x0000_0FFF  | Instruction TCM |
| DTCM   | 0x0000_0000  | 0x0000_0FFF  | Data TCM        |
| GPIO   | 0x0000_1000  | 0x0000_1FFF  | GPIO            |
| RTC    | 0x0000_2000  | 0x0000_2FFF  | Real-time clock |
| NOC    | 0x0000_3000  | 0x0000_3FFF  | NoC send/recv   |

### NOC Address Sub-mapping

| Offset | Access | Description                          |
|--------|--------|--------------------------------------|
| 0x000  | W      | Transmit data register (32-bit payload) |
| 0x004  | W      | Transmit destination: {DST_X[2:0], DST_Y[2:0]} |
| 0x008  | R      | Receive data register (32-bit payload) |
| 0x00C  | R      | Receive status: {rx_valid[0]} |
| 0x010  | W      | Receive acknowledge (clears rx buffer) |

## Build Status

See git log for integration milestones.
