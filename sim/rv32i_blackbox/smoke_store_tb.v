`timescale 1ns/1ps

module rv32i_blackbox_tb;
    reg clk;
    reg rst;
    reg dm_ack;
    reg im_ack;
    reg [31:0] im_inst;
    reg [31:0] dm_load;

    wire [31:0] dm_addr;
    wire [31:0] dm_store;
    wire [31:0] im_addr;
    wire [3:0]  dm_ctl;
    wire        mem_req;
    wire        mem_we;
    wire        mem_re;

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

    // clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // instruction memory always ready
    initial begin
        im_ack = 1'b1;
    end

    // instruction ROM (combinational)
    always @(*) begin
        case (im_addr)
        32'h00000000: im_inst = 32'h00500093;
        32'h00000004: im_inst = 32'h00308113;
        32'h00000008: im_inst = 32'h00410193;
        32'h0000000c: im_inst = 32'h00118213;
        32'h00000010: im_inst = 32'h10000293;
        32'h00000014: im_inst = 32'h00000013;
        32'h00000018: im_inst = 32'h00000013;
        32'h0000001c: im_inst = 32'h0042a023;
        32'h00000020: im_inst = 32'h00000013;
        32'h00000024: im_inst = 32'h00000013;
        32'h00000028: im_inst = 32'h00000013;
        32'h0000002c: im_inst = 32'h00000013;
        32'h00000030: im_inst = 32'h00000013;
        32'h00000034: im_inst = 32'h00000013;
        32'h00000038: im_inst = 32'h00000013;
        32'h0000003c: im_inst = 32'h00000013;
        default: im_inst = 32'h00000013; // nop
        endcase
    end

    // ===== data memory model (shared) =====
    dmem_model #(
        .DEPTH_WORDS (256),
        .ADDR_LSB    (2),
        .ADDR_MSB    (9),
        .BASE_LATENCY(3)
    ) dmem (
        .clk     (clk),
        .rst     (rst),
        .mem_req (mem_req),
        .mem_we  (mem_we),
        .mem_re  (mem_re),
        .dm_addr (dm_addr),
        .dm_store(dm_store),
        .dm_ctl  (dm_ctl),
        .dm_ack  (dm_ack),
        .dm_load (dm_load)
    );

    // ========= tracing =========
    localparam integer TRACE = 1;
    integer cyc;

    initial begin
        cyc = 0;
        if (TRACE) begin
            $dumpfile("/tmp/smoke_store.vcd");
            $dumpvars(0, rv32i_blackbox_tb);
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            cyc <= 0;
        end else begin
            cyc <= cyc + 1;
            if (TRACE && cyc < 200) begin
                // Print a short window; for longer traces use VCD.
                $display("[cyc=%0d] hold=%b flush=%b pc_id=%h inst_id=%h inst_ex=%h inst_ma=%h inst_wb=%h | A_sel=%b B_sel=%b | rd=%0d reg_wrt=%b din=%h | mem_req=%b we=%b re=%b ack=%b dm_addr=%h dm_store=%h dm_load=%h dm_ctl=%b",
                         cyc,
                         uut.hold,
                         uut.flush,
                         uut.pc_id,
                         uut.inst_id,
                         uut.inst_ex,
                         uut.inst_ma,
                         uut.inst_wb,
                         uut.A_sel,
                         uut.B_sel,
                         uut.rd,
                         uut.reg_wrt,
                         uut.din,
                         mem_req, mem_we, mem_re, dm_ack,
                         dm_addr, dm_store, dm_load, dm_ctl);
            end
        end
    end

    // reset + timeout + checks
    initial begin
        rst = 1'b0;
        #20; rst = 1'b1;

        // run
        #( 800 * 10 );

        // checks
        if (dmem.mem[32'h00000100 >> 2] !== 32'h0000000d) begin
            $display("FAIL: mem[0x100] exp=0000000d got=%h", dmem.mem[32'h00000100 >> 2]);
            $fatal(1);
        end

        $display("PASS: smoke_store");
        $finish;
    end
endmodule
