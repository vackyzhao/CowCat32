`timescale 1ns/1ps

// Minimal SoC top:
// - SynCPU core
// - Basic fabric with SRAM + GPIO + Timer
module soc_top_basic #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer IMEM_WORDS = 131072
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_dir
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

    soc_fabric_basic #(.CLK_HZ(CLK_HZ)) u_fab (
        .clk     (clk),
        .rst     (rst),
        .mem_req (mem_req),
        .mem_we  (mem_we),
        .mem_re  (mem_re),
        .dm_addr (dm_addr),
        .dm_store(dm_store),
        .dm_ctl  (dm_ctl),
        .dm_load (dm_load),
        .dm_ack  (dm_ack),
        .gpio_in (gpio_in),
        .gpio_out(gpio_out),
        .gpio_dir(gpio_dir)
    );

endmodule
