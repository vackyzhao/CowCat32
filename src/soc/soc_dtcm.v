module dtcm #(
    parameter IO_MAP_WIDTH = 32,
    parameter ADDR_WIDTH = 12 // 地址宽度，4KB内存
)(
    input wire clk,
    input wire rst,
    input wire [ADDR_WIDTH-1:0] addr,        // 地址
    input wire [IO_MAP_WIDTH-1:0] wdata,     // 写数据
    input wire rw,                           // 写使能 (1: 写, 0: 读)
    output reg [IO_MAP_WIDTH-1:0] rdata,     // 读数据
    output reg ready                         // 准备好信号
);

    // 内存数组，4KB 内存，32位总线宽度
    reg [IO_MAP_WIDTH-1:0] mem [(2**(ADDR_WIDTH-2))-1:0]; // 2^(12-2) = 1024，4字节对齐

    // 控制 ready 信号的有效性，只在操作完成后保持一个时钟周期
    reg ready_next;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // 复位状态：清空输出数据和准备信号
            rdata <= 0;
            ready <= 0;
            ready_next <= 0;
        end else begin
            // 默认情况下，ready 信号保持低电平，表示未准备好
            ready <= ready_next;
            ready_next <= 1'b0; // 在每个周期初始将 ready_next 清零

            // 读写控制，rw=1时为写操作，rw=0时为读操作
            if (rw) begin
                // 写操作：将数据写入内存
                mem[addr[ADDR_WIDTH-1:2]] <= wdata;  // 地址按字对齐
                ready_next <= 1'b1;  // 写操作完成，准备好
            end else begin
                // 读操作：从内存中读取数据
                rdata <= mem[addr[ADDR_WIDTH-1:2]];  // 地址按字对齐
                ready_next <= 1'b1;  // 读操作完成，准备好
            end
        end
    end

endmodule
