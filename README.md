# CowCat32 — RV32I 五级流水处理器（使用手册）

本项目实现了一个 **RV32I**（32-bit base integer）五级流水 RISC‑V 处理器，并提供了基于 `riscv-tests` 的回归测试脚本与一个自包含 testbench，便于快速验证与二次开发。

> 说明：当前处理器 **不实现 misaligned（非对齐）访存**（例如 `lw x?, 1(x?)`），相关测试（如 `ma_data`）失败不视为 bug。

---

## 目录结构（你最常用的部分）

- `src/`：RTL 主源码
  - `src/core/`：流水线各级模块与顶层 `SynCPU.v`
  - `src/control/`：控制单元（译码/流水控制/前递/暂停等）
  - `src/datapath/`：ALU、寄存器堆、立即数生成、流水寄存器等
  - `src/periph/`：GPIO/TIMER/DMA/UART 等外设
  - `src/soc/`：SoC 顶层与总线仲裁

- `sim/`：仿真
  - `sim/soc/`：SoC bring-up 仿真与自检程序（.S）
  - `sim/periph/`：外设单元测试（不带 CPU）
  - `sim/rv32i_blackbox/riscv_tests/`：rv32ui 回归测试脚本与 testbench

- `sw/`：裸机软件工具链（C/asm）
  - `sw/common/`：crt0/linker script + 外设 C driver
  - `sw/examples/`：示例程序（可生成 .elf/.vh/.imem.v）

- `third_party/`：本地第三方依赖（**不入 git**，见 `third_party/README.md`）

---

## 1. 顶层模块：SynCPU 接口说明

顶层模块：`src/core/SynCPU.v`

```verilog
module SynCPU(
    input  wire        clk,
    input  wire        rst,

    // instruction memory
    output wire [31:0] im_addr,
    input  wire [31:0] im_inst,
    input  wire        im_ack,

    // data memory
    output wire [31:0] dm_addr,
    output wire [31:0] dm_store,
    input  wire [31:0] dm_load,
    output wire [3:0]  dm_ctl,
    input  wire        dm_ack,

    // memory request qualifiers (MA stage)
    output wire        mem_req,
    output wire        mem_we,
    output wire        mem_re,

    // commit trace (WB stage)
    output wire        trace_valid,
    output wire [31:0] trace_pc,
    output wire [31:0] trace_inst,
    output wire [4:0]  trace_rd,
    output wire [31:0] trace_rd_data
);
```

### 1.1 时钟与复位

- `clk`：全局时钟，上升沿触发。
- `rst`：复位信号（设计里多数寄存器是 `negedge rst` 复位/或同步复位混用）。测试环境中通常先拉低，再拉高开始执行。

### 1.2 指令存储器接口（IMEM）

- `im_addr`（output）：**字节地址**。处理器每次取指以 32-bit 为单位，默认按 `pc + 4` 前进。
- `im_inst`（input）：当前 `im_addr` 对应的 32-bit 指令。
- `im_ack`（input）：指令侧握手/ready。

**约束与建议：**

- 当 `im_ack=1` 时，`im_inst` 必须有效。
- 当 `im_ack=0` 时，处理器会通过 `hold` 机制暂停流水线；外部最好保持 `im_inst` 稳定（或至少在 `im_ack` 重新为 1 前给出正确指令）。

> 仿真 testbench 里通常 `im_ack` 恒为 1（即无取指等待）。

### 1.3 数据存储器接口（DMEM）

- `mem_req`：MA 级发起一次数据访存请求（load/store）。
- `mem_we`：store 请求。
- `mem_re`：load 请求。

- `dm_addr`（output）：**字节地址**。
- `dm_store`（output）：store 写数据（注意：已经根据 `dm_addr[1:0]` 做了 byte lane 对齐移位，见后文）。
- `dm_load`（input）：load 读数据（整 32-bit word）。
- `dm_ctl`（output）：store 写掩码（byte enable），`dm_ctl[0]` 对应最低有效字节。
- `dm_ack`（input）：数据侧握手/ready。

**对齐/掩码规则（重要）：**

- 处理器输出的 `dm_ctl` 会根据 `dm_addr[1:0]` 自动左移对齐（在 `SynCPU.v` 内部处理）。
- 处理器输出的 `dm_store` 也会根据 `dm_addr[1:0]` 左移，把要写入的 byte/half/word 放到对应 lane。

因此，外部内存模型可以按如下方式写入：

- word index：`widx = dm_addr >> 2`
- byte enable：`dm_ctl[3:0]`
- write data：`dm_store`

对每个 byte 做 mask 写入即可。

---

## 2. 内存握手与暂停（hold）时序

处理器使用 `im_ack` / `dm_ack` 驱动暂停控制：

- 对 **LOAD/STORE**：当 `dm_ack=0` 时流水线会暂停（`hold=1`），直到 `dm_ack=1`。
- 对 **非访存指令**：通常只看 `im_ack`（在多数 testbench 中 `im_ack=1`）。

### 2.1 推荐的握手语义

- 当发出请求（`mem_req=1` 且 `mem_we|mem_re=1`）时，外部内存可以在任意若干周期后将 `dm_ack` 置 1（可以是单周期脉冲）。
- **当 `dm_ack=1` 的那个周期**：
  - 若是 load：`dm_load` 必须对应当前请求的返回数据。
  - 若是 store：外部内存应在该次请求语义上“完成写入”（也可以在更早的 accept-time 就写入，但要保证对处理器可见性一致）。

> 项目自带的 testbench 为了便于 fuzz/黑盒验证，采用了随机延迟并在 accept-time 提前提交 store；这是为了降低对 ack 时序细节的敏感性。

### 2.2 简化时序图（概念性）

以一次 `lw` 为例：

```
cycle N   : mem_req=1 mem_re=1 dm_addr=... dm_ack=0  -> hold=1
cycle N+1 : mem_req=1 mem_re=1 dm_addr=... dm_ack=0  -> hold=1
...
cycle N+k : mem_req=1 mem_re=1 dm_addr=... dm_ack=1 dm_load=DATA -> hold=0
cycle N+k+1 : pipeline continues
```

---

## 3. 对齐访存与“不支持非对齐访存”说明

- 支持：
  - `lb/lbu/lh/lhu/lw`（对齐地址；允许 base 非对齐但最终有效地址对齐）
  - `sb/sh/sw`（对齐地址）
- 不支持：
  - `lh/lhu/lw` 等在 **地址非对齐** 情况下的正确拼接行为（`ma_data` 即专门测这个）。

如果你希望未来实现非对齐访存，一般需要：
- 访问跨 word 的拼接（load）
- 拆分成多个 store/或做 read‑modify‑write（store）
- 或者实现异常/trap（更符合 RISC‑V 特权架构，但这需要 CSR/异常框架）。

---

## 4. 回归测试（rv32ui）使用方法

测试脚本位于：`sim/rv32i_blackbox/riscv_tests/`

> 注意：回归测试依赖 `third_party/riscv-tests/`（本地依赖，不入 git）。如缺失请按 `third_party/README.md` 拉取。

### 4.1 单个测试

```bash
cd sim/rv32i_blackbox/riscv_tests
./run_one.sh add
```

常用环境变量：

- `TRACE_OUT=/tmp/commit_add.log`：写出提交（WB）trace
- `QUIET_TRACE=1`：减少 console 输出
- `NO_VCD=1`：禁用 VCD（更快、也适合并行）
- `SKIP_TB_BUILD=1`：跳过 iverilog 编译（重复跑时更快）

### 4.2 并行跑完整 rv32ui（推荐，利用多核）

```bash
cd sim/rv32i_blackbox/riscv_tests
JOBS=8 NO_VCD=1 QUIET_TRACE=1 ./run_all_parallel.sh

# 结果汇总：
cat out/rv32ui_parallel_summary.txt
```

> 并行跑时强烈建议 `NO_VCD=1`，否则所有用例抢写同一个 VCD 文件会冲突且很慢。

---

## 5. Testbench（rv32i_riscvtests_tb）说明

文件：`sim/rv32i_blackbox/riscv_tests/rv32i_riscvtests_tb.v`

特性：
- 统一内存 `mem[]` 同时作为指令与数据存储
- 数据侧随机延迟 ack
- 监视对 `tohost`（`0x0000_1000`）的写入：
  - 写 `1` 判 PASS
  - 写其它值判 FAIL

VCD 控制：
- `+novcd`：禁用 VCD
- `+vcd=<path>`：指定 VCD 输出路径

---

## 6. SoC 基础外设（soc_top_basic）与 MMIO 地址映射

> 默认 IMEM/DMEM 均为 **2048 words（8KiB）**，更适合 FPGA 推断 BRAM。
> 如需更大容量，可通过参数覆写（`IMEM_WORDS` / `SRAM_WORDS`）。

本仓库除了 `SynCPU` 核心外，还提供一个用于 bring-up/外设联调的最小 SoC：

- 顶层：`src/soc/soc_top_basic.v`
- IMEM：独立 ROM（`src/mem/imem_rom.v`），**从地址 0x0000_0000 开始取指**
- DMEM：独立 SRAM（`src/mem/sram_1rw.v`），默认 512KiB
- MMIO：`0x1000_0000 ~ 0x1000_FFFF`（64KiB window），按 4KiB 页译码

> `soc_top_basic` 主要用于外设验证；`sim/rv32i_blackbox/riscv_tests/` 的 rv32ui 回归仍然是“统一内存 TB”。

### 6.1 地址空间（DMEM 侧）

| 区域 | 地址范围 | 说明 |
|---|---:|---|
| DMEM SRAM | `0x0000_0000 ~ 0x0000_1FFF` | 默认 8KiB（2048 words）数据内存（注意：当前模型未做越界检查，地址超范围会被截断/回卷） |
| MMIO window | `0x1000_0000 ~ 0x1000_FFFF` | 外设寄存器区（GPIO/TIMER/DMA/UART…） |
| tohost | `0x0000_1000` | SoC TB 用于 PASS/FAIL 的写地址（写 1 = PASS，写其它值 = FAIL code） |

### 6.2 GPIO（`GPIO_BASE = 0x1000_0000`）

寄存器（offset）：

> 说明：所有外设子模块内部地址均为 **4KiB 页内 offset（12-bit）**，由 SoC fabric 完成页译码后再传入子模块，便于调试与综合推断。

| offset | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `0x00` | `DATA` | R/W | 输出数据寄存器（读回为 `gpio_out`） |
| `0x04` | `DIR`  | R/W | 方向寄存器：1=output，0=input |
| `0x08` | `IN`   | R   | 输入采样（`gpio_in`） |

使用示例（汇编/伪码）：

```asm
# base = 0x1000_0000
lui  t0, 0x10000
li   t1, -1
sw   t1, 4(t0)      # DIR = 0xFFFF_FFFF
li   t1, 0x12345678
sw   t1, 0(t0)      # DATA = 0x12345678
lw   t2, 8(t0)      # IN
```

### 6.3 Timer（`TIMER_BASE = 0x1000_1000`，1MHz `mtime`）

实现：`src/periph/timer_mmio.v`

- 内部 `mtime` 是 64-bit，每 **1us** 自增 1（由 `CLK_HZ` 分频得到 1MHz tick；当前 SoC 默认 `CLK_HZ=100MHz`）
- `mtime` 是只读；可写 `CTRL` 与 `CMP_LO/HI`
- **原子读机制（硬件 latch）**：读 `MTIME_HI` 会锁存快照；随后读 `MTIME_LO` 会返回快照的低 32 位（避免 HI/LO 不一致）

寄存器（offset）：

| offset | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `0x00` | `CTRL` | R/W | bit0 enable，bit1 clear（写 1 清零 `mtime` 与分频计数） |
| `0x04` | `MTIME_LO` | R | 低 32（若刚读过 HI，则返回锁存快照 LO） |
| `0x08` | `MTIME_HI` | R | 高 32（同时锁存 64-bit 快照） |
| `0x0C` | `CMP_LO` | R/W | 比较值低 32 |
| `0x10` | `CMP_HI` | R/W | 比较值高 32 |
| `0x14` | `STATUS` | R | bit0 = (`mtime >= mtimecmp`) |

推荐读 64-bit 时间：

```c
uint64_t mtime;
uint32_t hi = MMIO32(TIMER_BASE + 0x08);
uint32_t lo = MMIO32(TIMER_BASE + 0x04);
mtime = ((uint64_t)hi << 32) | lo;
```

### 6.4 DMA（`DMA_BASE = 0x1000_2000`，仅 32-bit word copy）

实现：`src/periph/dma_mmio.v`

- 仅支持 32-bit 搬运：`SRC/DST` 需 4-byte 对齐，`LEN` 需为 4 的倍数
- DMA 作为第二个总线 master 通过 `src/soc/bus_arb_2m.v` 与 CPU 共享 DMEM 总线

寄存器（offset）：

| offset | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `0x00` | `SRC` | R/W | 源地址 |
| `0x04` | `DST` | R/W | 目的地址 |
| `0x08` | `LEN` | R/W | 字节数（4 对齐） |
| `0x0C` | `CTRL` | W | bit0 START(W1)，bit1 CLR_DONE(W1)，bit2 CLR_ERR(W1) |
| `0x10` | `STATUS` | R | bit0 BUSY，bit1 DONE，bit2 ERR |
| `0x14` | `ERRADDR` | R | 出错地址（best-effort） |

使用流程：
1) 写 `SRC/DST/LEN` → 2) 写 `CTRL.START=1` → 3) 轮询 `STATUS.DONE` → 4) （可选）清 `DONE/ERR`

### 6.5 UART（`UART_BASE = 0x1000_3000`，8N1，TX/RX FIFO）

实现：`src/periph/uart_mmio.v`

- 8N1（start + 8 data LSB-first + stop）
- `BAUDDIV`：每个 bit 的 clk 周期数（例如 100MHz/115200≈868）
- TX FIFO + RX FIFO（默认深度 64）
- UART 默认复位分频 `DEFAULT_BAUDDIV` 可参数化，软件也可运行时改写 `UART_BAUDDIV`
- 支持 `LOOPBACK`（bit-level：`tx -> rx`）用于自测

寄存器（offset）：

| offset | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `0x00` | `TXDATA` | W | 写低 8bit：push TX FIFO（若满则不入队） |
| `0x04` | `RXDATA` | R | 读：pop RX FIFO；bit31=valid，低 8bit=数据 |
| `0x08` | `STATUS` | R | bit0 TX_BUSY，bit1 TX_FULL，bit2 TX_EMPTY，bit3 RX_VALID，bit4 RX_FULL，bit5 OVERRUN |
| `0x0C` | `BAUDDIV` | R/W | bit 周期（>=1） |
| `0x10` | `CTRL` | R/W | bit0 TX_EN，bit1 RX_EN，bit2 LOOPBACK，bit3 CLR_OVERRUN(W1) |

TX 发送建议写法：轮询 `TX_FULL==0` 再写 `TXDATA`。
RX 接收建议写法：轮询 `RX_VALID==1` 再读 `RXDATA`（读会 pop）。

### 6.6 SoC 仿真（外设自检程序）

SoC TB：`sim/soc/soc_top_basic_tb.v`

构建与运行（示例）：

```bash
cd /home/zcq/CowCat32

# 构建某个自检程序（生成 .vh 和可直接复制的 ROM 文件 .imem.v）
./sim/soc/build_soc_prog.sh sim/soc/uart_loopback_test.S

# 编译 SoC TB（可选加 -DUART_SIM_PRINT 直接打印串口输出）
iverilog -g2012 -DUART_SIM_PRINT -o /tmp/soc_tb.out \
  sim/soc/soc_top_basic_tb.v \
  src/soc/*.v src/periph/*.v src/mem/*.v \
  src/core/*.v src/control/*.v src/datapath/*.v

# 运行（通过 +hex 指定程序镜像）
vvp -n /tmp/soc_tb.out +hex=sim/soc/out/uart_loopback_test.vh

# 如果你想把程序直接粘进 ROM，用生成出来的：
# sim/soc/out/uart_loopback_test.imem.v

# 可选：导出 VCD（便于 Vivado/GTKWave 看波形）
vvp -n /tmp/soc_tb.out +hex=sim/soc/out/uart_loopback_test.vh +vcd=/tmp/soc.vcd
```

已提供的外设自检程序（asm）：
- `sim/soc/gpio_timer.S`
- `sim/soc/gpio_timer_rwtest.S`
- `sim/soc/dma_memcpy_test.S`
- `sim/soc/uart_loopback_test.S`

已提供的外设自检程序（C，全覆盖）：
- `sw/examples/gpio_dma_uart_demo/`（GPIO + TIMER + DMA + UART）
- `sw/examples/uart_loopback/`（UART 内部回环：发送后读回比对）

### 6.7 外设单元测试（不带 CPU）

目录：`sim/periph/`

- `gpio_mmio_tb.v`：GPIO 单元测试
- `timer_mmio_tb.v`：Timer 单元测试
- `uart_mmio_tb.v`：UART 单元测试（loopback）
- `dma_mmio_tb.v`：DMA 单元测试

示例：

```bash
iverilog -g2012 -s uart_mmio_tb -o /tmp/uart_tb.out sim/periph/uart_mmio_tb.v src/periph/uart_mmio.v
vvp -n /tmp/uart_tb.out
```

---

## 7. 工具链依赖

- `iverilog` / `vvp`
- `riscv64-unknown-elf-gcc`（用于编译 rv32ui 测试与 `sw/` 裸机程序，常用 `-march=rv32i -mabi=ilp32`）
- `riscv64-unknown-elf-objcopy`（生成 verilog hex / binary）
- `python3`（`sw/tools/` 里用于转换 `.vh`/生成 `imem.v`）

---

## 8. 常见问题（FAQ）

### Q1：为什么并行跑更快？
本项目的仿真是 Icarus Verilog（单个仿真进程基本单线程），但你可以通过**多进程并行**跑多个测试用例，把 CPU 核心吃满。

### Q2：为什么之前 load/store 类用例会集体失败？
如果 `.vh` 的 `@` 地址按“字节地址”解释，而 testbench 的 `mem[]` 按“word index”加载，会导致 `.data/.tohost` 等段装载错位，从而出现大量 load/store 检查失败。

---

如需把本处理器接到真实 SRAM/AXI bridge、或加上异常/CSR/特权级，我可以基于当前接口再给一个更工程化的总线适配层建议。\
