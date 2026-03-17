`timescale 1ns/1ps

module uart_mmio_tb;
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
    reg  uart_rx;
    wire uart_tx;

    // plusargs
    reg [1023:0] vcdfile;
    integer dump_en;

    uart_mmio #(.FIFO_DEPTH(64)) dut (
        .clk(clk),
        .rst(rst),
        .req(req),
        .we(we),
        .addr(addr),
        .wdata(wdata),
        .wstrb(wstrb),
        .rdata(rdata),
        .ack(ack),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        req = 0; we = 0; addr = 0; wdata = 0; wstrb = 0;
        uart_rx = 1'b1;

        dump_en = 0;
        if ($value$plusargs("vcd=%s", vcdfile)) dump_en = 1;
        if (dump_en) begin
            $dumpfile(vcdfile);
            $dumpvars(0, uart_mmio_tb);
        end

        rst = 0;
        repeat (5) @(posedge clk);
        rst = 1;

        // BAUDDIV=8 (fast)
        mmio_wr(32'h0C, 32'd8);
        // CTRL: TX_EN=1 RX_EN=1 LOOPBACK=1
        mmio_wr(32'h10, 32'h7);

        // send "OK\n"
        mmio_wr(32'h00, "O");
        mmio_wr(32'h00, "K");
        mmio_wr(32'h00, 8'h0A);

        // receive 3 bytes and check
        expect_rx("O");
        expect_rx("K");
        expect_rx(8'h0A);

        $display("[uart_mmio_tb] PASS");
        $finish;
    end

    task mmio_wr(input [11:0] off, input [31:0] val);
        begin
            @(posedge clk);
            req   <= 1'b1;
            we    <= 1'b1;
            addr  <= off;
            wdata <= val;
            wstrb <= 4'hF;
            @(posedge clk);
            req   <= 1'b0;
            we    <= 1'b0;
            wstrb <= 4'h0;
        end
    endtask

    task mmio_rd(input [11:0] off, output [31:0] val);
        begin
            @(posedge clk);
            req   <= 1'b1;
            we    <= 1'b0;
            addr  <= off;
            wstrb <= 4'h0;
            @(posedge clk);
            val = rdata;
            req <= 1'b0;
        end
    endtask

    task expect_rx(input [7:0] exp);
        reg [31:0] st;
        reg [31:0] v;
        begin
            // wait RX_VALID (STATUS bit3)
            st = 0;
            while ((st & 32'h8) == 0) begin
                mmio_rd(32'h08, st);
            end
            mmio_rd(32'h04, v);
            if ((v & 32'hFF) !== exp) begin
                $display("[uart_mmio_tb] FAIL exp=%02x got=%02x", exp, v[7:0]);
                $fatal(1);
            end
        end
    endtask

endmodule
