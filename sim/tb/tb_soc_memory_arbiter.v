`timescale 1ns / 1ps

module tb_memory_arbiter;

    // 参数
    parameter IO_MAP_WIDTH = 32;
    parameter DTCM_BASE_ADDR = 32'h0000_0000;
    parameter DTCM_ADDR_END  = 32'h0000_0FFF;
    parameter GPIO_BASE_ADDR = 32'h0000_1000;
    parameter GPIO_ADDR_END  = 32'h0000_1FFF;
    parameter RTC_BASE_ADDR  = 32'h0000_2000;
    parameter RTC_ADDR_END   = 32'h0000_2FFF;

    // 信号声明
    reg clk;
    reg rst;
    reg [IO_MAP_WIDTH-1:0] cpu_addr;
    reg [IO_MAP_WIDTH-1:0] cpu_wdata;
    reg cpu_rw;
    wire [IO_MAP_WIDTH-1:0] cpu_rdata;
    wire cpu_ready;
    
    // DTCM 接口信号
    wire [IO_MAP_WIDTH-1:0] dtcm_addr;
    wire [IO_MAP_WIDTH-1:0] dtcm_wdata;
    reg [IO_MAP_WIDTH-1:0] dtcm_rdata;
    wire dtcm_rw;
    reg dtcm_ready;

    // GPIO 接口信号
    wire [IO_MAP_WIDTH-1:0] gpio_addr;
    wire [IO_MAP_WIDTH-1:0] gpio_wdata;
    reg [IO_MAP_WIDTH-1:0] gpio_rdata;
    wire gpio_we;
    reg gpio_ready;

    // RTC 接口信号
    wire [IO_MAP_WIDTH-1:0] rtc_addr;
    wire [IO_MAP_WIDTH-1:0] rtc_wdata;
    reg [IO_MAP_WIDTH-1:0] rtc_rdata;
    wire rtc_we;
    reg rtc_ready;

    // 实例化 memory_arbiter 模块
    memory_arbiter #(
        .IO_MAP_WIDTH(IO_MAP_WIDTH),
        .DTCM_BASE_ADDR(DTCM_BASE_ADDR),
        .DTCM_ADDR_END(DTCM_ADDR_END),
        .GPIO_BASE_ADDR(GPIO_BASE_ADDR),
        .GPIO_ADDR_END(GPIO_ADDR_END),
        .RTC_BASE_ADDR(RTC_BASE_ADDR),
        .RTC_ADDR_END(RTC_ADDR_END)
    ) uut (
        .clk(clk),
        .rst(rst),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_rw(cpu_rw),
        .cpu_ready(cpu_ready),
        .dtcm_addr(dtcm_addr),
        .dtcm_wdata(dtcm_wdata),
        .dtcm_rdata(dtcm_rdata),
        .dtcm_rw(dtcm_rw),
        .dtcm_ready(dtcm_ready),
        .gpio_addr(gpio_addr),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_we(gpio_we),
        .gpio_ready(gpio_ready),
        .rtc_addr(rtc_addr),
        .rtc_wdata(rtc_wdata),
        .rtc_rdata(rtc_rdata),
        .rtc_we(rtc_we),
        .rtc_ready(rtc_ready)
    );

    // 时钟生成
    always #5 clk = ~clk;  // 时钟周期为 10ns

    // 初始化和测试过程
    initial begin
        // 初始化信号
        clk = 0;
        rst = 1;
        cpu_addr = 0;
        cpu_wdata = 0;
        cpu_rw = 0;
        dtcm_rdata = 0;
        dtcm_ready = 0;
        gpio_rdata = 0;
        gpio_ready = 0;
        rtc_rdata = 0;
        rtc_ready = 0;

        // 复位
        #20;
        rst = 0;

        // --- Test 1: 4字节对齐测试（DTCM） ---
        // 写入 DTCM 地址 0x000
        #10;
        cpu_addr = 32'h0000_0000;  // DTCM 地址
        cpu_wdata = 32'hDEADBEEF;  // 数据
        cpu_rw = 1;  // 写操作
        dtcm_ready = 1;  // DTCM 准备好信号
        #10;
        dtcm_ready = 0;  // 完成操作

        // 读取 DTCM 地址 0x000
        #10;
        cpu_addr = 32'h0000_0000;
        cpu_rw = 0;  // 读操作
        dtcm_rdata = 32'hDEADBEEF;  // 返回数据
        dtcm_ready = 1;  // DTCM 准备好
        #10;
        dtcm_ready = 0;  // 完成操作

        // --- Test 2: GPIO 4字节对齐测试 ---
        // 写入 GPIO 地址 0x1000
        #10;
        cpu_addr = 32'h0000_1000;  // GPIO 地址
        cpu_wdata = 32'h12345678;  // 数据
        cpu_rw = 1;  // 写操作
        gpio_ready = 1;  // GPIO 准备好信号
        #10;
        gpio_ready = 0;  // 完成操作

        // 读取 GPIO 地址 0x1000
        #10;
        cpu_addr = 32'h0000_1000;
        cpu_rw = 0;  // 读操作
        gpio_rdata = 32'h12345678;  // 返回数据
        gpio_ready = 1;  // GPIO 准备好信号
        #10;
        gpio_ready = 0;  // 完成操作

        // --- Test 3: RTC 4字节对齐测试 ---
        // 写入 RTC 地址 0x2000
        #10;
        cpu_addr = 32'h0000_2000;  // RTC 地址
        cpu_wdata = 32'h87654321;  // 数据
        cpu_rw = 1;  // 写操作
        rtc_ready = 1;  // RTC 准备好信号
        #10;
        rtc_ready = 0;  // 完成操作

        // 读取 RTC 地址 0x2000
        #10;
        cpu_addr = 32'h0000_2000;
        cpu_rw = 0;  // 读操作
        rtc_rdata = 32'h87654321;  // 返回数据
        rtc_ready = 1;  // RTC 准备好信号
        #10;
        rtc_ready = 0;  // 完成操作

        // --- 边界测试: 读取 DTCM 边界地址 0xFFC ---
        #10;
        cpu_addr = 32'h0000_0FFC;  // DTCM 地址边界
        cpu_rw = 0;  // 读操作
        dtcm_rdata = 32'hAABBCCDD;  // 返回数据
        dtcm_ready = 1;  // DTCM 准备好信号
        #10;
        dtcm_ready = 0;  // 完成操作

        // 结束仿真
        $finish;
    end

endmodule
