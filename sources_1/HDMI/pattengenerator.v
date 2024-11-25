module HDMI_patten_generate(
    input wire clk,
    input wire rst,
    input wire [23:0] data,
    output reg [31:0] addr,
    output reg o_de,   
    output reg o_hs,
    output reg o_vs,
    output reg [7:0] o_data_r,    
    output reg [7:0] o_data_g,
    output reg [7:0] o_data_b
);    

    // 新的水平和垂直计数变量
    reg [11:0] hs_count = 12'b0;
    reg [11:0] vs_count = 12'b0;
    reg [11:0] frame_count = 12'b0;

    // 800x600分辨率的水平和垂直时序参数
    parameter H_TOTAL = 1056;  // 水平总周期
    parameter H_SYNC = 128;    // 水平同步脉冲宽度
    parameter H_BACK = 88;     // 水平后沿
    parameter H_ACTIVE = 800;  // 有效显示区域
    parameter H_FRONT = 40;    // 水平前沿

    parameter V_TOTAL = 628;   // 垂直总周期
    parameter V_SYNC = 4;      // 垂直同步脉冲宽度
    parameter V_BACK = 23;     // 垂直后沿
    parameter V_ACTIVE = 600;  // 有效显示区域
    parameter V_FRONT = 1;     // 垂直前沿

    always @(*) begin
        // 设置显示区域
        if (((hs_count >= (H_SYNC + H_BACK)) && (hs_count < (H_SYNC + H_BACK + H_ACTIVE))) &&
            ((vs_count >= (V_SYNC + V_BACK)) && (vs_count < (V_SYNC + V_BACK + V_ACTIVE)))) begin
            o_de <= 1'b1;

            // 设置微软标志的显示区域
            if (hs_count >= (H_SYNC + H_BACK + 300) && hs_count < (H_SYNC + H_BACK + 500) &&
                vs_count >= (V_SYNC + V_BACK + 200) && vs_count < (V_SYNC + V_BACK + 400)) begin
                
                // 微软标志四块颜色
                if (hs_count < (H_SYNC + H_BACK + 400) && vs_count < (V_SYNC + V_BACK + 300)) begin
                    // 左上角 - 红色
                    o_data_r <= 8'b1111_0000;
                    o_data_g <= 8'b0000_0000;
                    o_data_b <= 8'b0000_0000;
                end else if (hs_count >= (H_SYNC + H_BACK + 400) && vs_count < (V_SYNC + V_BACK + 300)) begin
                    // 右上角 - 绿色
                    o_data_r <= 8'b0000_0000;
                    o_data_g <= 8'b1111_0000;
                    o_data_b <= 8'b0000_0000;
                end else if (hs_count < (H_SYNC + H_BACK + 400) && vs_count >= (V_SYNC + V_BACK + 300)) begin
                    // 左下角 - 蓝色
                    o_data_r <= 8'b0000_0000;
                    o_data_g <= 8'b0000_0000;
                    o_data_b <= 8'b1111_0000;
                end else begin
                    // 右下角 - 黄色
                    o_data_r <= 8'b1111_1111;
                    o_data_g <= 8'b1111_1111;
                    o_data_b <= 8'b0000_0000;
                end
            end else begin
                // 其他区域显示背景颜色
                o_data_r <= 8'b1111_1111;
                o_data_g <= 8'b1111_1111;
                o_data_b <= 8'b1111_1111;
            end
        end else begin
            o_de <= 1'b0;
            o_data_r <= 8'b0;
            o_data_g <= 8'b0;
            o_data_b <= 8'b0;
        end
    end

    // 水平计数
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            hs_count <= 12'b0;
        end else begin
            if (hs_count < H_TOTAL - 1) begin
                hs_count <= hs_count + 1;
            end else begin
                hs_count <= 12'b0;
            end
            
            // 设置水平同步信号
            if (hs_count < H_SYNC) begin
                o_hs <= 1'b0;
            end else begin
                o_hs <= 1'b1;
            end
        end
    end

    // 垂直计数
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            vs_count <= 12'b0;
            frame_count <= 12'b0;
        end else begin
            if (hs_count == H_TOTAL - 1) begin
                if (vs_count < V_TOTAL - 1) begin
                    vs_count <= vs_count + 1;
                end else begin
                    vs_count <= 12'b0;
                    frame_count <= frame_count + 1;
                end
            end
            
            // 设置垂直同步信号
            if (vs_count < V_SYNC) begin
                o_vs <= 1'b0;
            end else begin
                o_vs <= 1'b1;
            end
        end
    end

endmodule
