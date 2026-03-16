module soc_top (
    input wire clk,         // 主时钟信号8MHz
    input wire rtc_clk,     // RTC 时钟信号32.768kHz
    input wire rst,         // 全局复位信号
    inout wire [31:0] gpio  // GPIO 外设信号
);

// ITCM信号
wire [31:0] cpu_iaddr;     // CPU 请求的ITCM地址
wire [31:0] cpu_idata;     // CPU 请求的ITCM数据
wire im_ready;             // ITCM 访问完成信号

// DTCM信号
wire [31:0] cpu_daddr;     // CPU 请求的DTCM地址
wire [31:0] cpu_dwdata;    // CPU 写入的DTCM数据
wire [31:0] cpu_drdata;    // CPU 读取的DTCM数据 
wire cpu_rw;               // CPU 读写使能
wire cpu_ready;            // CPU 访问完成信号

// 内存总线信号
wire [31:0] mem_daddr;     // 内存请求地址
wire [31:0] mem_dwdata;    // 内存写入数据
wire [31:0] mem_drdata;    // 内存读取数据
wire mem_rw;               // 内存读写使能
wire mem_ready;            // 内存访问完成信号

// 各模块的信号
wire [31:0] itcm_rdata, dtcm_rdata, gpio_rdata, rtc_rdata;
wire itcm_ready, dtcm_ready, gpio_ready, rtc_ready;

// GPIO引脚信号
wire [31:0] gpio_mode, gpio_out, gpio_in;   // GPIO模式, 输出, 输入

// CPU 实例化
SynCPU SynCPU_inst (
    .dm_load(cpu_drdata),      // CPU 从 DTCM 或 ITCM 读取数据
    .dm_addr(cpu_daddr),       // CPU 请求的地址
    .dm_store(cpu_dwdata),     // CPU 向 DTCM 写入数据
    .im_addr(cpu_iaddr),       // CPU 请求的ITCM地址
    .im_inst(cpu_idata),       // CPU 从 ITCM 读取指令
    .dm_ctl(cpu_rw),           // CPU 读写控制
    .clk(clk), 
    .rst(~rst), 
    .dm_ack(cpu_ready),        // 内存访问完成信号
    .im_ack(im_ready)          // ITCM 访问完成信号
);

// 内存仲裁器模块
memory_arbiter mem_arbiter_inst (
    .clk(clk),
    .rst(rst),
    
    // CPU 请求信号
    .cpu_addr(cpu_daddr),        // CPU 请求的地址
    .cpu_wdata(cpu_dwdata),      // CPU 写入的数据
    .cpu_rdata(cpu_drdata),      // CPU 读取的数据
    .cpu_rw(cpu_rw),             // CPU 读写控制信号
    .cpu_ready(cpu_ready),       // CPU 访问完成信号
    
    // DTCM 接口
    .dtcm_addr(cpu_daddr),       // DTCM 请求的地址
    .dtcm_wdata(cpu_dwdata),     // DTCM 写入的数据
    .dtcm_rdata(dtcm_rdata),     // DTCM 读取的数据
    .dtcm_rw(dtcm_rw),           // DTCM 读写控制信号（独立控制）
    .dtcm_ready(dtcm_ready),     // DTCM 访问完成信号

    // GPIO 接口
    .gpio_addr(cpu_daddr),
    .gpio_wdata(cpu_dwdata),
    .gpio_rdata(gpio_rdata),
    .gpio_rw(gpio_rw),           // GPIO 读写控制信号（独立控制）
    .gpio_ready(gpio_ready),

    // RTC 接口
    .rtc_addr(cpu_daddr),
    .rtc_wdata(cpu_dwdata),
    .rtc_rdata(rtc_rdata),
    .rtc_rw(rtc_rw),             // RTC 读写控制信号（独立控制）
    .rtc_ready(rtc_ready)
);



// GPIO 模块实例化
soc_gpio gpio_ctrl (
    .clk(clk),
    .rst(rst),
    .gpio_wdata(cpu_dwdata),   // CPU 写入GPIO的数据
    .gpio_we(gpio_rw),         // 只对 GPIO 地址范围有效的写使能信号
    .gpio_addr(cpu_daddr[3:0]),// GPIO地址（4位对齐）
    .gpio_rdata(gpio_rdata),   // CPU 读取GPIO的数据
    .gpio_ready(gpio_ready),   // GPIO 访问完成信号
    // GPIO 信号
    .gpio_mode(gpio_mode),     // GPIO模式寄存器
    .gpio_out(gpio_out),       // GPIO输出寄存器
    .gpio_in(gpio_in)          // GPIO输入寄存器
);

// RTC 模块实例化
soc_rtc rtc_inst (
    .clk(clk),                // 主时钟信号
    .rtc_clk(rtc_clk),        // RTC 时钟信号
    .rst(rst),                // 复位信号
    .rtc_rdata(rtc_rdata),    // RTC 读取的数据
    .rtc_we(rtc_rw),          // 只对 RTC 地址范围有效的写使能信号
    .rtc_ready(rtc_ready)     // RTC 访问完成信号
);
// 数据存储器 DTCM 模块
dtcm dtcm_inst (
    .clk(clk),
    .addr(cpu_daddr),         // DTCM 请求的地址
    .wdata(cpu_dwdata),       // DTCM 写入的数据
    .rdata(dtcm_rdata),       // DTCM 返回的读取数据
    .rw(cpu_rw),              // 读写控制信号
    .ready(dtcm_ready)        // DTCM 访问完成信号
);

// ITCM 模块实例化
itcm itcm_inst (
    .clk(clk),                // 时钟信号
    .addr(cpu_iaddr),         // 地址信号 (从 CPU 接收到的地址)
    .data_out(cpu_idata),    // 输出的指令数据
    .ack(im_ready)          // 访问完成信号
);


// IOBUF 实例化，用于处理双向 GPIO 信号
genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : gpio_iobuf
        IOBUF iobuf_inst (
            .I(gpio_out[i]),
            .O(gpio_in[i]),
            .IO(gpio[i]),
            .T(~gpio_mode[i])  // 当 gpio_mode 为 1 时，T 为 0，IO 为输出；当 gpio_mode 为 0 时，T 为 1，IO 为输入
        );
    end
endgenerate

endmodule