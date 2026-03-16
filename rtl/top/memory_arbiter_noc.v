// memory_arbiter_noc.v
// Extended version of CowCat32's memory_arbiter.
// Adds a NOC peripheral port alongside DTCM, GPIO, and RTC.
// The original arbiter logic is preserved; only the NOC decode block is new.

module memory_arbiter_noc #(
    parameter IO_MAP_WIDTH  = 32,
    parameter DTCM_BASE_ADDR = 32'h0000_0000,
    parameter DTCM_ADDR_END  = 32'h0000_0FFF,
    parameter GPIO_BASE_ADDR = 32'h0000_1000,
    parameter GPIO_ADDR_END  = 32'h0000_1FFF,
    parameter RTC_BASE_ADDR  = 32'h0000_2000,
    parameter RTC_ADDR_END   = 32'h0000_2FFF,
    parameter NOC_BASE_ADDR  = 32'h0000_3000,
    parameter NOC_ADDR_END   = 32'h0000_3FFF
)(
    input  wire                       clk,
    input  wire                       rst,

    // CPU request
    input  wire [IO_MAP_WIDTH-1:0]    cpu_addr,
    input  wire [IO_MAP_WIDTH-1:0]    cpu_wdata,
    output reg  [IO_MAP_WIDTH-1:0]    cpu_rdata,
    input  wire                       cpu_rw,
    output reg                        cpu_ready,

    // DTCM
    output reg  [IO_MAP_WIDTH-1:0]    dtcm_addr,
    output reg  [IO_MAP_WIDTH-1:0]    dtcm_wdata,
    input  wire [IO_MAP_WIDTH-1:0]    dtcm_rdata,
    output reg                        dtcm_rw,
    input  wire                       dtcm_ready,

    // GPIO
    output reg  [IO_MAP_WIDTH-1:0]    gpio_addr,
    output reg  [IO_MAP_WIDTH-1:0]    gpio_wdata,
    input  wire [IO_MAP_WIDTH-1:0]    gpio_rdata,
    output reg                        gpio_rw,
    input  wire                       gpio_ready,

    // RTC
    output reg  [IO_MAP_WIDTH-1:0]    rtc_addr,
    output reg  [IO_MAP_WIDTH-1:0]    rtc_wdata,
    input  wire [IO_MAP_WIDTH-1:0]    rtc_rdata,
    output reg                        rtc_rw,
    input  wire                       rtc_ready,

    // NOC (new)
    output reg  [IO_MAP_WIDTH-1:0]    noc_addr,
    output reg  [IO_MAP_WIDTH-1:0]    noc_wdata,
    input  wire [IO_MAP_WIDTH-1:0]    noc_rdata,
    output reg                        noc_rw,    // 1=write, 0=read
    output reg                        noc_we,    // chip-select
    input  wire                       noc_ready
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        cpu_rdata  <= 0; cpu_ready <= 0;
        dtcm_addr  <= 0; dtcm_wdata <= 0; dtcm_rw <= 0;
        gpio_addr  <= 0; gpio_wdata <= 0; gpio_rw <= 0;
        rtc_addr   <= 0; rtc_wdata  <= 0; rtc_rw  <= 0;
        noc_addr   <= 0; noc_wdata  <= 0; noc_rw  <= 0; noc_we <= 0;
    end else begin
        // Defaults
        cpu_ready <= 0;
        dtcm_rw   <= 0; gpio_rw <= 0; rtc_rw <= 0;
        noc_rw    <= 0; noc_we  <= 0;

        if (cpu_addr >= DTCM_BASE_ADDR && cpu_addr <= DTCM_ADDR_END) begin
            dtcm_addr  <= cpu_addr - DTCM_BASE_ADDR;
            dtcm_wdata <= cpu_wdata;
            if (cpu_rw) dtcm_rw <= 1;
            if (dtcm_ready) begin cpu_rdata <= dtcm_rdata; cpu_ready <= 1; end

        end else if (cpu_addr >= GPIO_BASE_ADDR && cpu_addr <= GPIO_ADDR_END) begin
            gpio_addr  <= cpu_addr - GPIO_BASE_ADDR;
            gpio_wdata <= cpu_wdata;
            if (cpu_rw) gpio_rw <= 1;
            if (gpio_ready) begin cpu_rdata <= gpio_rdata; cpu_ready <= 1; end

        end else if (cpu_addr >= RTC_BASE_ADDR && cpu_addr <= RTC_ADDR_END) begin
            rtc_addr  <= cpu_addr - RTC_BASE_ADDR;
            rtc_wdata <= cpu_wdata;
            if (cpu_rw) rtc_rw <= 1;
            if (rtc_ready) begin cpu_rdata <= rtc_rdata; cpu_ready <= 1; end

        end else if (cpu_addr >= NOC_BASE_ADDR && cpu_addr <= NOC_ADDR_END) begin
            noc_addr  <= cpu_addr - NOC_BASE_ADDR;
            noc_wdata <= cpu_wdata;
            noc_rw    <= cpu_rw;
            noc_we    <= 1;
            if (noc_ready) begin cpu_rdata <= noc_rdata; cpu_ready <= 1; end
        end
    end
end

endmodule
