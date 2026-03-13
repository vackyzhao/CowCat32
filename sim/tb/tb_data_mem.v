`timescale 1ns / 1ps

module tb_data_mem;
    localparam DM_IDLE = 4'b0000;
    localparam DM_SB   = 4'b0001;
    localparam DM_SH   = 4'b0011;
    localparam DM_SW   = 4'b1111;
    localparam DM_LOAD = 4'b1000;

    reg         clk;
    reg         rst;
    reg  [3:0]  dm_ctl;
    reg  [31:0] addr;
    reg  [31:0] dm_store;
    wire [31:0] dm_load;
    wire        dm_ack;

    integer err_count;
    integer latency_ref;
    integer i;

    reg [7:0] model_mem [0:255];

    data_mem dut (
        .rst(rst),
        .clk(clk),
        .dm_ctl(dm_ctl),
        .addr(addr),
        .dm_store(dm_store),
        .dm_load(dm_load),
        .dm_ack(dm_ack)
    );

    always #5 clk = ~clk;

    function [31:0] model_word;
        input [31:0] a;
        reg [7:0] a0, a1, a2, a3;
        begin
            a0 = a[7:0];
            a1 = a[7:0] + 8'd1;
            a2 = a[7:0] + 8'd2;
            a3 = a[7:0] + 8'd3;
            model_word = {model_mem[a3], model_mem[a2], model_mem[a1], model_mem[a0]};
        end
    endfunction

    task fail;
        input [8*96-1:0] msg;
        begin
            err_count = err_count + 1;
            $display("[FAIL] %s @%0t", msg, $time);
        end
    endtask

    task model_reset;
        integer j;
        begin
            for (j = 0; j < 256; j = j + 1)
                model_mem[j] = 8'h00;
        end
    endtask

    task model_store;
        input [3:0]  ctl;
        input [31:0] a;
        input [31:0] w;
        reg [7:0] a0, a1, a2, a3;
        begin
            a0 = a[7:0];
            a1 = a[7:0] + 8'd1;
            a2 = a[7:0] + 8'd2;
            a3 = a[7:0] + 8'd3;
            case (ctl)
                DM_SB: begin
                    model_mem[a0] = w[7:0];
                end
                DM_SH: begin
                    model_mem[a0] = w[7:0];
                    model_mem[a1] = w[15:8];
                end
                DM_SW: begin
                    model_mem[a0] = w[7:0];
                    model_mem[a1] = w[15:8];
                    model_mem[a2] = w[23:16];
                    model_mem[a3] = w[31:24];
                end
                default: begin
                    // no write
                end
            endcase
        end
    endtask

    task wait_idle;
        begin
            dm_ctl <= DM_IDLE;
            // Wait until no in-flight request and no pending ack pulse.
            while ((dut.busy !== 1'b0) || (dut.ack_pending !== 1'b0) || (dm_ack !== 1'b0))
                @(negedge clk);
        end
    endtask

    task check_latency_fixed;
        input integer lat;
        begin
            if (latency_ref < 0) begin
                latency_ref = lat;
                $display("[INFO] learned request latency = %0d negedges", latency_ref);
            end else if (lat != latency_ref) begin
                err_count = err_count + 1;
                $display("[FAIL] latency changed: ref=%0d got=%0d @%0t", latency_ref, lat, $time);
            end
        end
    endtask

    task issue_req_and_wait_ack;
        input [3:0]  ctl;
        input [31:0] a;
        input [31:0] w;
        input [8*96-1:0] tag;
        output integer lat;
        begin : ISSUE_BLOCK
            lat = 0;
            wait_idle();
            @(negedge clk);
            dm_ctl   <= ctl;
            addr     <= a;
            dm_store <= w;

            while (dm_ack !== 1'b1) begin
                @(negedge clk);
                lat = lat + 1;
                if (lat > 40) begin
                    fail("ack timeout");
                    disable ISSUE_BLOCK;
                end
            end

            dm_ctl <= DM_IDLE;
            @(negedge clk);
            if (dm_ack !== 1'b0)
                fail("ack pulse is wider than 1 cycle");

            check_latency_fixed(lat);
            $display("[PASS] %s (lat=%0d)", tag, lat);
        end
    endtask

    task do_store;
        input [3:0]  ctl;
        input [31:0] a;
        input [31:0] w;
        input [8*96-1:0] tag;
        integer lat;
        begin
            issue_req_and_wait_ack(ctl, a, w, tag, lat);
            model_store(ctl, a, w);
        end
    endtask

    task do_load_check;
        input [31:0] a;
        input [8*96-1:0] tag;
        integer lat;
        reg [31:0] exp;
        begin
            exp = model_word(a);
            issue_req_and_wait_ack(DM_LOAD, a, 32'h0, tag, lat);
            if (dm_load !== exp) begin
                err_count = err_count + 1;
                $display("[FAIL] load mismatch exp=0x%08x got=0x%08x @%0t", exp, dm_load, $time);
            end else begin
                $display("[PASS] %s data=0x%08x", tag, dm_load);
            end
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst       = 1'b1;
        dm_ctl    = DM_IDLE;
        addr      = 32'h0;
        dm_store  = 32'h0;
        err_count = 0;
        latency_ref = -1;

        // Active-low reset.
        #2 rst = 1'b0;
        repeat (2) @(negedge clk);
        rst = 1'b1;
        model_reset();

        @(negedge clk);
        if (dm_ack !== 1'b0)
            fail("ack should be low after reset release");
        else
            $display("[PASS] reset + idle ack");

        // Idle must not trigger ack.
        dm_ctl <= DM_IDLE;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            if (dm_ack !== 1'b0)
                fail("ack asserted during idle");
        end
        $display("[PASS] idle no-ack check");

        // Basic load/store functional checks.
        do_load_check(32'h00000020, "load zero after reset");
        do_store(DM_SW, 32'h00000024, 32'hDEADBEEF, "store word");
        do_load_check(32'h00000024, "load after SW");
        do_store(DM_SB, 32'h00000025, 32'h000000AA, "store byte");
        do_load_check(32'h00000024, "byte preserve");
        do_store(DM_SH, 32'h00000026, 32'h00001234, "store halfword");
        do_load_check(32'h00000024, "halfword preserve");

        // Unsupported mask should not create request/ack and should not modify memory.
        wait_idle();
        @(negedge clk);
        dm_ctl   <= 4'b0101;
        addr     <= 32'h00000040;
        dm_store <= 32'hAAAAAAAA;
        for (i = 0; i < 10; i = i + 1) begin
            @(negedge clk);
            if (dm_ack !== 1'b0)
                fail("ack asserted for unsupported dm_ctl");
            if (dut.busy !== 1'b0)
                fail("busy asserted for unsupported dm_ctl");
        end
        dm_ctl <= DM_IDLE;
        do_load_check(32'h00000040, "unsupported mask no-write");

        // Back-to-back valid requests.
        do_store(DM_SW, 32'h00000030, 32'h11112222, "store word A");
        do_store(DM_SW, 32'h00000034, 32'h33334444, "store word B");
        do_load_check(32'h00000030, "load word A");
        do_load_check(32'h00000034, "load word B");

        if (err_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED, error count = %0d", err_count);

        #20;
        $finish;
    end
endmodule
