`timescale 1ns/1ps

module gpio_mmio_tb;
    reg clk;
    reg rst;

    // MMIO
    reg        req;
    reg        we;
    reg [11:0] addr;
    reg [31:0] wdata;
    reg [3:0]  wstrb;
    wire [31:0] rdata;
    wire        ack;

    // pins
    reg  [31:0] gpio_in;
    wire [31:0] gpio_out;
    wire [31:0] gpio_dir;

    // plusargs
    reg [1023:0] vcdfile;
    integer dump_en;

    gpio_mmio dut (
        .clk(clk),
        .rst(rst),
        .req(req),
        .we(we),
        .addr(addr),
        .wdata(wdata),
        .wstrb(wstrb),
        .rdata(rdata),
        .ack(ack),
        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .gpio_dir(gpio_dir)
    );

    // 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    task mmio_wr(input [11:0] off, input [31:0] val, input [3:0] be);
        begin
            @(posedge clk);
            req <= 1'b1; we <= 1'b1; addr <= off; wdata <= val; wstrb <= be;
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

    reg [31:0] v;

    initial begin
        req=0; we=0; addr=0; wdata=0; wstrb=0;
        gpio_in = 32'h11223344;

        dump_en = 0;
        if ($value$plusargs("vcd=%s", vcdfile)) dump_en = 1;
        if (dump_en) begin
            $dumpfile(vcdfile);
            $dumpvars(0, gpio_mmio_tb);
        end

        rst = 0;
        repeat (5) @(posedge clk);
        rst = 1;

        // DIR full write/readback
        mmio_wr(32'h04, 32'hFFFF_FFFF, 4'hF);
        mmio_rd(32'h04, v);
        if (v !== 32'hFFFF_FFFF) begin
            $display("[gpio_mmio_tb] FAIL dir rb %08x", v);
            $fatal(1);
        end

        // DATA full write/readback
        mmio_wr(32'h00, 32'hA5A5_5A5A, 4'hF);
        mmio_rd(32'h00, v);
        if (v !== 32'hA5A5_5A5A) begin
            $display("[gpio_mmio_tb] FAIL data rb %08x", v);
            $fatal(1);
        end

        // DATA byte write mask: update only byte0 to 0x99
        mmio_wr(32'h00, 32'h0000_0099, 4'h1);
        mmio_rd(32'h00, v);
        if (v !== 32'hA5A5_5A99) begin
            $display("[gpio_mmio_tb] FAIL byte mask %08x", v);
            $fatal(1);
        end

        // IN read
        mmio_rd(32'h08, v);
        if (v !== 32'h11223344) begin
            $display("[gpio_mmio_tb] FAIL in %08x", v);
            $fatal(1);
        end

        $display("[gpio_mmio_tb] PASS");
        $finish;
    end

endmodule
