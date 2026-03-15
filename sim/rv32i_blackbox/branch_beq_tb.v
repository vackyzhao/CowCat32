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
        32'h00000000: im_inst = 32'h00100093;
        32'h00000004: im_inst = 32'h00100113;
        32'h00000008: im_inst = 32'h00208463;
        32'h0000000c: im_inst = 32'h06300193;
        32'h00000010: im_inst = 32'h00700193;
        32'h00000014: im_inst = 32'h00000013;
        32'h00000018: im_inst = 32'h00000013;
        32'h0000001c: im_inst = 32'h00000013;
        32'h00000020: im_inst = 32'h00000013;
        32'h00000024: im_inst = 32'h00000013;
        32'h00000028: im_inst = 32'h00000013;
        32'h0000002c: im_inst = 32'h00000013;
        32'h00000030: im_inst = 32'h00000013;
        default: im_inst = 32'h00000013; // nop
        endcase
    end

    // simple data memory model (word addressed)
    reg [31:0] data_mem [0:255];
    integer i;
    initial begin
        for (i=0;i<256;i=i+1) data_mem[i] = 32'h0;
    end

    localparam integer LATENCY = 3;
    reg dmem_busy;
    reg [3:0] dmem_cnt;
    reg pend_we;
    reg pend_re;
    reg [31:0] pend_addr;
    reg [31:0] pend_wdata;

    wire data_req = mem_req && (mem_we || mem_re);

    initial begin
        dm_ack    = 1'b0;
        dm_load   = 32'h0;
        dmem_busy = 1'b0;
        dmem_cnt  = 0;
        pend_we   = 1'b0;
        pend_re   = 1'b0;
        pend_addr = 32'h0;
        pend_wdata= 32'h0;
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            dm_ack    <= 1'b0;
            dm_load   <= 32'h0;
            dmem_busy <= 1'b0;
            dmem_cnt  <= 0;
        end else begin
            dm_ack <= 1'b0;
            if (!dmem_busy) begin
                if (data_req) begin
                    dmem_busy  <= 1'b1;
                    dmem_cnt   <= LATENCY;
                    pend_we    <= mem_we;
                    pend_re    <= mem_re;
                    pend_addr  <= dm_addr;
                    pend_wdata <= dm_store;
                end
            end else begin
                if (dmem_cnt != 0) begin
                    dmem_cnt <= dmem_cnt - 1;
                end else begin
                    dm_ack <= 1'b1;
                    if (pend_we) begin
                        data_mem[pend_addr[9:2]] <= pend_wdata;
                    end
                    if (pend_re) begin
                        dm_load <= data_mem[pend_addr[9:2]];
                    end
                    dmem_busy <= 1'b0;
                end
            end
        end
    end

    // reset + timeout + checks
    initial begin
        rst = 1'b0;
        #20; rst = 1'b1;

        // run
        #( 600 * 10 );

        // checks
        if (uut.ID.registers_file.regs[3] !== 32'h00000007) begin
            $display("FAIL: x3 exp=00000007 got=%h", uut.ID.registers_file.regs[3]);
            $fatal(1);
        end

        $display("PASS: branch_beq");
        $finish;
    end
endmodule
