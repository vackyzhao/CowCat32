module soc_top (
    input wire clk,         // 主时钟信号8MHz
    input wire rst        // 全局复位信号
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


endmodule