`timescale 1ns/1ps

module rv32i_riscvtests_tb;
    reg clk;
    reg rst;

    // CPU ports
    wire [31:0] dm_addr;
    wire [31:0] dm_store;
    wire [31:0] im_addr;
    wire [3:0]  dm_ctl;
    wire        mem_req;
    wire        mem_we;
    wire        mem_re;

    wire [31:0] dm_load;
    wire        dm_ack;

    reg  [31:0] im_inst;
    reg         im_ack;

    // Unified memory (instruction fetch + data)
    localparam integer MEM_WORDS = 131072; // 512 KiB
    reg [31:0] mem [0:MEM_WORDS-1];

    // plusargs
    reg [1023:0] hexfile;
    reg [1023:0] tracefile;
    reg [1023:0] vcdfile;
    integer seed;
    integer tfd;
    integer quiet_trace;
    integer dump_en;

    localparam [31:0] TOHOST_ADDR = 32'h0000_1000;

    // DUT
    wire        trace_valid;
    wire [31:0] trace_pc;
    wire [31:0] trace_inst;
    wire [4:0]  trace_rd;
    wire [31:0] trace_rd_data;

    SynCPU uut (
        .dm_load       (dm_load),
        .dm_addr       (dm_addr),
        .dm_store      (dm_store),
        .im_addr       (im_addr),
        .im_inst       (im_inst),
        .dm_ctl        (dm_ctl),
        .mem_req       (mem_req),
        .mem_we        (mem_we),
        .mem_re        (mem_re),
        .trace_valid   (trace_valid),
        .trace_pc      (trace_pc),
        .trace_inst    (trace_inst),
        .trace_rd      (trace_rd),
        .trace_rd_data (trace_rd_data),
        .clk           (clk),
        .rst           (rst),
        .dm_ack        (dm_ack),
        .im_ack        (im_ack)
    );

    // clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // instruction side always ready
    initial begin
        im_ack = 1'b1;
    end

    // load program image
    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0013; // nop
        end

        quiet_trace = 0;
        if ($test$plusargs("quiet_trace")) quiet_trace = 1;

        if (!$value$plusargs("hex=%s", hexfile)) begin
            hexfile = "prog.vh";
        end
        if ($value$plusargs("trace=%s", tracefile)) begin
            tfd = $fopen(tracefile, "w");
            if (tfd == 0) begin
                $display("[tb] ERROR: cannot open trace file: %0s", tracefile);
                $fatal(1);
            end
        end else begin
            tfd = 0;
        end

        if ($value$plusargs("seed=%d", seed)) begin
            $urandom(seed);
        end

        $display("[tb] loading hex: %0s", hexfile);
        $readmemh(hexfile, mem);

        // VCD control:
        //   +novcd      : disable dumping (recommended for parallel runs)
        //   +vcd=<path> : override VCD output path
        dump_en = 1;
        if ($test$plusargs("novcd")) dump_en = 0;
        if (!$value$plusargs("vcd=%s", vcdfile)) begin
            vcdfile = "/tmp/rv32i_riscvtests.vcd";
        end
        if (dump_en) begin
            $dumpfile(vcdfile);
            $dumpvars(0, rv32i_riscvtests_tb);
        end
    end

    // reset
    initial begin
        rst = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b1;
    end

    // instruction fetch (combinational)
    wire [31:0] im_word_idx = im_addr >> 2;
    always @(*) begin
        if (im_word_idx < MEM_WORDS)
            im_inst = mem[im_word_idx];
        else
            im_inst = 32'h0000_0013;
    end

    // data load is combinational read from unified memory
    wire [31:0] dm_word_idx = dm_addr >> 2;
    assign dm_load = (dm_word_idx < MEM_WORDS) ? mem[dm_word_idx] : 32'h0;

    // data handshake with randomized latency similar to dmem_model
    reg dmem_busy;
    reg [3:0] dmem_cnt;
    reg [31:0] pend_addr;

    wire data_req = mem_req && (mem_we || mem_re);

    function [31:0] apply_wmask;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0]  be;
        reg [31:0] m;
        begin
            m = { {8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}} };
            apply_wmask = (oldv & ~m) | (newv & m);
        end
    endfunction

    initial begin
        dmem_busy = 1'b0;
        dmem_cnt  = 0;
        pend_addr = 32'h0;
    end

    // ack generated on negedge for stable sampling at next posedge
    reg dm_ack_r;
    assign dm_ack = dm_ack_r;

    always @(negedge clk or negedge rst) begin
        if (!rst) begin
            dm_ack_r  <= 1'b0;
            dmem_busy <= 1'b0;
            dmem_cnt  <= 0;
            pend_addr <= 32'h0;
        end else begin
            dm_ack_r <= 1'b0;
            if (!dmem_busy) begin
                if (data_req) begin
                    dmem_busy <= 1'b1;
                    dmem_cnt  <= ($urandom % 7) + 1;
                    pend_addr <= dm_addr;

                    // commit store at accept-time
                    if (mem_we && (dm_word_idx < MEM_WORDS)) begin
                        mem[dm_word_idx] <= apply_wmask(mem[dm_word_idx], dm_store, dm_ctl);
                    end
                end
            end else begin
                if (dmem_cnt != 0) begin
                    dmem_cnt <= dmem_cnt - 1;
                end else begin
                    dm_ack_r  <= 1'b1;
                    dmem_busy <= 1'b0;
                end
            end
        end
    end

    // tohost monitor: detect pass/fail on any store to TOHOST_ADDR
    always @(posedge clk) begin
        if (rst && data_req && mem_we && (dm_addr == TOHOST_ADDR)) begin
            $display("[tb] tohost write: %08x", dm_store);
            if (dm_store == 32'h0000_0001) begin
                $display("PASS");
                $finish;
            end else begin
                $display("FAIL tohost=%08x", dm_store);
                $fatal(1);
            end
        end
    end

    // commit trace line (WB stage only)
    always @(posedge clk) begin
        if (rst && trace_valid) begin
            if (tfd != 0) begin
                $fdisplay(tfd, "TRACE %08x %08x x%0d=%08x", trace_pc, trace_inst, trace_rd, trace_rd_data);
            end
            if (!quiet_trace) begin
                $display("TRACE %08x %08x x%0d=%08x", trace_pc, trace_inst, trace_rd, trace_rd_data);
            end
        end
    end

    // safety timeout
    integer cyc;
    initial cyc = 0;
    always @(posedge clk) begin
        if (rst) begin
            cyc <= cyc + 1;
            if (cyc > 200000) begin
                $display("TIMEOUT");
                $fatal(1);
            end
        end
    end

endmodule
