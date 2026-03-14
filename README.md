# CowCat32 — RV32I 五级流水处理器（使用手册）

本项目实现了一个 **RV32I**（32-bit base integer）五级流水 RISC‑V 处理器，并提供了基于 `riscv-tests` 的回归测试脚本与一个自包含 testbench，便于快速验证与二次开发。

> 说明：当前处理器 **不实现 misaligned（非对齐）访存**（例如 `lw x?, 1(x?)`），相关测试（如 `ma_data`）失败不视为 bug。

---

## 目录结构（你最常用的部分）

- `src/core/`：流水线各级模块与顶层 `SynCPU.v`
- `src/control/`：控制单元（译码/流水控制/前递/暂停等）
- `src/datapath/`：ALU、寄存器堆、立即数生成、流水寄存器等
- `sim/rv32i_blackbox/riscv_tests/`：rv32ui 回归测试（编译、生成 hex、仿真）

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

## 6. 工具链依赖

- `iverilog` / `vvp`
- `riscv64-unknown-elf-gcc`（用于编译 rv32ui 测试，脚本中用 `-march=rv32i -mabi=ilp32`）
- `riscv64-unknown-elf-objcopy`（生成 verilog hex）

---

## 7. 常见问题（FAQ）

### Q1：为什么并行跑更快？
本项目的仿真是 Icarus Verilog（单个仿真进程基本单线程），但你可以通过**多进程并行**跑多个测试用例，把 CPU 核心吃满。

### Q2：为什么之前 load/store 类用例会集体失败？
如果 `.vh` 的 `@` 地址按“字节地址”解释，而 testbench 的 `mem[]` 按“word index”加载，会导致 `.data/.tohost` 等段装载错位，从而出现大量 load/store 检查失败。

---

如需把本处理器接到真实 SRAM/AXI bridge、或加上异常/CSR/特权级，我可以基于当前接口再给一个更工程化的总线适配层建议。\
