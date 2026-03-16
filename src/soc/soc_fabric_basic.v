`timescale 1ns/1ps

// Minimal SoC fabric:
// - Arb between CPU imem fetch and dmem access (single shared target)
// - Address decode: SRAM vs MMIO (GPIO/TIMER)
// - Data side has priority over instruction fetch
module soc_fabric_basic #(
    parameter integer SRAM_WORDS = 131072,      // 512KiB
    parameter [31:0]  MMIO_BASE  = 32'h1000_0000,
    parameter [31:0]  MMIO_MASK  = 32'hFFFF_0000,  // 64KiB MMIO window
    parameter [31:0]  PERIPH_MASK= 32'hFFFF_F000,  // 4KiB pages within MMIO
    parameter [31:0]  GPIO_BASE  = 32'h1000_0000,
    parameter [31:0]  TIMER_BASE = 32'h1000_1000,
    parameter integer CLK_HZ     = 100_000_000
) (
    input  wire        clk,
    input  wire        rst,

    // CPU instruction port
    input  wire [31:0] im_addr,
    output reg  [31:0] im_inst,
    output reg         im_ack,

    // CPU data port
    input  wire        mem_req,
    input  wire        mem_we,
    input  wire        mem_re,
    input  wire [31:0] dm_addr,
    input  wire [31:0] dm_store,
    input  wire [3:0]  dm_ctl,
    output reg  [31:0] dm_load,
    output reg         dm_ack,

    // GPIO pins
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_dir
);

    // data request
    wire d_req = mem_req && (mem_we || mem_re);

    // decode (data side only)
    wire is_mmio = ((dm_addr & MMIO_MASK) == (MMIO_BASE & MMIO_MASK));
    wire is_gpio  = ((dm_addr & PERIPH_MASK) == (GPIO_BASE & PERIPH_MASK));
    wire is_timer = ((dm_addr & PERIPH_MASK) == (TIMER_BASE & PERIPH_MASK));

    // SRAM (dual-port)
    wire [31:0] im_rdata;
    wire [31:0] dm_rdata_sram;
    wire        dm_ack_sram;

    sram_2p_imem_dmem #(.DEPTH_WORDS(SRAM_WORDS)) u_sram (
        .clk     (clk),
        .rst     (rst),
        .im_addr (im_addr),
        .im_rdata(im_rdata),
        .dm_req  (d_req && !is_mmio),
        .dm_we   (mem_we),
        .dm_addr (dm_addr),
        .dm_wdata(dm_store),
        .dm_wstrb(dm_ctl),
        .dm_rdata(dm_rdata_sram),
        .dm_ack  (dm_ack_sram)
    );

    // GPIO MMIO
    wire [31:0] gpio_rdata;
    wire        gpio_ack;
    gpio_mmio u_gpio (
        .clk      (clk),
        .rst      (rst),
        .req      (d_req && is_gpio),
        .we       (mem_we),
        .addr     (dm_addr - GPIO_BASE),
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
        .addr  (dm_addr - TIMER_BASE),
        .wdata (dm_store),
        .wstrb (dm_ctl),
        .rdata (tim_rdata),
        .ack   (tim_ack)
    );

    // instruction side: always ready
    always @(*) begin
        im_ack  = 1'b1;
        im_inst = im_rdata;

        // data side
        if (!d_req) begin
            dm_ack  = 1'b1;
            dm_load = 32'h0;
        end else if (is_mmio) begin
            dm_ack  = is_gpio ? gpio_ack : (is_timer ? tim_ack : 1'b1);
            dm_load = is_gpio ? gpio_rdata : (is_timer ? tim_rdata : 32'h0);
        end else begin
            dm_ack  = dm_ack_sram;
            dm_load = dm_rdata_sram;
        end
    end

endmodule
