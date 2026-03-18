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

    localparam [11:0] DATA_OFF = 12'h000;
    localparam [11:0] DIR_OFF  = 12'h004;
    localparam [11:0] IN_OFF   = 12'h008;
    localparam [11:0] BAD_OFF  = 12'h00C;

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

        // active-low reset asserted
        rst = 0;
        repeat (2) @(posedge clk);

        // reset defaults must be zero
        if (gpio_out !== 32'h0 || gpio_dir !== 32'h0) begin
            $display("[gpio_mmio_tb] FAIL reset defaults out=%08x dir=%08x", gpio_out, gpio_dir);
            $fatal(1);
        end
        mmio_rd(DATA_OFF, v);
        if (v !== 32'h0) begin
            $display("[gpio_mmio_tb] FAIL reset DATA rb %08x", v);
            $fatal(1);
        end
        mmio_rd(DIR_OFF, v);
        if (v !== 32'h0) begin
            $display("[gpio_mmio_tb] FAIL reset DIR rb %08x", v);
            $fatal(1);
        end

        // release reset
        repeat (3) @(posedge clk);
        rst = 1;

        // DIR full write/readback
        mmio_wr(DIR_OFF, 32'hFFFF_FFFF, 4'hF);
        mmio_rd(DIR_OFF, v);
        if (v !== 32'hFFFF_FFFF) begin
            $display("[gpio_mmio_tb] FAIL dir rb %08x", v);
            $fatal(1);
        end

        // DIR byte-mask write: clear byte[15:8] only
        mmio_wr(DIR_OFF, 32'h0000_0000, 4'h2);
        mmio_rd(DIR_OFF, v);
        if (v !== 32'hFFFF_00FF) begin
            $display("[gpio_mmio_tb] FAIL dir mask rb %08x", v);
            $fatal(1);
        end

        // DATA full write/readback
        mmio_wr(DATA_OFF, 32'hA5A5_5A5A, 4'hF);
        mmio_rd(DATA_OFF, v);
        if (v !== 32'hA5A5_5A5A) begin
            $display("[gpio_mmio_tb] FAIL data rb %08x", v);
            $fatal(1);
        end

        // DATA byte write mask: update only byte0 to 0x99
        mmio_wr(DATA_OFF, 32'h0000_0099, 4'h1);
        mmio_rd(DATA_OFF, v);
        if (v !== 32'hA5A5_5A99) begin
            $display("[gpio_mmio_tb] FAIL data byte0 mask %08x", v);
            $fatal(1);
        end

        // DATA upper-half write mask only
        mmio_wr(DATA_OFF, 32'h1234_0000, 4'hC);
        mmio_rd(DATA_OFF, v);
        if (v !== 32'h1234_5A99) begin
            $display("[gpio_mmio_tb] FAIL data upper-half mask %08x", v);
            $fatal(1);
        end

        // zero strobe must not modify register
        mmio_wr(DATA_OFF, 32'hDEAD_BEEF, 4'h0);
        mmio_rd(DATA_OFF, v);
        if (v !== 32'h1234_5A99) begin
            $display("[gpio_mmio_tb] FAIL zero strobe modified data %08x", v);
            $fatal(1);
        end

        // IN read
        mmio_rd(IN_OFF, v);
        if (v !== 32'h11223344) begin
            $display("[gpio_mmio_tb] FAIL in %08x", v);
            $fatal(1);
        end

        // invalid offset read returns zero
        mmio_rd(BAD_OFF, v);
        if (v !== 32'h0) begin
            $display("[gpio_mmio_tb] FAIL bad offset read %08x", v);
            $fatal(1);
        end

        // invalid offset write must not modify DATA/DIR
        mmio_wr(BAD_OFF, 32'hFFFF_FFFF, 4'hF);
        mmio_rd(DATA_OFF, v);
        if (v !== 32'h1234_5A99) begin
            $display("[gpio_mmio_tb] FAIL bad offset write changed data %08x", v);
            $fatal(1);
        end
        mmio_rd(DIR_OFF, v);
        if (v !== 32'hFFFF_00FF) begin
            $display("[gpio_mmio_tb] FAIL bad offset write changed dir %08x", v);
            $fatal(1);
        end

        $display("[gpio_mmio_tb] PASS");
        $finish;
    end

endmodule
