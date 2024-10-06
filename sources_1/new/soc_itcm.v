module itcm (
    input wire clk,                   // 时钟信号
    input wire [31:0] addr,           // 地址信号 (从 CPU 接收到的地址)
    output reg [31:0] data_out,       // 输出的指令数据
    output reg ack                    // 访问完成信号
);

    // 内存大小定义 (4KB)
    parameter ITCM_SIZE = 1024;       // 1024 x 32 bits = 4KB

    // 内存数组
    reg [31:0] memory [0:ITCM_SIZE-1];

    // 预存储的 RV32I 指令 (示例)
    initial begin
            // 1. 初始化寄存器值
        memory[0] = 32'h00100113;  // addi x2, x0, 1 (x2 = 1)
        memory[1] = 32'h00400113;  // addi x2, x0, 4 (x2 = 4, 用作存储数据)

        // 2. 写操作，将 x2 中的数据 (4) 存储到地址 0x10 处
        memory[2] = 32'h00202023;  // sw x2, 0x10(x0) (将 x2 的数据 4 存储到内存地址 0x10 处)

        // 3. 读操作，从地址 0x10 处加载数据到 x3 寄存器
        memory[3] = 32'h00002183;  // lw x3, 0x10(x0) (从内存地址 0x10 读取数据到 x3)

        // 4. 验证操作
        // 你可以在仿真波形中检查 x3 寄存器的值是否为 4 (存储的值)

        memory[4]  = 32'h00000013;  // NOP (addi x0, x0, 0，没有操作)
        memory[5]  = 32'h00000013;  // NOP (重复的 NOP 指令)
        memory[6]  = 32'h00000013;  // NOP (重复的 NOP 指令)

    end

    // 处理访问请求
    always @(posedge clk) begin
        // 4 字节对齐，忽略地址的最低两位
        data_out <= memory[addr[11:2]];  // 由于 4 字节对齐，只使用 addr[11:2] 作为地址
        ack <= 1'b1;                     // 每次读取完成后，将 ack 信号拉高，表示访问完成
    end

endmodule
