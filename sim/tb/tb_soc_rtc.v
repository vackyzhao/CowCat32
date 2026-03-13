`timescale 1ns / 1ps

module tb_soc_rtc;

    // 参数
    parameter IO_MAP_WIDTH = 32;

    // 信号声明
    reg clk;
    reg rtc_clk;
    reg rst;
    reg [IO_MAP_WIDTH-1:0] rtc_wdata;
    reg rtc_we;
    wire [IO_MAP_WIDTH-1:0] rtc_rdata;
    wire rtc_ready;

    // 实例化被测模块
    soc_rtc #(
        .IO_MAP_WIDTH(IO_MAP_WIDTH)
    ) uut (
        .clk(clk),
        .rtc_clk(rtc_clk),
        .rst(rst),
        .rtc_wdata(rtc_wdata),
        .rtc_we(rtc_we),
        .rtc_rdata(rtc_rdata),
        .rtc_ready(rtc_ready)
    );

    // 时钟生成
    always #1 clk = ~clk;      // 10ns 时钟周期
    always #7.5 rtc_clk = ~rtc_clk; // 15ns 时钟周期

    // 初始化和测试过程
    initial begin
        // 初始化信号
        clk = 0;
        rtc_clk = 0;
        rst = 1;
        rtc_wdata = 0;
        rtc_we = 0;

        // 复位
        #20;
        rst = 0;

        // 等待一段时间观察结果
        #200;

        // 结束仿真
        $finish;
    end

endmodule