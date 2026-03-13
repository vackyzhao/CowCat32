`timescale 1ns / 1ps

module SynCPU_tb;

    // ========= 输入到 DUT =========
    reg         clk;
    reg         rst;
    reg         dm_ack;
    reg         im_ack;
    reg [31:0]  im_inst;
    reg [31:0]  dm_load;

    // ========= DUT 输出 =========
    wire [31:0] dm_addr;
    wire [31:0] dm_store;
    wire [31:0] im_addr;
    wire [3:0]  dm_ctl;
    wire        mem_req;
    wire        mem_we;
    wire        mem_re;

    // ========= 例化 DUT =========
    SynCPU uut (
        .dm_load (dm_load),
        .dm_addr (dm_addr),
        .dm_store(dm_store),
        .im_addr (im_addr),
        .im_inst (im_inst),
        .dm_ctl  (dm_ctl),
        .mem_req (mem_req),
        .mem_we  (mem_we),
        .mem_re  (mem_re),
        .clk     (clk),
        .rst     (rst),
        .dm_ack  (dm_ack),
        .im_ack  (im_ack)
    );

    // ========= 时钟 =========
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 10ns 周期
    end

    // ========= 指令 ROM（组合） =========
always @(*) begin
    case (im_addr)
        32'h0000_0000: im_inst = 32'h00500093; // addi x1, x0, 5
        32'h0000_0004: im_inst = 32'h00308113; // addi x2, x1, 3
        32'h0000_0008: im_inst = 32'h00410193; // addi x3, x2, 4
        32'h0000_000C: im_inst = 32'h00118213; // addi x4, x3, 1
        32'h0000_0010: im_inst = 32'h10000293; // addi x5, x0, 256

        32'h0000_0014: im_inst = 32'h00000013; // nop
        32'h0000_0018: im_inst = 32'h00000013; // nop

        32'h0000_001C: im_inst = 32'h0042A023; // sw x4, 0(x5)

        32'h0000_0020: im_inst = 32'h00000013; // nop
        32'h0000_0024: im_inst = 32'h00000013; // nop
        default:       im_inst = 32'h00000013; // nop
    endcase
end

    // ========= 指令存储器恒 ready =========
    initial begin
        im_ack = 1'b1;
    end

    // ========= 简单数据存储器模型 =========
    reg [31:0] data_mem [0:255];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            data_mem[i] = 32'h0;
    end

    // ========= 固定延迟数据存储器模型 =========
    // 语义：
    // 1. 看到一次有效访存请求后锁存请求
    // 2. 固定等待 LATENCY 个周期
    // 3. 然后 dm_ack 拉高 1 个周期
    // 4. 读请求返回 dm_load；写请求写入 data_mem
    localparam integer LATENCY = 3;

    reg        dmem_busy;
    reg [3:0]  dmem_cnt;

    reg        pend_we;
    reg        pend_re;
    reg [31:0] pend_addr;
    reg [31:0] pend_wdata;
    reg [3:0]  pend_ctl;

    wire data_req;
    assign data_req = mem_req && (mem_we || mem_re);

    initial begin
        dm_ack    = 1'b0;
        dm_load   = 32'h0000_0000;
        dmem_busy = 1'b0;
        dmem_cnt  = 4'd0;
        pend_we   = 1'b0;
        pend_re   = 1'b0;
        pend_addr = 32'h0;
        pend_wdata= 32'h0;
        pend_ctl  = 4'h0;
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            dm_ack    <= 1'b0;
            dm_load   <= 32'h0000_0000;
            dmem_busy <= 1'b0;
            dmem_cnt  <= 4'd0;
            pend_we   <= 1'b0;
            pend_re   <= 1'b0;
            pend_addr <= 32'h0;
            pend_wdata<= 32'h0;
            pend_ctl  <= 4'h0;
        end
        else begin
            // 默认 ack 只保持一个周期脉冲
            dm_ack <= 1'b0;

            if (!dmem_busy) begin
                // 空闲态：接收一个新的访存事务
                if (data_req) begin
                    dmem_busy  <= 1'b1;
                    dmem_cnt   <= LATENCY;

                    pend_we    <= mem_we;
                    pend_re    <= mem_re;
                    pend_addr  <= dm_addr;
                    pend_wdata <= dm_store;
                    pend_ctl   <= dm_ctl;
                end
            end
            else begin
                // 忙态：固定等待
                if (dmem_cnt != 0) begin
                    dmem_cnt <= dmem_cnt - 1'b1;
                end
                else begin
                    // 到期响应：给一个 ack 脉冲
                    dm_ack <= 1'b1;

                    // 写请求：写入 data_mem
                    if (pend_we) begin
                        // 这里先按 32bit 对齐整字写，暂不处理 byte/halfword 掩码
                        data_mem[pend_addr[9:2]] <= pend_wdata;
                    end

                    // 读请求：返回 data_mem
                    if (pend_re) begin
                        dm_load <= data_mem[pend_addr[9:2]];
                    end

                    dmem_busy <= 1'b0;
                end
            end
        end
    end

    // ========= 调试打印 =========
    always @(posedge clk) begin
        if (rst) begin
            if (data_req && !dmem_busy) begin
                $display("[%0t] NEW DMEM REQ: we=%b re=%b addr=%h wdata=%h",
                         $time, mem_we, mem_re, dm_addr, dm_store);
            end

            if (dmem_busy) begin
                $display("[%0t] DMEM BUSY: cnt=%0d", $time, dmem_cnt);
            end

            if (dm_ack) begin
                $display("[%0t] DMEM ACK : we=%b re=%b addr=%h rdata=%h",
                         $time, pend_we, pend_re, pend_addr, dm_load);
            end
        end
    end

    // ========= 初始激励 =========
    initial begin
        rst = 1'b0;
        #20;
        rst = 1'b1;

        #400;
        $stop;
    end

endmodule