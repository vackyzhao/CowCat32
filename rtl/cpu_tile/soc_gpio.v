module soc_gpio #(
    parameter IO_MAP_WIDTH = 32,
    parameter NUM_GPIO = 32
)(
    // 控制信号
    input wire clk,
    input wire rst,
    input wire [IO_MAP_WIDTH-1:0] gpio_wdata,
    input wire gpio_we,
    input wire [3:0] gpio_addr, // 用于选择寄存器的地址
    output reg [IO_MAP_WIDTH-1:0] gpio_rdata,
    output reg gpio_ready,
    // GPIO 接口
    output reg [NUM_GPIO-1:0] gpio_mode, // GPIO 模式引脚 寄存器地址00
    output reg [NUM_GPIO-1:0] gpio_out,  // GPIO 输出引脚  寄存器地址04
    input wire [NUM_GPIO-1:0] gpio_in    // GPIO 输入引脚  寄存器地址08
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        // 初始化寄存器
        gpio_out <= {NUM_GPIO{1'b0}};
        gpio_mode <= {NUM_GPIO{1'b0}};
        gpio_rdata <= {IO_MAP_WIDTH{1'b0}};
        gpio_ready <= 1'b0;
    end else begin
        gpio_ready <= 1'b0; // 默认保持不准备好，直到操作完成
        if (gpio_we) begin
            case (gpio_addr)
                4'h0: begin
                    gpio_mode <= gpio_wdata[NUM_GPIO-1:0]; // 写入控制寄存器（地址 0x00）
                    gpio_ready <= 1'b1; // 操作完成，准备好
                end
                4'h4: begin
                    gpio_out <= gpio_wdata[NUM_GPIO-1:0];  // 写入 GPIO 输出寄存器（地址 0x04）
                    gpio_ready <= 1'b1; // 操作完成，准备好
                end
                default: ;
            endcase
        end else begin
            case (gpio_addr)
                4'h8: begin
                    gpio_rdata <= { {IO_MAP_WIDTH-NUM_GPIO{1'b0}}, gpio_in }; // 读取 GPIO 输入寄存器（地址 0x08）
                    gpio_ready <= 1'b1; // 读取完成，准备好
                end
                default: gpio_rdata <= {IO_MAP_WIDTH{1'b0}};
            endcase
        end
    end
end

endmodule
