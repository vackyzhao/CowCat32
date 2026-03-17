`timescale 1ns/1ps

// Very simple 32-bit-only DMA engine.
// - Copies LEN bytes from SRC to DST in 32-bit words.
// - SRC/DST/LEN must be 4-byte aligned and LEN multiple of 4.
// - Acts as an MMIO slave (configuration) and a bus master (read/write transactions).
//
// MMIO map (offset from DMA_BASE):
//  0x00 SRC      (R/W)
//  0x04 DST      (R/W)
//  0x08 LEN      (R/W) bytes
//  0x0C CTRL     (W)
//       bit0 START (W1)
//       bit1 CLR_DONE (W1)
//       bit2 CLR_ERR  (W1)
//  0x10 STATUS   (R)
//       bit0 BUSY
//       bit1 DONE
//       bit2 ERR
//  0x14 ERRADDR  (R) last faulting address (best-effort)
module dma_mmio #(
    parameter [31:0] DMA_BASE    = 32'h1000_2000,
    parameter [31:0] PERIPH_MASK = 32'hFFFF_F000
) (
    input  wire        clk,
    input  wire        rst,

    // MMIO slave interface (from CPU)
    input  wire        s_req,
    input  wire        s_we,
    input  wire [11:0] s_addr,   // 4KiB page offset
    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    output reg  [31:0] s_rdata,
    output wire        s_ack,

    // DMA master interface (to system bus)
    output reg         m_req,
    output reg         m_we,
    output reg         m_re,
    output reg  [31:0] m_addr,
    output reg  [31:0] m_wdata,
    output reg  [3:0]  m_wstrb,
    input  wire        m_ack,
    input  wire [31:0] m_rdata
);

    localparam [11:0] SRC_OFF     = 12'h000;
    localparam [11:0] DST_OFF     = 12'h004;
    localparam [11:0] LEN_OFF     = 12'h008;
    localparam [11:0] CTRL_OFF    = 12'h00C;
    localparam [11:0] STAT_OFF    = 12'h010;
    localparam [11:0] ERRADDR_OFF = 12'h014;

    // registers
    reg [31:0] src_reg, dst_reg, len_reg;
    reg        done, err;
    reg [31:0] erraddr;

    // engine regs
    reg [31:0] src_cur, dst_cur, left;
    reg [31:0] data_buf;

    // FSM
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_READ  = 2'd1;
    localparam [1:0] ST_WRITE = 2'd2;
    reg [1:0] st;

    wire busy = (st != ST_IDLE);

    function [31:0] apply_wmask;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0]  be;
        reg   [31:0] m;
        begin
            m = { {8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}} };
            apply_wmask = (oldv & ~m) | (newv & m);
        end
    endfunction

    wire start_w1    = s_req && s_we && (s_addr == CTRL_OFF) && s_wstrb[0] && s_wdata[0];
    wire clr_done_w1 = s_req && s_we && (s_addr == CTRL_OFF) && s_wstrb[0] && s_wdata[1];
    wire clr_err_w1  = s_req && s_we && (s_addr == CTRL_OFF) && s_wstrb[0] && s_wdata[2];

    wire aligned_ok = (src_reg[1:0] == 2'b00) && (dst_reg[1:0] == 2'b00) && (len_reg[1:0] == 2'b00);

    // prevent recursion: DMA master must not access its own page
    wire addr_hits_dma_page = ((m_addr & PERIPH_MASK) == (DMA_BASE & PERIPH_MASK));

    // MMIO writes
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            src_reg <= 32'h0;
            dst_reg <= 32'h0;
            len_reg <= 32'h0;
            done    <= 1'b0;
            err     <= 1'b0;
            erraddr <= 32'h0;
        end else begin
            if (s_req && s_we) begin
                case (s_addr)
                    SRC_OFF: src_reg <= apply_wmask(src_reg, s_wdata, s_wstrb);
                    DST_OFF: dst_reg <= apply_wmask(dst_reg, s_wdata, s_wstrb);
                    LEN_OFF: len_reg <= apply_wmask(len_reg, s_wdata, s_wstrb);
                    default: ;
                endcase
            end
            if (clr_done_w1) done <= 1'b0;
            if (clr_err_w1)  err  <= 1'b0;
        end
    end

    // MMIO reads
    always @(*) begin
        case (s_addr)
            SRC_OFF:     s_rdata = src_reg;
            DST_OFF:     s_rdata = dst_reg;
            LEN_OFF:     s_rdata = len_reg;
            CTRL_OFF:    s_rdata = 32'h0;
            STAT_OFF:    s_rdata = {29'd0, err, done, busy};
            ERRADDR_OFF: s_rdata = erraddr;
            default:     s_rdata = 32'h0;
        endcase
    end

    assign s_ack = s_req;

    // Master interface outputs (combinational from state)
    always @(*) begin
        m_req   = 1'b0;
        m_we    = 1'b0;
        m_re    = 1'b0;
        m_addr  = 32'h0;
        m_wdata = 32'h0;
        m_wstrb = 4'h0;
        case (st)
            ST_READ: begin
                m_req   = 1'b1;
                m_re    = 1'b1;
                m_addr  = src_cur;
            end
            ST_WRITE: begin
                m_req   = 1'b1;
                m_we    = 1'b1;
                m_addr  = dst_cur;
                m_wdata = data_buf;
                m_wstrb = 4'hF;
            end
            default: ;
        endcase
    end

    // FSM sequencing
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            st       <= ST_IDLE;
            src_cur  <= 32'h0;
            dst_cur  <= 32'h0;
            left     <= 32'h0;
            data_buf <= 32'h0;
        end else begin
            case (st)
                ST_IDLE: begin
                    if (start_w1) begin
                        if (!aligned_ok || (len_reg == 32'h0)) begin
                            erraddr <= 32'h0;
                            err     <= 1'b1;
                            done    <= 1'b0;
                            st      <= ST_IDLE;
                        end else begin
                            src_cur <= src_reg;
                            dst_cur <= dst_reg;
                            left    <= len_reg;
                            done    <= 1'b0;
                            st      <= ST_READ;
                        end
                    end
                end

                ST_READ: begin
                    if (addr_hits_dma_page) begin
                        erraddr <= m_addr;
                        err     <= 1'b1;
                        st      <= ST_IDLE;
                    end else if (m_ack) begin
                        data_buf <= m_rdata;
                        st       <= ST_WRITE;
                    end
                end

                ST_WRITE: begin
                    if (addr_hits_dma_page) begin
                        erraddr <= m_addr;
                        err     <= 1'b1;
                        st      <= ST_IDLE;
                    end else if (m_ack) begin
                        src_cur <= src_cur + 32'd4;
                        dst_cur <= dst_cur + 32'd4;
                        left    <= left - 32'd4;
                        if (left == 32'd4) begin
                            done <= 1'b1;
                            st   <= ST_IDLE;
                        end else begin
                            st <= ST_READ;
                        end
                    end
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
