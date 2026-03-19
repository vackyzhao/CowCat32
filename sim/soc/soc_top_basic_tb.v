`timescale 1ns/1ps

module soc_top_basic_tb;
    reg clk;
    reg rst;
    reg [31:0] gpio_in;
    wire [31:0] gpio_out;
    wire [31:0] gpio_dir;

    reg  uart_rx;
    wire uart_tx;

    // Optional VCD dumping: pass +vcd=<path> to enable
    reg [1023:0] vcdfile;
    integer dump_en;

    reg [1023:0] hexfile;
    reg [1023:0] datahexfile;
    initial begin
        if (!$value$plusargs("hex=%s", hexfile)) begin
            hexfile = "sw/examples/uart_hello/out/uart_hello.vh";
        end
        if (!$value$plusargs("datahex=%s", datahexfile)) begin
            datahexfile = "sw/examples/uart_hello/out/uart_hello.data.vh";
        end
    end

    soc_top_basic #(
        .CLK_HZ(100_000_000),
        .INIT_DATA_WORDS(2048)
    ) dut (
        .clk(clk),
        .rst(rst),
        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .gpio_dir(gpio_dir),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // clock: 100MHz -> 10ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $display("[soc_tb] loading imem hex: %0s", hexfile);
        // load program into instruction ROM
        $readmemh(hexfile, dut.u_rom.mem);
        if (datahexfile != "") begin
            $display("[soc_tb] loading init-data hex: %0s", datahexfile);
            $readmemh(datahexfile, dut.u_init_rom.mem);
        end

        dump_en = 0;
        if ($value$plusargs("vcd=%s", vcdfile)) begin
            dump_en = 1;
        end
        if (dump_en) begin
            $display("[soc_tb] dumping VCD: %0s", vcdfile);
            $dumpfile(vcdfile);
            $dumpvars(0, soc_top_basic_tb);
        end
    end

    initial begin
        rst = 0;
        gpio_in = 0;
        uart_rx = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1;
    end

    // tohost monitor: dmem[0x1000>>2] == 1 indicates PASS
    localparam integer TOHOST_WORD = (32'h0000_1000 >> 2);

    integer cyc;
    integer grace;
    initial cyc = 0;

    localparam integer UART_FINISH_GRACE_CYCLES = 64;
    integer auto_finish;
    initial begin
        auto_finish = 0;
        if ($test$plusargs("auto_finish")) auto_finish = 1;
    end

    reg [31:0] last_pc;
    reg        pass_seen;
    initial begin
        last_pc = 32'h0;
        pass_seen = 1'b0;
    end
    always @(posedge clk) begin
        if (dut.trace_valid) last_pc <= dut.trace_pc;
    end
    integer verbose;
    initial begin
        verbose = 0;
        if ($test$plusargs("verbose")) verbose = 1;
    end

    always @(posedge clk) begin
        if (rst) begin
            cyc <= cyc + 1;

            if (verbose) begin
                // commit trace (WB)
                if (dut.trace_valid) begin
                    $display("TRACE pc=%08x inst=%08x rd=x%0d data=%08x", dut.trace_pc, dut.trace_inst, dut.trace_rd, dut.trace_rd_data);
                end

                // observe CPU-side data memory ops
                if (dut.mem_req && dut.mem_we) begin
                    $display("CPU STORE addr=%08x data=%08x wstrb=%x", dut.dm_addr, dut.dm_store, dut.dm_ctl);
                end
                if (dut.mem_req && dut.mem_re) begin
                    $display("CPU LOAD  addr=%08x", dut.dm_addr);
                end

                // observe shared bus + arbiter owner (0=CPU,1=DMA)
                if (dut.bus_req) begin
                    $display("BUS owner=%0d we=%0d re=%0d addr=%08x wdata=%08x ack=%0d",
                             dut.u_arb.owner, dut.bus_we, dut.bus_re, dut.bus_addr, dut.bus_wdata, dut.bus_ack);
                end
            end

            if ((dut.u_fab.u_dmem.mem[TOHOST_WORD] != 32'h0000_0000) && !pass_seen) begin
                if (dut.u_fab.u_dmem.mem[TOHOST_WORD] == 32'h0000_0001) begin
                    pass_seen <= 1'b1;
                    $display("[soc_tb] PASS: tohost=1 at cycle %0d", cyc);
                    $display("[soc_tb] GPIO_OUT=%h DIR=%h", gpio_out, gpio_dir);

                    if (auto_finish) begin
                        // Optional auto-finish mode for batch regression.
                        while (!dut.u_fab.u_uart.tx_empty || dut.u_fab.u_uart.tx_busy) begin
                            @(posedge clk);
                        end
                        for (grace = 0; grace < UART_FINISH_GRACE_CYCLES; grace = grace + 1) begin
                            @(posedge clk);
                        end
                        $finish;
                    end
                end else begin
                    $display("[soc_tb] FAIL: tohost=%0d at cycle %0d", dut.u_fab.u_dmem.mem[TOHOST_WORD], cyc);
                    $fatal(1);
                end
            end
            if (cyc > 200000) begin
                $display("[soc_tb] TIMEOUT last_pc=%08x", last_pc);
                $display("[soc_tb] timer en=%0d mtime=%0d div_cnt=%0d", dut.u_fab.u_tim.en, dut.u_fab.u_tim.mtime, dut.u_fab.u_tim.div_cnt);
                $display("[soc_tb] DMA busy=%0d done=%0d err=%0d st=%0d left=%0d src=%08x dst=%08x",
                         dut.u_fab.u_dma.busy, dut.u_fab.u_dma.done, dut.u_fab.u_dma.err,
                         dut.u_fab.u_dma.st, dut.u_fab.u_dma.left, dut.u_fab.u_dma.src_cur, dut.u_fab.u_dma.dst_cur);
                $display("[soc_tb] GPIO_OUT=%h DIR=%h", gpio_out, gpio_dir);
                $fatal(1);
            end
        end
    end
endmodule
