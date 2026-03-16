# LobsterPawn Memory Map & Interface Specification

## Per-Tile Address Map

Each CowCat32 tile sees the following flat address space:

| Region | Base         | End          | Size  | Peripheral      |
|--------|--------------|--------------|-------|-----------------|
| ITCM   | 0x0000_0000  | 0x0000_0FFF  | 4 KB  | Instruction TCM |
| DTCM   | 0x0000_0000  | 0x0000_0FFF  | 4 KB  | Data TCM        |
| GPIO   | 0x0000_1000  | 0x0000_1FFF  | 4 KB  | GPIO controller |
| RTC    | 0x0000_2000  | 0x0000_2FFF  | 4 KB  | Real-time clock |
| **NOC**| **0x0000_3000**  | **0x0000_3FFF**  | **4 KB**  | **NoC send/receive** |

## NOC Register Map (offset from 0x0000_3000)

| Offset | Name        | R/W | Width | Description |
|--------|-------------|-----|-------|-------------|
| 0x000  | NOC_TX_DATA | W   | 32    | Payload to send (latched on write) |
| 0x004  | NOC_TX_DST  | W   | 32    | Destination: bits[5:3]=DST_X, bits[2:0]=DST_Y |
| 0x008  | NOC_RX_DATA | R   | 32    | Received payload (valid when NOC_RX_STATUS[0]=1) |
| 0x00C  | NOC_RX_STATUS | R | 32   | bit[0]: rx_valid; bit[1]: tx_busy |
| 0x010  | NOC_RX_ACK  | W   | 32    | Write any value to dequeue receive buffer |

## Flit Encoding

A CPU NOC transaction generates a 2-flit packet on the NoD:

```
Flit 0 (HEAD):  [129:128]=2'b00  [127:26]=payload[101:0]=0  
                [25:20]=RTID={DST_X,DST_Y}
                [19:16]=SCID=0   [15:12]=DCID=0
                [11:6] =SRID={SRC_X,SRC_Y}
                [5:0]  =DRID={DST_X,DST_Y}

Flit 1 (TAIL):  [129:128]=2'b10  [127:96]=payload[31:0]  [95:0]=0
```

The 32-bit CPU payload travels in the TAIL flit [127:96].

## NoC Adapter Interface (noc_adapter ↔ memory_arbiter)

The noc_adapter presents the same interface as other peripherals in the
CowCat32 memory arbiter:

```
Inputs from arbiter:
  noc_addr  [31:0]   — address (offset from NOC_BASE)
  noc_wdata [31:0]   — write data
  noc_rw             — 1=write, 0=read
  noc_we             — chip-select (asserted when addr in NOC range)

Outputs to arbiter:
  noc_rdata [31:0]   — read data
  noc_ready          — transaction complete
```

## Inter-Tile Routing

Tile at grid position (X, Y) uses NoD local port (X, Y).

To send to tile (X', Y'), the CPU writes:
  1. `NOC_TX_DATA` ← payload
  2. `NOC_TX_DST`  ← {X'[2:0], Y'[2:0]}  (bits [5:3] and [2:0])

The adapter then injects a 2-flit packet. The NoD routes it via XY
dimension-order routing to the destination local port, where the
receiving tile's adapter captures it.
