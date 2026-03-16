`timescale 1ns/1ps

// Simple timer MMIO block with a fixed 1MHz timebase derived from clk.
// No interrupt output yet (status bit only).
//
// MTIME is 64-bit (HI/LO). Hardware provides an atomic read mechanism:
// - Read MTIME_HI latches a snapshot of the 64-bit counter.
// - The following read of MTIME_LO returns the snapshot LO (consistent with that HI).
// This way software can simply do HI then LO without retry loops.
//
// Address map (offset from BASE):
//  0x00 CTRL      (R/W) bit0 enable, bit1 clear
//  0x04 MTIME_LO  (R)   snapshot low (after HI read)
//  0x08 MTIME_HI  (R)   live high; also latches snapshot
//  0x0C CMP_LO    (R/W)
//  0x10 CMP_HI    (R/W)
//  0x14 STATUS    (R)   bit0 = (mtime >= cmp)
//
module timer_mmio #(
    parameter integer CLK_HZ = 50_000_000
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        req,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,

    output reg  [31:0] rdata,
    output wire        ack
);

    localparam integer CTRL_OFF   = 32'h00;
    localparam integer MTLO_OFF   = 32'h04;
    localparam integer MTHI_OFF   = 32'h08;
    localparam integer CMPLO_OFF  = 32'h0C;
    localparam integer CMPHI_OFF  = 32'h10;
    localparam integer STAT_OFF   = 32'h14;

    // 1MHz tick divider
    localparam integer DIV_1MHZ = (CLK_HZ/1_000_000);
    // guard
    localparam integer DIV_SAFE = (DIV_1MHZ < 1) ? 1 : DIV_1MHZ;

    reg        en;
    reg [31:0] div_cnt;
    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    // latched snapshot for atomic HI->LO read
    reg [63:0] mtime_lat;
    reg        lat_valid;

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

    wire [31:0] off = addr[31:0];

    wire hit = (mtime >= mtimecmp);

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            en        <= 1'b0;
            div_cnt   <= 32'd0;
            mtime     <= 64'd0;
            mtimecmp  <= 64'hFFFF_FFFF_FFFF_FFFF;
            mtime_lat <= 64'd0;
            lat_valid <= 1'b0;
        end else begin
            // 1MHz tick
            if (en) begin
                if (div_cnt == (DIV_SAFE-1)) begin
                    div_cnt <= 32'd0;
                    mtime   <= mtime + 64'd1;
                end else begin
                    div_cnt <= div_cnt + 32'd1;
                end
            end

            // MMIO reads: latch snapshot on HI read, consume on LO read
            if (req && !we) begin
                case (off)
                    MTHI_OFF: begin
                        mtime_lat <= mtime;
                        lat_valid <= 1'b1;
                    end
                    MTLO_OFF: begin
                        // after HI read, LO returns snapshot; then clear valid
                        if (lat_valid) lat_valid <= 1'b0;
                    end
                    default: ;
                endcase
            end

            // MMIO writes
            if (req && we) begin
                case (off)
                    CTRL_OFF: begin
                        // bit0 enable, bit1 clear
                        if (wstrb[0]) begin
                            en <= wdata[0];
                            if (wdata[1]) begin
                                mtime     <= 64'd0;
                                div_cnt   <= 32'd0;
                                lat_valid <= 1'b0;
                            end
                        end
                    end
                    CMPLO_OFF: mtimecmp[31:0]  <= apply_wmask(mtimecmp[31:0],  wdata, wstrb);
                    CMPHI_OFF: mtimecmp[63:32] <= apply_wmask(mtimecmp[63:32], wdata, wstrb);
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (off)
            CTRL_OFF:  rdata = {30'd0, 1'b0, en};
            MTLO_OFF:  rdata = lat_valid ? mtime_lat[31:0] : mtime[31:0];
            MTHI_OFF:  rdata = mtime[63:32];
            CMPLO_OFF: rdata = mtimecmp[31:0];
            CMPHI_OFF: rdata = mtimecmp[63:32];
            STAT_OFF:  rdata = {31'd0, hit};
            default:   rdata = 32'h0;
        endcase
    end

    assign ack = req;

endmodule
