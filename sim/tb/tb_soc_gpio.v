`timescale 1ns / 1ps

module tb_soc_gpio;

    // 参数
    parameter IO_MAP_WIDTH = 32;
    parameter NUM_GPIO = 32;

    // 信号声明
    reg clk;
    reg rst;
    reg [IO_MAP_WIDTH-1:0] gpio_wdata;
    reg gpio_we;
    reg [3:0] gpio_addr;
    wire [IO_MAP_WIDTH-1:0] gpio_rdata;
    wire gpio_ready;
    reg [NUM_GPIO-1:0] gpio_in;
    wire [NUM_GPIO-1:0] gpio_out;
    wire [NUM_GPIO-1:0] gpio_mode;

    // 实例化被测模块
    soc_gpio #(
        .IO_MAP_WIDTH(IO_MAP_WIDTH),
        .NUM_GPIO(NUM_GPIO)
    ) uut (
        .clk(clk),
        .rst(rst),
        .gpio_wdata(gpio_wdata),
        .gpio_we(gpio_we),
        .gpio_addr(gpio_addr),
        .gpio_rdata(gpio_rdata),
        .gpio_ready(gpio_ready),
        .gpio_mode(gpio_mode),
        .gpio_out(gpio_out),
        .gpio_in(gpio_in)
    );

    // 时钟生成
    always #5 clk = ~clk; // 10ns 时钟周期

    // 测试过程
    initial begin
        // 初始化
        clk = 0;
        rst = 1;
        gpio_wdata = 0;
        gpio_we = 0;
        gpio_addr = 0;
        gpio_in = 0;

        // 复位系统
        #20;
        rst = 0;

        // --- Test 1: 写入模式寄存器，设置为输出模式 ---
        #10;
        gpio_we = 1;
        gpio_addr = 4'h0;  // 地址 0x00 - 控制寄存器
        gpio_wdata = 32'hFFFFFFFF; // 设置所有 GPIO 为输出模式
        #10;
        gpio_we = 0;

        // 验证：gpio_mode 应为 0xFFFFFFFF
        #10;
        if (gpio_mode !== 32'hFFFFFFFF)
            $display("Test 1 Failed: gpio_mode != 0xFFFFFFFF");

        // --- Test 2: 写入 GPIO 输出寄存器，设置输出值 ---
        #10;
        gpio_we = 1;
        gpio_addr = 4'h4;  // 地址 0x04 - 输出寄存器
        gpio_wdata = 32'hAAAAAAAA; // 设置 GPIO 输出值
        #10;
        gpio_we = 0;

        // 验证：gpio_out 应为 0xAAAAAAAA
        #10;
        if (gpio_out !== 32'hAAAAAAAA)
            $display("Test 2 Failed: gpio_out != 0xAAAAAAAA");

        // --- Test 3: 切换到输入模式，写入 GPIO 模式寄存器 ---
        #10;
        gpio_we = 1;
        gpio_addr = 4'h0;  // 地址 0x00 - 控制寄存器
        gpio_wdata = 32'h00000000; // 设置所有 GPIO 为输入模式
        #10;
        gpio_we = 0;

        // 验证：gpio_mode 应为 0x00000000
        #10;
        if (gpio_mode !== 32'h00000000)
            $display("Test 3 Failed: gpio_mode != 0x00000000");

        // --- Test 4: 模拟输入信号，并读取 GPIO 输入寄存器 ---
        #10;
        gpio_in = 32'h55555555; // 模拟 GPIO 输入值
        gpio_addr = 4'h8;  // 地址 0x08 - 输入寄存器
        gpio_we = 0;  // 设置为读操作
        #10;

        // 验证：gpio_rdata 应为 0x55555555
        if (gpio_rdata !== 32'h55555555)
            $display("Test 4 Failed: gpio_rdata != 0x55555555");

        // --- Test 5: 并发输入与输出测试 ---
        #10;
        gpio_we = 1;
        gpio_addr = 4'h4;  // 地址 0x04 - 输出寄存器
        gpio_wdata = 32'h33333333; // 设置 GPIO 输出值
        gpio_in = 32'h77777777; // 同时设置输入值
        #10;
        gpio_we = 0;
        gpio_addr = 4'h8; // 切换到读取输入寄存器
        #10;

        // 验证：gpio_out 应为 0x33333333，gpio_rdata 应为 0x77777777
        if (gpio_out !== 32'h33333333)
            $display("Test 5 Failed: gpio_out != 0x33333333");
        if (gpio_rdata !== 32'h77777777)
            $display("Test 5 Failed: gpio_rdata != 0x77777777");

        // 等待一段时间观察输出
        #50;

        // --- Test 6: 随机输入和输出测试 ---
        repeat (5) begin
            #10;
            gpio_we = 1;
            gpio_wdata = $random;
            gpio_addr = 4'h4;  // 地址 0x04 - 输出寄存器
            #10;
            gpio_we = 0;
            gpio_in = $random;
            gpio_addr = 4'h8;  // 地址 0x08 - 输入寄存器
            #10;
            $display("Random Test: gpio_wdata = %h, gpio_out = %h, gpio_in = %h, gpio_rdata = %h",
                     gpio_wdata, gpio_out, gpio_in, gpio_rdata);
        end

        // 测试结束
        $finish;
    end

endmodule
