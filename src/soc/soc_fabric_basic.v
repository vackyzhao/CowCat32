`timescale 1ns/1ps

// Minimal DMEM fabric (data memory + MMIO).
// Instruction side is assumed to come from a separate ROM.
module soc_fabric_basic #(
    // Default DMEM size: 2048 words = 8KiB (FPGA-friendly). Override as needed.
    parameter integer SRAM_WORDS = 2048,
    parameter [31:0]  MMIO_BASE  = 32'h1000_0000,
    parameter [31:0]  MMIO_MASK  = 32'hFFFF_0000,  // 64KiB MMIO window
    parameter [31:0]  PERIPH_MASK= 32'hFFFF_F000,  // 4KiB pages within MMIO
    parameter [31:0]  GPIO_BASE  = 32'h1000_0000,
    parameter [31:0]  TIMER_BASE = 32'h1000_1000,
    parameter [31:0]  DMA_BASE   = 32'h1000_2000,
    parameter [31:0]  UART_BASE  = 32'h1000_3000,
    parameter integer CLK_HZ     = 100_000_000
) (
    input  wire        clk,
    input  wire        rst,

    // Shared data bus (from arbiter)
    input  wire        mem_req,
    input  wire        mem_we,
    input  wire        mem_re,
    input  wire [31:0] dm_addr,
    input  wire [31:0] dm_store,
    input  wire [3:0]  dm_ctl,
    output reg  [31:0] dm_load,
    output reg         dm_ack,

    // DMA master port (to arbiter)
    output wire        dma_m_req,
    output wire        dma_m_we,
    output wire        dma_m_re,
    output wire [31:0] dma_m_addr,
    output wire [31:0] dma_m_wdata,
    output wire [3:0]  dma_m_wstrb,
    input  wire        dma_m_ack,
    input  wire [31:0] dma_m_rdata,

    // GPIO pins
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_dir,

    // UART pins
    input  wire        uart_rx,
    output wire        uart_tx
);

    wire d_req = mem_req && (mem_we || mem_re);

    // decode (data side only)
    wire is_mmio = ((dm_addr & MMIO_MASK) == (MMIO_BASE & MMIO_MASK));
    wire is_gpio  = ((dm_addr & PERIPH_MASK) == (GPIO_BASE  & PERIPH_MASK));
    wire is_timer = ((dm_addr & PERIPH_MASK) == (TIMER_BASE & PERIPH_MASK));
    wire is_dma   = ((dm_addr & PERIPH_MASK) == (DMA_BASE   & PERIPH_MASK));
    wire is_uart  = ((dm_addr & PERIPH_MASK) == (UART_BASE  & PERIPH_MASK));

    // SRAM for data
    wire [31:0] sram_rdata;
    wire        sram_ack;
    sram_1rw #(.DEPTH_WORDS(SRAM_WORDS)) u_dmem (
        .clk   (clk),
        .rst   (rst),
        .req   (d_req && !is_mmio),
        .we    (mem_we),
        .addr  (dm_addr),
        .wdata (dm_store),
        .wstrb (dm_ctl),
        .rdata (sram_rdata),
        .ack   (sram_ack)
    );

    // GPIO MMIO
    wire [31:0] gpio_rdata;
    wire        gpio_ack;
    gpio_mmio u_gpio (
        .clk      (clk),
        .rst      (rst),
        .req      (d_req && is_gpio),
        .we       (mem_we),
        .addr     (dm_addr[11:0]),
        .wdata    (dm_store),
        .wstrb    (dm_ctl),
        .rdata    (gpio_rdata),
        .ack      (gpio_ack),
        .gpio_in  (gpio_in),
        .gpio_out (gpio_out),
        .gpio_dir (gpio_dir)
    );

    // TIMER MMIO
    wire [31:0] tim_rdata;
    wire        tim_ack;
    timer_mmio #(.CLK_HZ(CLK_HZ)) u_tim (
        .clk   (clk),
        .rst   (rst),
        .req   (d_req && is_timer),
        .we    (mem_we),
        .addr  (dm_addr[11:0]),
        .wdata (dm_store),
        .wstrb (dm_ctl),
        .rdata (tim_rdata),
        .ack   (tim_ack)
    );

    // DMA MMIO + engine
    wire [31:0] dma_rdata;
    wire        dma_ack;
    dma_mmio #(
        .DMA_BASE   (DMA_BASE),
        .PERIPH_MASK(PERIPH_MASK)
    ) u_dma (
        .clk     (clk),
        .rst     (rst),
        // slave
        .s_req   (d_req && is_dma),
        .s_we    (mem_we),
        .s_addr  (dm_addr[11:0]),
        .s_wdata (dm_store),
        .s_wstrb (dm_ctl),
        .s_rdata (dma_rdata),
        .s_ack   (dma_ack),
        // master
        .m_req   (dma_m_req),
        .m_we    (dma_m_we),
        .m_re    (dma_m_re),
        .m_addr  (dma_m_addr),
        .m_wdata (dma_m_wdata),
        .m_wstrb (dma_m_wstrb),
        .m_ack   (dma_m_ack),
        .m_rdata (dma_m_rdata)
    );

    // UART MMIO
    wire [31:0] uart_rdata;
    wire        uart_ack;
    uart_mmio u_uart (
        .clk     (clk),
        .rst     (rst),
        .req     (d_req && is_uart),
        .we      (mem_we),
        .addr    (dm_addr[11:0]),
        .wdata   (dm_store),
        .wstrb   (dm_ctl),
        .rdata   (uart_rdata),
        .ack     (uart_ack),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx)
    );

    always @(*) begin
        if (!d_req) begin
            dm_ack  = 1'b1;
            dm_load = 32'h0;
        end else if (is_mmio) begin
            dm_ack  = is_gpio  ? gpio_ack :
                      is_timer ? tim_ack  :
                      is_dma   ? dma_ack  :
                      is_uart  ? uart_ack : 1'b1;
            dm_load = is_gpio  ? gpio_rdata :
                      is_timer ? tim_rdata  :
                      is_dma   ? dma_rdata  :
                      is_uart  ? uart_rdata : 32'h0;
        end else begin
            dm_ack  = sram_ack;
            dm_load = sram_rdata;
        end
    end

endmodule
