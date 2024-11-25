module text_renderer (
    input wire clk,                    // 时钟信号
    input wire rst,                    // 复位信号
    input wire [7:0] ascii_code,       // 输入字符的 ASCII 码
    input wire new_char,               // 高电平表示有新的字符输入
    input wire clear,                  // 高电平表示清屏指令
    input wire backspace,              // 高电平表示退格指令
    output reg we,                     // 写使能，连接到双口 RAM
    output reg [6:0] ram_addr_x,       // 双口 RAM 的 X 坐标地址
    output reg [6:0] ram_addr_y,       // 双口 RAM 的 Y 坐标地址
    output reg color_data              // 写入到双口 RAM 的颜色数据（1位：0 = 白，1 = 黑）
);

    // 字符点阵 ROM 实例化
    reg [2:0] row;  // 当前字符的行号（0-7）
    wire [7:0] font_row_data;
    font_rom font_inst (
        .ascii_code(ascii_code),
        .row(row),
        .data(font_row_data)
    );

    // 渲染尺寸 (100列x75行，每个字符8x8像素)
    parameter CHAR_WIDTH = 8;
    parameter CHAR_HEIGHT = 8;
    parameter MAX_COLS = 100; // 800 / 8
    parameter MAX_ROWS = 75;  // 600 / 8

    // 状态机状态
    localparam IDLE = 0, RENDER_CHAR = 1, BACKSPACE = 2;
    reg [1:0] state;

    // 光标位置
    reg [9:0] cursor_x;
    reg [8:0] cursor_y;

    // 光标位置控制和 RAM 写入
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cursor_x <= 0;
            cursor_y <= 0;
            we <= 0;
            state <= IDLE;
            row <= 0;
        end else if (clear) begin
            // 清除屏幕并重置光标
            cursor_x <= 0;
            cursor_y <= 0;
            we <= 0;
        end else begin
            case (state)
                IDLE: begin
                    we <= 0;
                    if (new_char) begin
                        if (ascii_code == 8'h20) begin // 空格处理
                            if (cursor_x + CHAR_WIDTH < MAX_COLS * CHAR_WIDTH)
                                cursor_x <= cursor_x + CHAR_WIDTH;
                            else begin
                                cursor_x <= 0;
                                if (cursor_y + CHAR_HEIGHT < MAX_ROWS * CHAR_HEIGHT)
                                    cursor_y <= cursor_y + CHAR_HEIGHT;
                                else
                                    cursor_y <= 0;  // 换到屏幕顶部
                            end
                        end else if (ascii_code == 8'h0A) begin // 换行处理
                            cursor_x <= 0;
                            if (cursor_y + CHAR_HEIGHT < MAX_ROWS * CHAR_HEIGHT)
                                cursor_y <= cursor_y + CHAR_HEIGHT;
                            else
                                cursor_y <= 0;
                        end else begin
                            state <= RENDER_CHAR;
                            row <= 0;
                        end
                    end else if (backspace) begin
                        state <= BACKSPACE;
                    end
                end

                RENDER_CHAR: begin 
                    // 渲染字符并写入视频缓冲
                    if (row < CHAR_HEIGHT) begin
                        // 写入颜色数据到视频缓冲
                        we <= 1;
                        ram_addr_x <= (cursor_x >> 3) + row; // 当前字符的列地址
                        ram_addr_y <= (cursor_y >> 3);       // 当前字符的行地址
                        color_data <= font_row_data[CHAR_WIDTH - 1 - row]; // 字体数据行的位（1 表示黑，0 表示白）

                        row <= row + 1;
                    end else begin
                        row <= 0;
                        we <= 0;

                        // 移动光标
                        if (cursor_x + CHAR_WIDTH < MAX_COLS * CHAR_WIDTH)
                            cursor_x <= cursor_x + CHAR_WIDTH;
                        else begin
                            cursor_x <= 0;
                            if (cursor_y + CHAR_HEIGHT < MAX_ROWS * CHAR_HEIGHT)
                                cursor_y <= cursor_y + CHAR_HEIGHT;
                            else
                                cursor_y <= 0;
                        end
                        state <= IDLE;
                    end
                end

                BACKSPACE: begin
                    // 退格处理
                    if (cursor_x > 0) begin
                        cursor_x <= cursor_x - CHAR_WIDTH;  // 光标左移一个字符宽度
                    end else if (cursor_y > 0) begin
                        cursor_y <= cursor_y - CHAR_HEIGHT; // 换到上一行
                        cursor_x <= (MAX_COLS - 1) * CHAR_WIDTH; // 到行尾
                    end

                    // 清除当前光标位置的字符
                    we <= 1;
                    ram_addr_x <= cursor_x >> 3;
                    ram_addr_y <= cursor_y >> 3;
                    color_data <= 0; // 白色（清除显示）

                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
