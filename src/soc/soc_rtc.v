module soc_rtc #(
    parameter IO_MAP_WIDTH = 32
)(
    input wire clk,
    input wire rtc_clk,
    input wire rst,
    input wire [IO_MAP_WIDTH-1:0] rtc_wdata,
    input wire rtc_we,
    output reg [IO_MAP_WIDTH-1:0] rtc_rdata,
    output reg rtc_ready
);

reg [IO_MAP_WIDTH-1:0] rtc_reg;

// 在 rtc_clk 上递增计数器
always @(posedge rtc_clk or posedge rst) begin
    if (rst) begin
        rtc_reg <= {IO_MAP_WIDTH{1'b0}};
    end else begin
        rtc_reg <= rtc_reg + 1;
    end
end

// 在 clk 上处理读写操作
always @(posedge clk or posedge rst) begin
    if (rst) begin
        rtc_rdata <= {IO_MAP_WIDTH{1'b0}};
        rtc_ready <= 1'b0;
    end else begin
        // 忽略写操作
        rtc_rdata <= rtc_reg;
        rtc_ready <= 1'b1; // 表示RTC准备好
    end
end

endmodule