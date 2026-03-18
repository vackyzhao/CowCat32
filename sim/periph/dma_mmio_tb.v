`timescale 1ns/1ps

module dma_mmio_tb;
    reg clk;
    reg rst;

    // DMA MMIO slave (CPU-like)
    reg        s_req;
    reg        s_we;
    reg [11:0] s_addr;
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
    task mmio_wr(input [11:0] off, input [31:0] val);
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

    task mmio_rd(input [11:0] off, output [31:0] val);
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

    task clear_done_err;
        begin
            mmio_wr(12'h00C, 32'h6); // CLR_DONE | CLR_ERR
        end
    endtask

    task program_dma(input [31:0] src, input [31:0] dst, input [31:0] len);
        begin
            mmio_wr(12'h000, src);
            mmio_wr(12'h004, dst);
            mmio_wr(12'h008, len);
        end
    endtask

    task start_dma;
        begin
            mmio_wr(12'h00C, 32'h1); // START
        end
    endtask

    task wait_done_noerr;
        reg [31:0] st;
        begin
            st = 0;
            while ((st & 32'h2) == 0) begin
                mmio_rd(12'h010, st);
                if (st & 32'h4) begin
                    $display("[dma_mmio_tb] FAIL: ERR set unexpectedly, erraddr=%08x status=%08x", dut.erraddr, st);
                    $fatal(1);
                end
            end
        end
    endtask

    task expect_err(input [31:0] exp_erraddr);
        reg [31:0] st;
        reg [31:0] ea;
        reg        found;
        integer    tries;
        begin
            st = 0;
            ea = 0;
            found = 1'b0;
            for (tries = 0; tries < 20; tries = tries + 1) begin
                mmio_rd(12'h010, st);
                if (st & 32'h4) begin
                    mmio_rd(12'h014, ea);
                    if (ea !== exp_erraddr) begin
                        $display("[dma_mmio_tb] FAIL: erraddr=%08x exp=%08x", ea, exp_erraddr);
                        $fatal(1);
                    end
                    found = 1'b1;
                end
            end
            if (!found) begin
                $display("[dma_mmio_tb] FAIL: expected ERR not observed");
                $fatal(1);
            end
        end
    endtask

    task expect_start_rejected;
        reg [31:0] st;
        reg [31:0] ea;
        begin
            mmio_rd(12'h010, st);
            if ((st & 32'h4) == 0) begin
                $display("[dma_mmio_tb] FAIL: expected immediate ERR for invalid start, status=%08x", st);
                $fatal(1);
            end
            if ((st & 32'h1) != 0) begin
                $display("[dma_mmio_tb] FAIL: BUSY should not remain high on rejected start, status=%08x", st);
                $fatal(1);
            end
            mmio_rd(12'h014, ea);
            if (ea !== 32'h0) begin
                $display("[dma_mmio_tb] FAIL: rejected-start erraddr should be 0, got=%08x", ea);
                $fatal(1);
            end
        end
    endtask

    task fill_region(input [31:0] base, input integer words, input [31:0] seed);
        integer k;
        begin
            for (k = 0; k < words; k = k + 1) begin
                mem[(base>>2)+k] = seed + k;
            end
        end
    endtask

    task clear_region(input [31:0] base, input integer words);
        integer k;
        begin
            for (k = 0; k < words; k = k + 1) begin
                mem[(base>>2)+k] = 32'h0;
            end
        end
    endtask

    task expect_region(input [31:0] src, input [31:0] dst, input integer words);
        integer k;
        begin
            for (k = 0; k < words; k = k + 1) begin
                if (mem[(dst>>2)+k] !== mem[(src>>2)+k]) begin
                    $display("[dma_mmio_tb] FAIL: dst[%0d]=%08x exp=%08x", k,
                             mem[(dst>>2)+k], mem[(src>>2)+k]);
                    $fatal(1);
                end
            end
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

        // ----------------------------------------
        // 0) aligned happy path: 64B copy
        // ----------------------------------------
        fill_region(32'h0000_0400, 16, 32'hA500_0000);
        clear_region(32'h0000_0800, 16);
        clear_done_err();
        program_dma(32'h0000_0400, 32'h0000_0800, 32'd64);
        start_dma();
        wait_done_noerr();
        expect_region(32'h0000_0400, 32'h0000_0800, 16);

        // clear done and verify it clears
        clear_done_err();
        mmio_rd(12'h010, st);
        if ((st & 32'h2) != 0 || (st & 32'h4) != 0) begin
            $display("[dma_mmio_tb] FAIL: done/err not cleared after CLR bits, st=%08x", st);
            $fatal(1);
        end

        // ----------------------------------------
        // 1) aligned small transfer: single word
        // ----------------------------------------
        fill_region(32'h0000_0500, 1, 32'h1234_0000);
        clear_region(32'h0000_0900, 1);
        clear_done_err();
        program_dma(32'h0000_0500, 32'h0000_0900, 32'd4);
        start_dma();
        wait_done_noerr();
        expect_region(32'h0000_0500, 32'h0000_0900, 1);

        // ----------------------------------------
        // 2) back-to-back aligned transfers
        // ----------------------------------------
        fill_region(32'h0000_0600, 8, 32'hCAFE_1000);
        clear_region(32'h0000_0A00, 8);
        clear_done_err();
        program_dma(32'h0000_0600, 32'h0000_0A00, 32'd32);
        start_dma();
        wait_done_noerr();
        expect_region(32'h0000_0600, 32'h0000_0A00, 8);

        fill_region(32'h0000_0700, 8, 32'hFACE_2000);
        clear_region(32'h0000_0B00, 8);
        clear_done_err();
        program_dma(32'h0000_0700, 32'h0000_0B00, 32'd32);
        start_dma();
        wait_done_noerr();
        expect_region(32'h0000_0700, 32'h0000_0B00, 8);

        // ----------------------------------------
        // 3) invalid starts: len=0 or misaligned
        // ----------------------------------------
        clear_done_err();
        program_dma(32'h0000_0400, 32'h0000_0800, 32'd0);
        start_dma();
        expect_start_rejected();

        clear_done_err();
        program_dma(32'h0000_0402, 32'h0000_0800, 32'd64);
        start_dma();
        expect_start_rejected();

        clear_done_err();
        program_dma(32'h0000_0400, 32'h0000_0802, 32'd64);
        start_dma();
        expect_start_rejected();

        clear_done_err();
        program_dma(32'h0000_0400, 32'h0000_0800, 32'd66);
        start_dma();
        expect_start_rejected();

        // ----------------------------------------
        // 4) recursion guard: DMA page access must ERR
        // ----------------------------------------
        clear_done_err();
        program_dma(32'h1000_2000, 32'h0000_0800, 32'd4);
        start_dma();
        expect_err(32'h1000_2000);

        clear_done_err();
        program_dma(32'h0000_0400, 32'h1000_2000, 32'd4);
        start_dma();
        expect_err(32'h1000_2000);

        $display("[dma_mmio_tb] PASS");
        $finish;
    end

endmodule
