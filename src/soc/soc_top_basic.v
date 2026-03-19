`timescale 1ns/1ps

// Minimal SoC top:
// - SynCPU core
// - Basic fabric with SRAM + GPIO + Timer
module soc_top_basic #(
    parameter integer CLK_HZ = 100_000_000,
    // Default IMEM size: 2048 words = 8KiB (FPGA-friendly). Override as needed.
    parameter integer IMEM_WORDS = 2048,
    parameter [31:0]  UART_DEFAULT_BAUDDIV = 32'd868
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_dir,

    input  wire        uart_rx,
    output wire        uart_tx
);

    // CPU ports
    wire [31:0] im_addr;
    wire [31:0] im_inst;
    wire        im_ack;

    wire [31:0] dm_addr;
    wire [31:0] dm_store;
    wire [31:0] dm_load;
    wire [3:0]  dm_ctl;
    wire        dm_ack;

    wire        mem_req;
    wire        mem_we;
    wire        mem_re;

    // trace
    wire        trace_valid;
    wire [31:0] trace_pc;
    wire [31:0] trace_inst;
    wire [4:0]  trace_rd;
    wire [31:0] trace_rd_data;

    // Instruction ROM
    imem_rom #(
        .DEPTH_WORDS(IMEM_WORDS)
    ) u_rom (
        .addr (im_addr),
        .rdata(im_inst)
    );
    assign im_ack = 1'b1;

    // CPU <-> bus signals
    wire        cpu_req = mem_req && (mem_we || mem_re);
    wire        cpu_we  = mem_we;
    wire        cpu_re  = mem_re;
    wire [31:0] cpu_addr  = dm_addr;
    wire [31:0] cpu_wdata = dm_store;
    wire [3:0]  cpu_wstrb = dm_ctl;
    wire        cpu_ack;
    wire [31:0] cpu_rdata;

    // DMA master port from fabric
    wire        dma_req;
    wire        dma_we;
    wire        dma_re;
    wire [31:0] dma_addr;
    wire [31:0] dma_wdata;
    wire [3:0]  dma_wstrb;
    wire        dma_ack;
    wire [31:0] dma_rdata;

    // arbiter -> fabric bus
    wire        bus_req;
    wire        bus_we;
    wire        bus_re;
    wire [31:0] bus_addr;
    wire [31:0] bus_wdata;
    wire [3:0]  bus_wstrb;
    wire        bus_ack;
    wire [31:0] bus_rdata;

    bus_arb_2m u_arb (
        .clk     (clk),
        .rst     (rst),
        .m0_req  (cpu_req),
        .m0_we   (cpu_we),
        .m0_re   (cpu_re),
        .m0_addr (cpu_addr),
        .m0_wdata(cpu_wdata),
        .m0_wstrb(cpu_wstrb),
        .m0_ack  (cpu_ack),
        .m0_rdata(cpu_rdata),

        .m1_req  (dma_req),
        .m1_we   (dma_we),
        .m1_re   (dma_re),
        .m1_addr (dma_addr),
        .m1_wdata(dma_wdata),
        .m1_wstrb(dma_wstrb),
        .m1_ack  (dma_ack),
        .m1_rdata(dma_rdata),

        .s_req   (bus_req),
        .s_we    (bus_we),
        .s_re    (bus_re),
        .s_addr  (bus_addr),
        .s_wdata (bus_wdata),
        .s_wstrb (bus_wstrb),
        .s_ack   (bus_ack),
        .s_rdata (bus_rdata)
    );

    // hook CPU to arbiter responses
    assign dm_ack  = cpu_ack;
    assign dm_load = cpu_rdata;

    SynCPU u_cpu (
        .dm_load       (dm_load),
        .dm_addr       (dm_addr),
        .dm_store      (dm_store),
        .im_addr       (im_addr),
        .im_inst       (im_inst),
        .dm_ctl        (dm_ctl),
        .mem_req       (mem_req),
        .mem_we        (mem_we),
        .mem_re        (mem_re),
        .trace_valid   (trace_valid),
        .trace_pc      (trace_pc),
        .trace_inst    (trace_inst),
        .trace_rd      (trace_rd),
        .trace_rd_data (trace_rd_data),
        .clk           (clk),
        .rst           (rst),
        .dm_ack        (dm_ack),
        .im_ack        (im_ack)
    );

    soc_fabric_basic #(
        .CLK_HZ(CLK_HZ),
        .UART_DEFAULT_BAUDDIV(UART_DEFAULT_BAUDDIV)
    ) u_fab (
        .clk        (clk),
        .rst        (rst),
        .mem_req    (bus_req),
        .mem_we     (bus_we),
        .mem_re     (bus_re),
        .dm_addr    (bus_addr),
        .dm_store   (bus_wdata),
        .dm_ctl     (bus_wstrb),
        .dm_load    (bus_rdata),
        .dm_ack     (bus_ack),
        // dma master
        .dma_m_req  (dma_req),
        .dma_m_we   (dma_we),
        .dma_m_re   (dma_re),
        .dma_m_addr (dma_addr),
        .dma_m_wdata(dma_wdata),
        .dma_m_wstrb(dma_wstrb),
        .dma_m_ack  (dma_ack),
        .dma_m_rdata(dma_rdata),
        // gpio
        .gpio_in    (gpio_in),
        .gpio_out   (gpio_out),
        .gpio_dir   (gpio_dir),
        // uart
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx)
    );

endmodule
