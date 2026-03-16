// cpu_tile_top.v
// One CowCat32 CPU + its local NoC adapter.
// This is the instantiation unit for each node in LobsterPawn.
//
// The original soc_top.v is NOT used here because we extend the
// memory_arbiter with a NOC port. The CPU, ITCM, DTCM, GPIO, RTC, and
// noc_adapter are all wired together here with the extended arbiter below.

`include "param.vh"

module cpu_tile_top #(
    parameter NODE_X        = 0,
    parameter NODE_Y        = 0,
    // Address map
    parameter DTCM_BASE     = 32'h0000_0000,
    parameter DTCM_END      = 32'h0000_0FFF,
    parameter GPIO_BASE     = 32'h0000_1000,
    parameter GPIO_END      = 32'h0000_1FFF,
    parameter RTC_BASE      = 32'h0000_2000,
    parameter RTC_END       = 32'h0000_2FFF,
    parameter NOC_BASE      = 32'h0000_3000,
    parameter NOC_END       = 32'h0000_3FFF
)(
    input  wire        clk,
    input  wire        rtc_clk,
    input  wire        rst,       // active-high, from top-level

    // GPIO (bidirectional — kept for compatibility)
    inout  wire [31:0] gpio,

    // NoD local port — TX
    output wire [`DATA_WIDTH-1:0] nod_tx_data,
    output wire                   nod_tx_valid,
    input  wire                   nod_tx_ready,

    // NoD local port — RX
    input  wire [`DATA_WIDTH-1:0] nod_rx_data,
    input  wire                   nod_rx_valid,
    output wire                   nod_rx_ready
);

// Internal active-low reset for sub-modules derived from active-high rst
wire rstn = ~rst;

// -----------------------------------------------------------------------
// CPU signals
// -----------------------------------------------------------------------
wire [31:0] cpu_iaddr, cpu_idata;
wire        im_ready;
wire [31:0] cpu_daddr, cpu_dwdata, cpu_drdata;
wire        cpu_rw, cpu_ready;
wire [3:0]  dm_ctl;

// -----------------------------------------------------------------------
// Peripheral bus signals (extended arbiter outputs)
// -----------------------------------------------------------------------
wire [31:0] dtcm_rdata, gpio_rdata, rtc_rdata, noc_rdata;
wire        dtcm_ready, gpio_ready, rtc_ready, noc_ready;
wire        dtcm_rw, gpio_rw, rtc_rw, noc_we, noc_rw_sig;
wire [31:0] noc_addr_sig, noc_wdata_sig;

// GPIO pins
wire [31:0] gpio_mode, gpio_out, gpio_in;

// -----------------------------------------------------------------------
// CPU
// -----------------------------------------------------------------------
SynCPU cpu (
    .clk      (clk),
    .rst      (rstn),          // SynCPU uses active-low rst internally
    .dm_ack   (cpu_ready),
    .im_ack   (im_ready),
    .im_inst  (cpu_idata),
    .im_addr  (cpu_iaddr),
    .dm_load  (cpu_drdata),
    .dm_addr  (cpu_daddr),
    .dm_store (cpu_dwdata),
    .dm_ctl   (dm_ctl)
);

// cpu_rw: dm_ctl[0] indicates a store operation
assign cpu_rw = |dm_ctl;

// -----------------------------------------------------------------------
// ITCM
// -----------------------------------------------------------------------
itcm itcm_inst (
    .clk      (clk),
    .addr     (cpu_iaddr),
    .data_out (cpu_idata),
    .ack      (im_ready)
);

// -----------------------------------------------------------------------
// Extended memory arbiter (adds NOC port to original arbiter)
// -----------------------------------------------------------------------
memory_arbiter_noc #(
    .DTCM_BASE_ADDR (DTCM_BASE), .DTCM_ADDR_END (DTCM_END),
    .GPIO_BASE_ADDR (GPIO_BASE), .GPIO_ADDR_END (GPIO_END),
    .RTC_BASE_ADDR  (RTC_BASE),  .RTC_ADDR_END  (RTC_END),
    .NOC_BASE_ADDR  (NOC_BASE),  .NOC_ADDR_END  (NOC_END)
) arbiter (
    .clk        (clk),
    .rst        (rst),
    .cpu_addr   (cpu_daddr),
    .cpu_wdata  (cpu_dwdata),
    .cpu_rdata  (cpu_drdata),
    .cpu_rw     (cpu_rw),
    .cpu_ready  (cpu_ready),
    // DTCM
    .dtcm_rdata (dtcm_rdata), .dtcm_ready (dtcm_ready), .dtcm_rw (dtcm_rw),
    // GPIO
    .gpio_rdata (gpio_rdata), .gpio_ready (gpio_ready), .gpio_rw (gpio_rw),
    // RTC
    .rtc_rdata  (rtc_rdata),  .rtc_ready  (rtc_ready),  .rtc_rw  (rtc_rw),
    // NOC
    .noc_rdata  (noc_rdata),  .noc_ready  (noc_ready),
    .noc_we     (noc_we),     .noc_rw     (noc_rw_sig),
    .noc_addr   (noc_addr_sig), .noc_wdata (noc_wdata_sig)
);

// -----------------------------------------------------------------------
// DTCM
// -----------------------------------------------------------------------
dtcm dtcm_inst (
    .clk   (clk),
    .addr  (cpu_daddr[11:0]),   // dtcm addr is 12-bit (4 KB)
    .wdata (cpu_dwdata),
    .rdata (dtcm_rdata),
    .rw    (cpu_rw),
    .ready (dtcm_ready)
);

// -----------------------------------------------------------------------
// GPIO
// -----------------------------------------------------------------------
soc_gpio gpio_ctrl (
    .clk        (clk),
    .rst        (rst),
    .gpio_wdata (cpu_dwdata),
    .gpio_we    (gpio_rw),
    .gpio_addr  (cpu_daddr[3:0]),
    .gpio_rdata (gpio_rdata),
    .gpio_ready (gpio_ready),
    .gpio_mode  (gpio_mode),
    .gpio_out   (gpio_out),
    .gpio_in    (gpio_in)
);

// -----------------------------------------------------------------------
// RTC
// -----------------------------------------------------------------------
soc_rtc rtc_inst (
    .clk       (clk),
    .rtc_clk   (rtc_clk),
    .rst       (rst),
    .rtc_rdata (rtc_rdata),
    .rtc_we    (rtc_rw),
    .rtc_ready (rtc_ready)
);

// -----------------------------------------------------------------------
// NoC Adapter
// -----------------------------------------------------------------------
noc_adapter #(
    .NODE_X (NODE_X),
    .NODE_Y (NODE_Y)
) u_noc_adapter (
    .clk         (clk),
    .rstn        (rstn),
    .noc_addr    (noc_addr_sig),
    .noc_wdata   (noc_wdata_sig),
    .noc_rw      (noc_rw_sig),
    .noc_we      (noc_we),
    .noc_rdata   (noc_rdata),
    .noc_ready   (noc_ready),
    .nod_tx_data  (nod_tx_data),
    .nod_tx_valid (nod_tx_valid),
    .nod_tx_ready (nod_tx_ready),
    .nod_rx_data  (nod_rx_data),
    .nod_rx_valid (nod_rx_valid),
    .nod_rx_ready (nod_rx_ready)
);

// -----------------------------------------------------------------------
// GPIO I/O buffers (synthesis-only — for simulation tie off)
// -----------------------------------------------------------------------
`ifdef SYNTHESIS
genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : gpio_iobuf
        IOBUF iobuf_inst (
            .I  (gpio_out[i]),
            .O  (gpio_in[i]),
            .IO (gpio[i]),
            .T  (~gpio_mode[i])
        );
    end
endgenerate
`else
assign gpio_in = gpio;
`endif

endmodule
