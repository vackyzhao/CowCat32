`timescale 1ns/1ps

module timer_mmio_tb;
    reg clk;
    reg rst;

    reg        req;
    reg        we;
    reg [11:0] addr;
    reg [31:0] wdata;
    reg [3:0]  wstrb;
    wire [31:0] rdata;
    wire        ack;

    reg [1023:0] vcdfile;
    integer dump_en;

    // 100MHz clock -> divider=100 gives 1MHz mtime
    timer_mmio #(.CLK_HZ(100_000_000)) dut (
        .clk(clk),
        .rst(rst),
        .req(req),
        .we(we),
        .addr(addr),
        .wdata(wdata),
        .wstrb(wstrb),
        .rdata(rdata),
        .ack(ack)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task mmio_wr(input [11:0] off, input [31:0] val);
        begin
            @(posedge clk);
            req <= 1'b1; we <= 1'b1; addr <= off; wdata <= val; wstrb <= 4'hF;
            @(posedge clk);
            req <= 1'b0; we <= 1'b0; wstrb <= 4'h0;
        end
    endtask

    task mmio_rd(input [11:0] off, output [31:0] val);
        begin
            @(posedge clk);
            req <= 1'b1; we <= 1'b0; addr <= off; wstrb <= 4'h0;
            @(posedge clk);
            val = rdata;
            req <= 1'b0;
        end
    endtask

    task read_mtime(output [63:0] t);
        reg [31:0] hi, lo;
        begin
            mmio_rd(32'h08, hi); // HI latches
            mmio_rd(32'h04, lo); // LO snapshot
            t = {hi, lo};
        end
    endtask

    reg [63:0] t0, t1;
    reg [31:0] st;

    initial begin
        req = 0; we = 0; addr = 0; wdata = 0; wstrb = 0;
        dump_en = 0;
        if ($value$plusargs("vcd=%s", vcdfile)) dump_en = 1;
        if (dump_en) begin
            $dumpfile(vcdfile);
            $dumpvars(0, timer_mmio_tb);
        end

        rst = 0;
        repeat (5) @(posedge clk);
        rst = 1;

        // enable + clear
        mmio_wr(32'h00, 32'h2); // clear
        mmio_wr(32'h00, 32'h1); // enable

        read_mtime(t0);
        // wait until advances
        repeat (300) @(posedge clk);
        read_mtime(t1);
        if (t1 <= t0) begin
            $display("[timer_mmio_tb] FAIL mtime not increment t0=%0d t1=%0d", t0, t1);
            $fatal(1);
        end

        // set cmp = now + 20
        mmio_wr(32'h0C, t1[31:0] + 32'd20);
        mmio_wr(32'h10, 32'd0);

        // wait hit
        st = 0;
        while ((st & 32'h1) == 0) begin
            mmio_rd(32'h14, st);
        end

        $display("[timer_mmio_tb] PASS");
        $finish;
    end

endmodule
