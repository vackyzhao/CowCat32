module dual_port_ram #(
    parameter WIDTH = 3,     // 每个存储单元的位宽
    parameter COLS = 100,    // 列数
    parameter ROWS = 75      // 行数
)(
    input wire clk,                  // 时钟信号
    input wire we_a,                 // 端口 A 的写使能
    input wire [6:0] addr_a_x,       // 端口 A 的 X 地址 (0-99)
    input wire [6:0] addr_a_y,       // 端口 A 的 Y 地址 (0-74)
    input wire [WIDTH-1:0] data_in_a,// 端口 A 的写入数据
    output reg [WIDTH-1:0] data_out_a,// 端口 A 的读取数据
    
    input wire we_b,                 // 端口 B 的写使能
    input wire [6:0] addr_b_x,       // 端口 B 的 X 地址 (0-99)
    input wire [6:0] addr_b_y,       // 端口 B 的 Y 地址 (0-74)
    input wire [WIDTH-1:0] data_in_b,// 端口 B 的写入数据
    output reg [WIDTH-1:0] data_out_b// 端口 B 的读取数据
);

    // 内部存储器声明
    reg [WIDTH-1:0] memory [0:COLS*ROWS-1];

    // 计算平面地址
    wire [13:0] addr_a = addr_a_y * COLS + addr_a_x;
    wire [13:0] addr_b = addr_b_y * COLS + addr_b_x;

    // 端口 A 操作
    always @(posedge clk) begin
        if (we_a)
            memory[addr_a] <= data_in_a;
        data_out_a <= memory[addr_a];
    end

    // 端口 B 操作
    always @(posedge clk) begin
        if (we_b)
            memory[addr_b] <= data_in_b;
        data_out_b <= memory[addr_b];
    end

endmodule
