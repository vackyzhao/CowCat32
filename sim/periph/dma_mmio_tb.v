`timescale 1ns/1ps

module dma_mmio_tb;
    reg clk;
    reg rst;

    // DMA MMIO slave (CPU-like)
    reg        s_req;
    reg        s_we;
    reg [31:0] s_addr;
    reg [31:0] s_wdata;
    reg [3:0]  s_wstrb;
    wire [31:0] s_rdata;
    wire        s_ack;

    // DMA master (to bus)
    wire        m_req;
    wire        m_we;
    wire        m_re;
    wire [31:0] m_addr;
    wire [31:0] m_wdata;
    wire [3:0]  m_wstrb;
    reg         m_ack;
    reg [31:0]  m_rdata;

    // plusargs
    reg [1023:0] vcdfile;
    integer dump_en;

    // DUT
    dma_mmio #(
        .DMA_BASE(32'h1000_2000),
        .PERIPH_MASK(32'hFFFF_F000)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_req(s_req),
        .s_we(s_we),
        .s_addr(s_addr),
        .s_wdata(s_wdata),
        .s_wstrb(s_wstrb),
        .s_rdata(s_rdata),
        .s_ack(s_ack),
        .m_req(m_req),
        .m_we(m_we),
        .m_re(m_re),
        .m_addr(m_addr),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_ack(m_ack),
        .m_rdata(m_rdata)
    );

    // 100MHz clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Simple on-chip memory model (8KiB = 2048 words)
    localparam integer MEM_WORDS = 2048;
    reg [31:0] mem [0:MEM_WORDS-1];

    function [31:0] apply_wmask;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0]  be;
        reg   [31:0] m;
        begin
            m = { {8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}} };
            apply_wmask = (oldv & ~m) | (newv & m);
        end
    endfunction

    wire [31:0] widx = m_addr >> 2;

    // Bus handshake: 0-wait
    always @(*) begin
        m_ack   = m_req;
        m_rdata = (widx < MEM_WORDS) ? mem[widx] : 32'h0;
    end

    always @(posedge clk) begin
        if (rst && m_req && m_we && (widx < MEM_WORDS)) begin
            mem[widx] <= apply_wmask(mem[widx], m_wdata, m_wstrb);
        end
    end

    // MMIO helper tasks
    task mmio_wr(input [31:0] off, input [31:0] val);
        begin
            @(posedge clk);
            s_req   <= 1'b1;
            s_we    <= 1'b1;
            s_addr  <= off;
            s_wdata <= val;
            s_wstrb <= 4'hF;
            @(posedge clk);
            s_req   <= 1'b0;
            s_we    <= 1'b0;
            s_wstrb <= 4'h0;
        end
    endtask

    task mmio_rd(input [31:0] off, output [31:0] val);
        begin
            @(posedge clk);
            s_req   <= 1'b1;
            s_we    <= 1'b0;
            s_addr  <= off;
            s_wstrb <= 4'h0;
            @(posedge clk);
            val = s_rdata;
            s_req <= 1'b0;
        end
    endtask

    // Test
    integer i;
    reg [31:0] st;

    initial begin
        // init
        s_req=0; s_we=0; s_addr=0; s_wdata=0; s_wstrb=0;
        for (i=0;i<MEM_WORDS;i=i+1) mem[i]=32'h0;

        dump_en = 0;
        if ($value$plusargs("vcd=%s", vcdfile)) dump_en = 1;
        if (dump_en) begin
            $dumpfile(vcdfile);
            $dumpvars(0, dma_mmio_tb);
        end

        rst = 0;
        repeat (5) @(posedge clk);
        rst = 1;

        // Fill SRC region and clear DST region.
        // Use addresses well within 8KiB.
        // SRC: 0x0000_0400 (word 0x100)
        // DST: 0x0000_0800 (word 0x200)
        for (i=0;i<16;i=i+1) begin
            mem[(32'h00000400>>2)+i] = 32'hA500_0000 + i;
            mem[(32'h00000800>>2)+i] = 32'h0;
        end

        // Program DMA
        mmio_wr(32'h00, 32'h0000_0400); // SRC
        mmio_wr(32'h04, 32'h0000_0800); // DST
        mmio_wr(32'h08, 32'd64);        // LEN

        // Clear flags and start
        mmio_wr(32'h0C, 32'h6); // CLR_DONE|CLR_ERR
        mmio_wr(32'h0C, 32'h1); // START

        // Poll done
        st = 0;
        while ((st & 32'h2) == 0) begin
            mmio_rd(32'h10, st);
            if (st & 32'h4) begin
                $display("[dma_mmio_tb] FAIL: ERR set, erraddr=%08x", dut.erraddr);
                $fatal(1);
            end
        end

        // Verify copy
        for (i=0;i<16;i=i+1) begin
            if (mem[(32'h00000800>>2)+i] !== (32'hA500_0000 + i)) begin
                $display("[dma_mmio_tb] FAIL: dst[%0d]=%08x exp=%08x", i,
                         mem[(32'h00000800>>2)+i], (32'hA500_0000 + i));
                $fatal(1);
            end
        end

        $display("[dma_mmio_tb] PASS");
        $finish;
    end

endmodule
