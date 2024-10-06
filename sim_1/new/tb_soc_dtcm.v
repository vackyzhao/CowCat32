`timescale 1ns / 1ps

module tb_dtcm;

    // 参数
    parameter IO_MAP_WIDTH = 32;
    parameter ADDR_WIDTH = 12;
    parameter MEM_SIZE = 1 << (ADDR_WIDTH - 2); // 4KB 内存

    // 信号声明
    reg clk;
    reg rst;
    reg [ADDR_WIDTH-1:0] addr;
    reg [IO_MAP_WIDTH-1:0] wdata;
    reg rw;
    wire [IO_MAP_WIDTH-1:0] rdata;
    wire ready;

    // 实例化被测模块
    dtcm #(
        .IO_MAP_WIDTH(IO_MAP_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .addr(addr),
        .wdata(wdata),
        .rw(rw),
        .rdata(rdata),
        .ready(ready)
    );

    // 时钟生成
    always #5 clk = ~clk; // 10ns 时钟周期

    // 测试过程
    initial begin
        // 初始化
        clk = 0;
        rst = 1;
        addr = 0;
        wdata = 0;
        rw = 0;

        // 复位系统
        #20;
        rst = 0;

        // --- Test 1: 连续写入和读取 ---
        // 连续写入地址 0x000 和 0x004
        repeat(2) begin
            rw = 1; // 写操作
            addr = addr + 12'h004; // 地址递增
            wdata = $random;  // 随机写入数据
            #10;
            rw = 0; // 读操作
            #10;
            if (ready !== 1'b1) begin
                $display("Test 1 Failed: ready signal is not high during read operation at time %t", $time);
            end
        end

        // --- Test 2: 边界测试 ---
        // 写入最小地址
        rw = 1; 
        addr = 12'h000;
        wdata = 32'hDEADBEEF;
        #10;

        // 读取最小地址
        rw = 0;
        addr = 12'h000;
        #10;
        if (rdata !== 32'hDEADBEEF || ready !== 1'b1)
            $display("Test 2 Failed: rdata != DEADBEEF at address 0x000");

        // 写入最大地址
        rw = 1;
        addr = 12'hFFC;
        wdata = 32'hAABBCCDD;
        #10;

        // 读取最大地址
        rw = 0;
        addr = 12'hFFC;
        #10;
        if (rdata !== 32'hAABBCCDD || ready !== 1'b1)
            $display("Test 2 Failed: rdata != AABBCCDD at address 0xFFC");

        // --- Test 3: 随机化读写测试 ---
        // 随机地址和数据的写入和读取
        repeat (5) begin
            rw = 1;  // 随机写操作
            addr = $random % (MEM_SIZE * 4);  // 随机生成地址
            wdata = $random;  // 随机生成数据
            #10;
            rw = 0;  // 随机读操作
            #10;
            if (ready !== 1'b1) begin
                $display("Test 3 Failed: ready signal not high for random address at time %t", $time);
            end
        end

        // --- Test 4: 连续读写交替测试 ---
        // 交替进行读写操作，验证处理正确性
        rw = 1;  // 写操作
        addr = 12'h100;
        wdata = 32'hABCDEF12;
        #10;

        rw = 0;  // 读操作
        addr = 12'h100;
        #10;
        if (rdata !== 32'hABCDEF12 || ready !== 1'b1)
            $display("Test 4 Failed: rdata != ABCDEF12 after read operation");

        // --- Test 5: 连续写入和读取不同地址 ---
        rw = 1;  // 写操作
        addr = 12'h200;
        wdata = 32'h55555555;
        #10;
        
        rw = 1;  // 写操作
        addr = 12'h204;
        wdata = 32'h66666666;
        #10;
        
        // 读取地址 0x200
        rw = 0;
        addr = 12'h200;
        #10;
        if (rdata !== 32'h55555555 || ready !== 1'b1)
            $display("Test 5 Failed: rdata != 55555555 after reading address 0x200");

        // 读取地址 0x204
        rw = 0;
        addr = 12'h204;
        #10;
        if (rdata !== 32'h66666666 || ready !== 1'b1)
            $display("Test 5 Failed: rdata != 66666666 after reading address 0x204");

        // 结束测试
        $finish;
    end

endmodule
