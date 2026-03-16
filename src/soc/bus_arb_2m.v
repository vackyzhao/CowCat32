`timescale 1ns/1ps

// 2-master -> 1-slave bus arbiter with simple round-robin fairness.
// Interface: req/we/re/addr/wdata/wstrb, response: ack/rdata.
// - When both masters request at the same time, grant alternates based on last grant.
// - Holds grant stable while a request is pending (for potential wait-state slaves).
module bus_arb_2m (
    input  wire        clk,
    input  wire        rst,

    // Master 0 (e.g. CPU)
    input  wire        m0_req,
    input  wire        m0_we,
    input  wire        m0_re,
    input  wire [31:0] m0_addr,
    input  wire [31:0] m0_wdata,
    input  wire [3:0]  m0_wstrb,
    output wire        m0_ack,
    output wire [31:0] m0_rdata,

    // Master 1 (e.g. DMA)
    input  wire        m1_req,
    input  wire        m1_we,
    input  wire        m1_re,
    input  wire [31:0] m1_addr,
    input  wire [31:0] m1_wdata,
    input  wire [3:0]  m1_wstrb,
    output wire        m1_ack,
    output wire [31:0] m1_rdata,

    // Slave
    output wire        s_req,
    output wire        s_we,
    output wire        s_re,
    output wire [31:0] s_addr,
    output wire [31:0] s_wdata,
    output wire [3:0]  s_wstrb,
    input  wire        s_ack,
    input  wire [31:0] s_rdata
);

    reg pending;
    reg owner;      // 0 -> m0, 1 -> m1
    reg last_owner; // for RR when both request

    // Latched request (used only if slave inserts wait states)
    reg        l_we, l_re;
    reg [31:0] l_addr, l_wdata;
    reg [3:0]  l_wstrb;

    wire both = m0_req && m1_req;

    wire comb_owner = (both ? ~last_owner : (m0_req ? 1'b0 : 1'b1));
    wire comb_valid = (m0_req || m1_req);

    wire use_owner  = pending ? owner : comb_owner;
    wire use_valid  = pending ? 1'b1  : comb_valid;

    // drive slave bus; if pending, use latched signals
    assign s_req   = use_valid;
    assign s_we    = pending ? l_we    : ((use_owner==1'b0) ? m0_we    : m1_we);
    assign s_re    = pending ? l_re    : ((use_owner==1'b0) ? m0_re    : m1_re);
    assign s_addr  = pending ? l_addr  : ((use_owner==1'b0) ? m0_addr  : m1_addr);
    assign s_wdata = pending ? l_wdata : ((use_owner==1'b0) ? m0_wdata : m1_wdata);
    assign s_wstrb = pending ? l_wstrb : ((use_owner==1'b0) ? m0_wstrb : m1_wstrb);

    // sequential: only enter pending if slave didn't ack in the same cycle
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            pending    <= 1'b0;
            owner      <= 1'b0;
            last_owner <= 1'b0;
            l_we       <= 1'b0;
            l_re       <= 1'b0;
            l_addr     <= 32'h0;
            l_wdata    <= 32'h0;
            l_wstrb    <= 4'h0;
        end else begin
            if (!pending) begin
                if (comb_valid) begin
                    if (s_ack) begin
                        last_owner <= comb_owner;
                        pending    <= 1'b0;
                    end else begin
                        pending <= 1'b1;
                        owner   <= comb_owner;
                        // latch selected master request
                        if (comb_owner == 1'b0) begin
                            l_we    <= m0_we;
                            l_re    <= m0_re;
                            l_addr  <= m0_addr;
                            l_wdata <= m0_wdata;
                            l_wstrb <= m0_wstrb;
                        end else begin
                            l_we    <= m1_we;
                            l_re    <= m1_re;
                            l_addr  <= m1_addr;
                            l_wdata <= m1_wdata;
                            l_wstrb <= m1_wstrb;
                        end
                    end
                end
            end else begin
                if (s_ack) begin
                    pending    <= 1'b0;
                    last_owner <= owner;
                end
            end
        end
    end

    // ack/rdata routing (ack is meaningful only for the granted master)
    assign m0_ack   = (use_valid && (use_owner==1'b0)) ? s_ack : (m0_req ? 1'b0 : 1'b1);
    assign m1_ack   = (use_valid && (use_owner==1'b1)) ? s_ack : (m1_req ? 1'b0 : 1'b1);

    assign m0_rdata = (use_valid && (use_owner==1'b0)) ? s_rdata : 32'h0;
    assign m1_rdata = (use_valid && (use_owner==1'b1)) ? s_rdata : 32'h0;

endmodule
