`timescale 1ns/1ps

module soc_top_basic_tb;
    reg clk;
    reg rst;
    reg [31:0] gpio_in;
    wire [31:0] gpio_out;
    wire [31:0] gpio_dir;

    soc_top_basic #(.CLK_HZ(100_000_000)) dut (
        .clk(clk),
        .rst(rst),
        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .gpio_dir(gpio_dir)
    );

    // clock: 100MHz -> 10ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // load program image into SRAM
    reg [1023:0] hexfile;
    initial begin
        if (!$value$plusargs("hex=%s", hexfile)) begin
            hexfile = "sim/soc/out/gpio_timer.vh";
        end
        $display("[soc_tb] loading hex: %0s", hexfile);
        // hierarchical path: soc_top_basic.u_fab.u_sram.mem
        $readmemh(hexfile, dut.u_fab.u_sram.mem);
    end

    initial begin
        rst = 0;
        gpio_in = 0;
        repeat (5) @(posedge clk);
        rst = 1;
    end

    // tohost monitor: memory[0x1000>>2] == 1 indicates PASS
    localparam integer TOHOST_WORD = (32'h0000_1000 >> 2);

    integer cyc;
    initial cyc = 0;
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

                // observe data memory ops
                if (dut.mem_req && dut.mem_we) begin
                    $display("DMEM STORE addr=%08x data=%08x wstrb=%x", dut.dm_addr, dut.dm_store, dut.dm_ctl);
                end
                if (dut.mem_req && dut.mem_re) begin
                    $display("DMEM LOAD  addr=%08x", dut.dm_addr);
                end
            end

            if (dut.u_fab.u_sram.mem[TOHOST_WORD] == 32'h0000_0001) begin
                $display("[soc_tb] PASS: tohost=1 at cycle %0d", cyc);
                $display("[soc_tb] GPIO_OUT=%h DIR=%h", gpio_out, gpio_dir);
                $finish;
            end
            if (cyc > 200000) begin
                $display("[soc_tb] TIMEOUT");
                $display("[soc_tb] timer en=%0d mtime=%0d div_cnt=%0d", dut.u_fab.u_tim.en, dut.u_fab.u_tim.mtime, dut.u_fab.u_tim.div_cnt);
                $display("[soc_tb] GPIO_OUT=%h DIR=%h", gpio_out, gpio_dir);
                $fatal(1);
            end
        end
    end
endmodule
