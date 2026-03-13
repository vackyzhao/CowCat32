module memory_arbiter #(
    parameter IO_MAP_WIDTH = 32,
    parameter DTCM_BASE_ADDR = 32'h0000_0000,
    parameter DTCM_ADDR_END = 32'h0000_0FFF, // DTCM 大小为4KB
    parameter GPIO_BASE_ADDR = 32'h0000_1000,
    parameter GPIO_ADDR_END = 32'h0000_1FFF,
    parameter RTC_BASE_ADDR = 32'h0000_2000,
    parameter RTC_ADDR_END = 32'h0000_2FFF
)(
    input wire clk,
    input wire rst,
    
    // CPU 请求信号
    input wire [IO_MAP_WIDTH-1:0] cpu_addr,
    input wire [IO_MAP_WIDTH-1:0] cpu_wdata,
    output reg [IO_MAP_WIDTH-1:0] cpu_rdata,
    input wire cpu_rw,          // CPU 读写控制信号 (1: 写, 0: 读)
    output reg cpu_ready,       // CPU 准备好信号

    // DTCM 接口
    output reg [IO_MAP_WIDTH-1:0] dtcm_addr,
    output reg [IO_MAP_WIDTH-1:0] dtcm_wdata,
    input wire [IO_MAP_WIDTH-1:0] dtcm_rdata,
    output reg dtcm_rw,         // DTCM 读写控制信号 (1: 写, 0: 读)
    input wire dtcm_ready,

    // GPIO 接口
    output reg [IO_MAP_WIDTH-1:0] gpio_addr,
    output reg [IO_MAP_WIDTH-1:0] gpio_wdata,
    input wire [IO_MAP_WIDTH-1:0] gpio_rdata,
    output reg gpio_rw,          // GPIO 写使能
    input wire gpio_ready,

    // RTC 接口
    output reg [IO_MAP_WIDTH-1:0] rtc_addr,
    output reg [IO_MAP_WIDTH-1:0] rtc_wdata,
    input wire [IO_MAP_WIDTH-1:0] rtc_rdata,
    output reg rtc_rw,           // RTC 写使能
    input wire rtc_ready
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        // Reset all signals
        cpu_rdata <= {IO_MAP_WIDTH{1'b0}};
        cpu_ready <= 1'b0;
        dtcm_addr <= {IO_MAP_WIDTH{1'b0}};
        dtcm_wdata <= {IO_MAP_WIDTH{1'b0}};
        dtcm_rw <= 1'b0;
        gpio_addr <= {IO_MAP_WIDTH{1'b0}};
        gpio_wdata <= {IO_MAP_WIDTH{1'b0}};
        gpio_rw <= 1'b0;
        rtc_addr <= {IO_MAP_WIDTH{1'b0}};
        rtc_wdata <= {IO_MAP_WIDTH{1'b0}};
        rtc_rw <= 1'b0;
    end else begin
        // Default values
        cpu_ready <= 1'b0;
        dtcm_rw <= 1'b0; // 默认读操作
        gpio_rw <= 1'b0;
        rtc_rw <= 1'b0;

        // Handle CPU requests
        if (cpu_addr >= DTCM_BASE_ADDR && cpu_addr <= DTCM_ADDR_END) begin
            // DTCM access
            dtcm_addr <= cpu_addr - DTCM_BASE_ADDR;
            if (cpu_rw) begin
                dtcm_wdata <= cpu_wdata;
                dtcm_rw <= 1'b1;  // DTCM 写操作
            end
            if (dtcm_ready) begin
                cpu_rdata <= dtcm_rdata;
                cpu_ready <= 1'b1;
            end
        end else if (cpu_addr >= GPIO_BASE_ADDR && cpu_addr <= GPIO_ADDR_END) begin
            // GPIO access
            gpio_addr <= cpu_addr - GPIO_BASE_ADDR;
            if (cpu_rw) begin
                gpio_wdata <= cpu_wdata;
                gpio_rw <= 1'b1;  // GPIO 写操作
            end
            if (gpio_ready) begin
                cpu_rdata <= gpio_rdata;
                cpu_ready <= 1'b1;
            end
        end else if (cpu_addr >= RTC_BASE_ADDR && cpu_addr <= RTC_ADDR_END) begin
            // RTC access
            rtc_addr <= cpu_addr - RTC_BASE_ADDR;
            if (cpu_rw) begin
                rtc_wdata <= cpu_wdata;
                rtc_rw <= 1'b1;  // RTC 写操作
            end
            if (rtc_ready) begin
                cpu_rdata <= rtc_rdata;
                cpu_ready <= 1'b1;
            end
        end
    end
end

endmodule
