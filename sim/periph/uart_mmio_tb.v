`timescale 1ns/1ps

// ------------------------------
// Easy-to-tune test knobs
// ------------------------------
`define UART_TB_FIFO_DEPTH       64
`define UART_TB_BAUDDIV          8
`define UART_TB_OVERRUN_EXTRA    2
`define UART_TB_TX_FILL_COUNT    `UART_TB_FIFO_DEPTH
`define UART_TB_LOOP0            "O"
`define UART_TB_LOOP1            "K"
`define UART_TB_LOOP2            8'h0A
`define UART_TB_EXT0             "H"
`define UART_TB_EXT1             "i"
`define UART_TB_EXT2             8'h21

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

    localparam integer FIFO_DEPTH = `UART_TB_FIFO_DEPTH;
    localparam integer BAUDDIV    = `UART_TB_BAUDDIV;

    localparam [11:0] TXDATA_OFF  = 12'h000;
    localparam [11:0] RXDATA_OFF  = 12'h004;
    localparam [11:0] STATUS_OFF  = 12'h008;
    localparam [11:0] BAUDDIV_OFF = 12'h00C;
    localparam [11:0] CTRL_OFF    = 12'h010;

    uart_mmio #(.FIFO_DEPTH(FIFO_DEPTH)) dut (
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

    integer i;
    reg [31:0] st;
    reg [31:0] v;

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

        // ------------------------------
        // 0) basic register R/W sanity
        // ------------------------------
        mmio_wr(BAUDDIV_OFF, BAUDDIV);
        mmio_rd(BAUDDIV_OFF, v);
        if (v !== BAUDDIV) begin
            $display("[uart_mmio_tb] FAIL bauddiv rb got=%08x", v);
            $fatal(1);
        end

        mmio_wr(CTRL_OFF, 32'h7); // TX_EN | RX_EN | LOOPBACK
        mmio_rd(CTRL_OFF, v);
        if ((v & 32'h7) !== 32'h7) begin
            $display("[uart_mmio_tb] FAIL ctrl rb got=%08x", v);
            $fatal(1);
        end

        // ------------------------------
        // 1) full-chain loopback + TX pin decode
        // ------------------------------
        mmio_wr(TXDATA_OFF, `UART_TB_LOOP0);
        mmio_wr(TXDATA_OFF, `UART_TB_LOOP1);
        mmio_wr(TXDATA_OFF, `UART_TB_LOOP2);

        expect_tx(`UART_TB_LOOP0);
        expect_tx(`UART_TB_LOOP1);
        expect_tx(`UART_TB_LOOP2);

        expect_rx(`UART_TB_LOOP0);
        expect_rx(`UART_TB_LOOP1);
        expect_rx(`UART_TB_LOOP2);

        mmio_rd(STATUS_OFF, st);
        if ((st & 32'h2) != 0) begin
            $display("[uart_mmio_tb] FAIL tx_full unexpectedly set");
            $fatal(1);
        end
        if ((st & 32'h4) == 0) begin
            $display("[uart_mmio_tb] FAIL tx_empty not set after drain st=%08x", st);
            $fatal(1);
        end
        if ((st & 32'h8) != 0) begin
            $display("[uart_mmio_tb] FAIL rx_valid not cleared after pops st=%08x", st);
            $fatal(1);
        end

        // ------------------------------
        // 2) external RX injection (no loopback)
        // ------------------------------
        mmio_wr(CTRL_OFF, 32'h2); // RX_EN only
        drive_rx_byte(`UART_TB_EXT0);
        drive_rx_byte(`UART_TB_EXT1);
        drive_rx_byte(`UART_TB_EXT2);
        expect_rx(`UART_TB_EXT0);
        expect_rx(`UART_TB_EXT1);
        expect_rx(`UART_TB_EXT2);

        // ------------------------------
        // 3) TX disabled should queue but not transmit
        // ------------------------------
        mmio_wr(CTRL_OFF, 32'h0); // all disabled
        mmio_wr(TXDATA_OFF, "Q");
        wait_ticks(BAUDDIV * 12);
        if (uart_tx !== 1'b1) begin
            $display("[uart_mmio_tb] FAIL uart_tx toggled while TX disabled");
            $fatal(1);
        end
        mmio_rd(STATUS_OFF, st);
        if ((st & 32'h1) != 0) begin
            $display("[uart_mmio_tb] FAIL tx_busy while TX disabled st=%08x", st);
            $fatal(1);
        end
        if ((st & 32'h4) != 0) begin
            $display("[uart_mmio_tb] FAIL tx_empty should be 0 after queued byte st=%08x", st);
            $fatal(1);
        end
        mmio_wr(CTRL_OFF, 32'h1); // TX_EN only
        expect_tx("Q");
        mmio_rd(STATUS_OFF, st);
        if ((st & 32'h4) == 0) begin
            $display("[uart_mmio_tb] FAIL tx_empty not restored after queued send st=%08x", st);
            $fatal(1);
        end

        // ------------------------------
        // 4) TX FIFO fill / full / drain order
        // ------------------------------
        mmio_wr(CTRL_OFF, 32'h0); // keep transmitter parked while filling FIFO
        for (i = 0; i < `UART_TB_TX_FILL_COUNT; i = i + 1) begin
            mmio_wr(TXDATA_OFF, i[7:0]);
        end
        mmio_rd(STATUS_OFF, st);
        if ((st & 32'h2) == 0) begin
            $display("[uart_mmio_tb] FAIL tx_full not set after fill st=%08x", st);
            $fatal(1);
        end
        if ((st & 32'h4) != 0) begin
            $display("[uart_mmio_tb] FAIL tx_empty unexpectedly set after fill st=%08x", st);
            $fatal(1);
        end

        // extra write while full must not corrupt FIFO contents
        mmio_wr(TXDATA_OFF, 8'hEE);
        mmio_wr(CTRL_OFF, 32'h1); // TX_EN only
        for (i = 0; i < `UART_TB_TX_FILL_COUNT; i = i + 1) begin
            expect_tx(i[7:0]);
        end
        mmio_rd(STATUS_OFF, st);
        if ((st & 32'h4) == 0) begin
            $display("[uart_mmio_tb] FAIL tx_empty not set after full drain st=%08x", st);
            $fatal(1);
        end
        if ((st & 32'h2) != 0) begin
            $display("[uart_mmio_tb] FAIL tx_full stuck after drain st=%08x", st);
            $fatal(1);
        end

        // ------------------------------
        // 5) RX overrun / full / clear-overrun
        // ------------------------------
        mmio_wr(CTRL_OFF, 32'h2); // RX_EN only
        for (i = 0; i < FIFO_DEPTH + `UART_TB_OVERRUN_EXTRA; i = i + 1) begin
            drive_rx_byte(8'h80 + i[7:0]);
        end

        mmio_rd(STATUS_OFF, st);
        if ((st & 32'h8) == 0) begin
            $display("[uart_mmio_tb] FAIL rx_valid not set after fill st=%08x", st);
            $fatal(1);
        end
        if ((st & 32'h10) == 0) begin
            $display("[uart_mmio_tb] FAIL rx_full not set at depth limit st=%08x", st);
            $fatal(1);
        end
        if ((st & 32'h20) == 0) begin
            $display("[uart_mmio_tb] FAIL overrun not set after overflow st=%08x", st);
            $fatal(1);
        end

        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            expect_rx(8'h80 + i[7:0]);
        end

        mmio_rd(STATUS_OFF, st);
        if ((st & 32'h8) != 0) begin
            $display("[uart_mmio_tb] FAIL rx_valid not cleared after draining st=%08x", st);
            $fatal(1);
        end
        if ((st & 32'h20) == 0) begin
            $display("[uart_mmio_tb] FAIL overrun unexpectedly cleared before W1C st=%08x", st);
            $fatal(1);
        end

        mmio_wr(CTRL_OFF, 32'h8); // CLR_OVERRUN W1C, leaves enables low
        mmio_rd(STATUS_OFF, st);
        if ((st & 32'h20) != 0) begin
            $display("[uart_mmio_tb] FAIL overrun W1C failed st=%08x", st);
            $fatal(1);
        end

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

    task wait_ticks(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task expect_tx(input [7:0] exp);
        integer bit_i;
        reg [7:0] got;
        begin
            while (uart_tx !== 1'b0) begin
                @(posedge clk);
            end

            wait_ticks(BAUDDIV/2);
            if (uart_tx !== 1'b0) begin
                $display("[uart_mmio_tb] FAIL TX start bit not low");
                $fatal(1);
            end

            got = 8'h00;
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                wait_ticks(BAUDDIV);
                got[bit_i] = uart_tx;
            end

            wait_ticks(BAUDDIV);
            if (uart_tx !== 1'b1) begin
                $display("[uart_mmio_tb] FAIL TX stop bit not high");
                $fatal(1);
            end

            if (got !== exp) begin
                $display("[uart_mmio_tb] FAIL TX exp=%02x got=%02x", exp, got);
                $fatal(1);
            end
        end
    endtask

    task expect_rx(input [7:0] exp);
        reg [31:0] status;
        reg [31:0] data;
        begin
            status = 0;
            while ((status & 32'h8) == 0) begin
                mmio_rd(STATUS_OFF, status);
            end
            mmio_rd(RXDATA_OFF, data);
            if ((data & 32'hFF) !== exp) begin
                $display("[uart_mmio_tb] FAIL RX exp=%02x got=%02x", exp, data[7:0]);
                $fatal(1);
            end
        end
    endtask

    task drive_rx_byte(input [7:0] b);
        integer bit_i;
        begin
            // keep line stable well before the sampling posedge
            uart_rx <= 1'b1;
            wait_ticks(BAUDDIV);

            // start bit
            @(negedge clk);
            uart_rx <= 1'b0;
            wait_ticks(BAUDDIV);

            // data bits (LSB first)
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                @(negedge clk);
                uart_rx <= b[bit_i];
                wait_ticks(BAUDDIV);
            end

            // stop bit
            @(negedge clk);
            uart_rx <= 1'b1;
            wait_ticks(BAUDDIV);
        end
    endtask

endmodule
