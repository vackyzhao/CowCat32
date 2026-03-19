# CowCat32 MMIO Manual

A practical MMIO reference for bring-up, baremetal software, and waveform debugging.

## Global Address Map

- `GPIO_BASE  = 0x10000000`
- `TIMER_BASE = 0x10001000`
- `DMA_BASE   = 0x10002000`
- `UART_BASE  = 0x10003000`
- `TOHOST_ADDR = 0x00001000`

`TOHOST_ADDR` is used by testbenches:
- write `1` => PASS
- write other non-zero => FAIL code

---

## GPIO

Base: `0x10000000`

| Offset | Address | Name | R/W | Description |
|---|---:|---|---|---|
| `0x00` | `0x10000000` | `GPIO_DATA` | R/W | Output data register |
| `0x04` | `0x10000004` | `GPIO_DIR`  | R/W | Direction register, `1=output`, `0=input` |
| `0x08` | `0x10000008` | `GPIO_IN`   | R   | Sampled input value |

### Notes
- Reset defaults:
  - `GPIO_DATA = 0`
  - `GPIO_DIR  = 0`
- Supports `wstrb`-masked writes.
- Undefined offsets:
  - read => `0`
  - write => no effect

### Example

```c
MMIO32(GPIO_DIR) = 0xffffffff;
MMIO32(GPIO_DATA) = 0x1;
```

---

## TIMER

Base: `0x10001000`

| Offset | Address | Name | R/W | Description |
|---|---:|---|---|---|
| `0x00` | `0x10001000` | `TIMER_CTRL` | R/W | Control register |
| `0x04` | `0x10001004` | `TIMER_MTIME_LO` | R/W | `mtime[31:0]` |
| `0x08` | `0x10001008` | `TIMER_MTIME_HI` | R/W | `mtime[63:32]` |
| `0x0C` | `0x1000100C` | `TIMER_CMP_LO` | R/W | `cmp[31:0]` |
| `0x10` | `0x10001010` | `TIMER_CMP_HI` | R/W | `cmp[63:32]` |
| `0x14` | `0x10001014` | `TIMER_STATUS` | R/W | Status / hit indication |

### Notes
- `mtime` increments when enabled.
- `cmp` can be programmed for compare-hit behavior.
- Common software helpers already exist in `sw/common/timer.c`.

---

## DMA

Base: `0x10002000`

| Offset | Address | Name | R/W | Description |
|---|---:|---|---|---|
| `0x00` | `0x10002000` | `DMA_SRC` | R/W | Source address |
| `0x04` | `0x10002004` | `DMA_DST` | R/W | Destination address |
| `0x08` | `0x10002008` | `DMA_LEN` | R/W | Transfer length in bytes |
| `0x0C` | `0x1000200C` | `DMA_CTRL` | W | Control |
| `0x10` | `0x10002010` | `DMA_STATUS` | R | Status |
| `0x14` | `0x10002014` | `DMA_ERRADDR` | R | Fault address |

### `DMA_CTRL`

| Bit | Name | Meaning |
|---|---|---|
| `0` | `START` | Write `1` to start |
| `1` | `CLR_DONE` | Write `1` to clear `DONE` |
| `2` | `CLR_ERR` | Write `1` to clear `ERR` |

### `DMA_STATUS`

| Bit | Name | Meaning |
|---|---|---|
| `0` | `BUSY` | DMA active |
| `1` | `DONE` | Transfer completed |
| `2` | `ERR`  | Error occurred |

### Alignment Rules
DMA is **32-bit aligned only**:
- `SRC[1:0] == 2'b00`
- `DST[1:0] == 2'b00`
- `LEN[1:0] == 2'b00`
- `LEN != 0`

Misaligned or zero-length starts are rejected.

### Example

```c
MMIO32(DMA_SRC) = 0x00001400;
MMIO32(DMA_DST) = 0x00001800;
MMIO32(DMA_LEN) = 64;
MMIO32(DMA_CTRL) = 1;
while ((MMIO32(DMA_STATUS) & (1u << 1)) == 0) {}
```

---

## UART

Base: `0x10003000`

| Offset | Address | Name | R/W | Description |
|---|---:|---|---|---|
| `0x00` | `0x10003000` | `UART_TXDATA` | W | Push one transmit byte from `wdata[7:0]` |
| `0x04` | `0x10003004` | `UART_RXDATA` | R | Pop one receive byte |
| `0x08` | `0x10003008` | `UART_STATUS` | R | Status register |
| `0x0C` | `0x1000300C` | `UART_BAUDDIV` | R/W | Clock cycles per serial bit |
| `0x10` | `0x10003010` | `UART_CTRL` | R/W | Control register |

### `UART_CTRL`

| Bit | Name | Meaning |
|---|---|---|
| `0` | `TX_EN` | Enable transmit |
| `1` | `RX_EN` | Enable receive |
| `2` | `LOOPBACK` | Internal loopback |
| `3` | `CLR_OVERRUN` | Write `1` to clear RX overrun |

### `UART_STATUS`

| Bit | Name | Meaning |
|---|---|---|
| `0` | `TX_BUSY` | TX shifter currently sending bits |
| `1` | `TX_FULL` | TX FIFO full |
| `2` | `TX_EMPTY` | TX FIFO empty |
| `3` | `RX_VALID` | RX FIFO contains readable data |
| `4` | `RX_FULL` | RX FIFO full |
| `5` | `OVERRUN` | RX overflow occurred |

### `UART_BAUDDIV`
- Meaning: number of system clock cycles per UART bit.
- Example values:
  - simulation: `8`
  - FPGA at 100MHz / 115200 baud: about `868`
- Reset/default baud divider is parameterized (`DEFAULT_BAUDDIV`).
- Software can still override it at runtime by writing `UART_BAUDDIV`.

### Common STATUS Values

| Value | Meaning |
|---:|---|
| `0x4` | `TX_EMPTY=1`, transmitter fully idle |
| `0x5` | `TX_EMPTY=1`, but `TX_BUSY=1` (last byte still shifting out) |
| `0x8` | `RX_VALID=1`, at least one byte ready |
| `0x18` | `RX_VALID=1` and `RX_FULL=1` |
| `0x20` | `OVERRUN=1` |

### Important Flush Note
`uart_flush()` does **not** zero FIFO RAM contents. It only waits until:
1. `TX_EMPTY = 1`
2. `TX_BUSY = 0`

So waveform RAM entries may still show historical bytes after flush; logical emptiness is determined by FIFO state (`count`, `TX_EMPTY`, `TX_BUSY`), not RAM contents.

### Example

```c
MMIO32(UART_BAUDDIV) = 8;
MMIO32(UART_CTRL) = 1;      // TX_EN
MMIO32(UART_TXDATA) = 'H';
```

Or with helpers:

```c
uart_init(8);
uart_putc('H');
uart_flush();
```

---

## CPU Address-Alignment Guidance

Use address low bits explicitly:
- 8-bit access: no extra alignment requirement
- 16-bit access: prefer `addr[0] == 1'b0`
- 32-bit access: require `addr[1:0] == 2'b00`

This is separate from DMA, which is strictly 32-bit aligned only.

---

## Testbench Result Signaling

`TOHOST_ADDR = 0x00001000`

| Written value | Meaning |
|---:|---|
| `0` | no action |
| `1` | PASS |
| non-zero, not `1` | FAIL code |
