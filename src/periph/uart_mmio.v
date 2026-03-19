`timescale 1ns/1ps

// Simple UART (8N1) with TX/RX FIFOs.
// - MMIO slave registers
// - Baud divider programmable (clk cycles per bit)
// - Optional loopback (bit-level: tx -> rx)
//
// Address map (offset from UART_BASE):
//  0x00 TXDATA   (W)  [7:0] byte to send (push TX FIFO if !TX_FULL)
//  0x04 RXDATA   (R)  [7:0] received byte (pop RX FIFO if RX_VALID),
//                    [31]   RX_VALID (1 if returned byte is valid)
//  0x08 STATUS   (R)
//        bit0 TX_BUSY   (shifting out frame)
//        bit1 TX_FULL
//        bit2 TX_EMPTY
//        bit3 RX_VALID  (RX FIFO not empty)
//        bit4 RX_FULL
//        bit5 OVERRUN   (RX overflow occurred; W1C via CTRL)
//  0x0C BAUDDIV  (R/W) clk cycles per bit (>=1). Example: 100MHz/115200 ~ 868
//  0x10 CTRL     (R/W)
//        bit0 TX_EN
//        bit1 RX_EN
//        bit2 LOOPBACK
//        bit3 CLR_OVERRUN (W1)
//
module uart_mmio #(
    // Default FIFO depth increased for smoother bursts (must be power-of-2).
    parameter integer FIFO_DEPTH = 64,
    // Reset/default baud divider; runtime MMIO writes can still override it.
    parameter [31:0] DEFAULT_BAUDDIV = 32'd868
) (
    input  wire        clk,
    input  wire        rst,

    // MMIO slave
    input  wire        req,
    input  wire        we,
    input  wire [11:0] addr,   // 4KiB page offset
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg  [31:0] rdata,
    output wire        ack,

    // UART pins
    input  wire        uart_rx,
    output reg         uart_tx
);

    localparam [11:0] TXDATA_OFF = 12'h000;
    localparam [11:0] RXDATA_OFF = 12'h004;
    localparam [11:0] STATUS_OFF = 12'h008;
    localparam [11:0] BAUDDIV_OFF= 12'h00C;
    localparam [11:0] CTRL_OFF   = 12'h010;

    // ----------------
    // Registers
    // ----------------
    reg [31:0] bauddiv;
    reg        tx_en, rx_en, loopback;
    reg        overrun;

    wire [31:0] bauddiv_eff = (bauddiv == 32'd0) ? 32'd1 : bauddiv;

    // ----------------
    // FIFOs (simple ring)
    // ----------------
    localparam integer AW = $clog2(FIFO_DEPTH);

    reg [7:0] tx_mem [0:FIFO_DEPTH-1];
    reg [AW-1:0] tx_wptr, tx_rptr;
    reg [AW:0]   tx_count;

    reg [7:0] rx_mem [0:FIFO_DEPTH-1];
    reg [AW-1:0] rx_wptr, rx_rptr;
    reg [AW:0]   rx_count;

    wire tx_full  = (tx_count == FIFO_DEPTH);
    wire tx_empty = (tx_count == 0);
    wire rx_full  = (rx_count == FIFO_DEPTH);
    wire rx_valid = (rx_count != 0);

    // MMIO push/pop
    wire mmio_wr_tx = req && we && (addr == TXDATA_OFF) && (wstrb != 4'h0);
    wire mmio_rd_rx = req && !we && (addr == RXDATA_OFF);

    // TX pop requested by engine (combinational)
    wire tx_pop = (tx_state == TX_IDLE) && tx_en && !tx_empty;

    wire [7:0] tx_pop_byte = tx_mem[tx_rptr];
    wire [7:0] rx_pop_byte = rx_mem[rx_rptr];

    // RX push pulse from RX engine (registered)
    reg        rx_push;
    reg [7:0]  rx_push_byte;

    // RX pop by MMIO read
    wire rx_pop = mmio_rd_rx && rx_valid;

    wire tx_do_pop  = tx_pop && !tx_empty;
    // allow push when full if also popping in same cycle
    wire tx_can_push = (!tx_full) || tx_do_pop;
    wire tx_do_push  = mmio_wr_tx && tx_can_push;

    wire rx_do_pop   = rx_pop;
    // allow push when full if also popping in same cycle
    wire rx_can_push = (!rx_full) || rx_do_pop;
    wire rx_do_push  = rx_push && rx_can_push;

    // FIFO update (handles simultaneous push/pop correctly)
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            tx_wptr  <= {AW{1'b0}};
            tx_rptr  <= {AW{1'b0}};
            tx_count <= {(AW+1){1'b0}};
            rx_wptr  <= {AW{1'b0}};
            rx_rptr  <= {AW{1'b0}};
            rx_count <= {(AW+1){1'b0}};
            overrun  <= 1'b0;
        end else begin
            // TX FIFO
            case ({tx_do_push, tx_do_pop})
                2'b10: begin
                    tx_mem[tx_wptr] <= wdata[7:0];
                    tx_wptr <= tx_wptr + {{(AW-1){1'b0}},1'b1};
                    tx_count <= tx_count + {{AW{1'b0}},1'b1};
                end
                2'b01: begin
                    tx_rptr <= tx_rptr + {{(AW-1){1'b0}},1'b1};
                    tx_count <= tx_count - {{AW{1'b0}},1'b1};
                end
                2'b11: begin
                    // push and pop in same cycle
                    tx_mem[tx_wptr] <= wdata[7:0];
                    tx_wptr <= tx_wptr + {{(AW-1){1'b0}},1'b1};
                    tx_rptr <= tx_rptr + {{(AW-1){1'b0}},1'b1};
                    // count unchanged
                end
                default: ;
            endcase

            // RX FIFO
            case ({rx_do_push, rx_do_pop})
                2'b10: begin
                    // push only
                    rx_mem[rx_wptr] <= rx_push_byte;
                    rx_wptr <= rx_wptr + {{(AW-1){1'b0}},1'b1};
                    rx_count <= rx_count + {{AW{1'b0}},1'b1};
                end
                2'b01: begin
                    // pop only
                    rx_rptr <= rx_rptr + {{(AW-1){1'b0}},1'b1};
                    rx_count <= rx_count - {{AW{1'b0}},1'b1};
                end
                2'b11: begin
                    // pop + push
                    rx_rptr <= rx_rptr + {{(AW-1){1'b0}},1'b1};
                    rx_mem[rx_wptr] <= rx_push_byte;
                    rx_wptr <= rx_wptr + {{(AW-1){1'b0}},1'b1};
                    // count unchanged
                end
                default: ;
            endcase

            // overflow detection: if push requested but fifo full and no pop
            if (rx_push && rx_full && !rx_do_pop) begin
                overrun <= 1'b1;
            end
        end
    end

    // ----------------
    // Control regs
    // ----------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            bauddiv  <= DEFAULT_BAUDDIV;
            tx_en    <= 1'b0;
            rx_en    <= 1'b0;
            loopback <= 1'b0;
        end else if (req && we) begin
            if (addr == BAUDDIV_OFF) begin
                if (wstrb[0]) bauddiv[7:0]   <= wdata[7:0];
                if (wstrb[1]) bauddiv[15:8]  <= wdata[15:8];
                if (wstrb[2]) bauddiv[23:16] <= wdata[23:16];
                if (wstrb[3]) bauddiv[31:24] <= wdata[31:24];
                // Re-align the bit-time generator whenever software changes the divisor.
                baud_cnt <= 32'd0;
            end
            if (addr == CTRL_OFF) begin
                if (wstrb[0]) begin
                    tx_en    <= wdata[0];
                    rx_en    <= wdata[1];
                    loopback <= wdata[2];
                    if (wdata[3]) overrun <= 1'b0; // W1C
                end
            end
        end
    end

    // ----------------
    // Baud tick generator
    // ----------------
    reg [31:0] baud_cnt;
    // Use >= so dynamic divisor reductions cannot wedge the tick generator when
    // baud_cnt is already above the new threshold.
    wire baud_tick = (baud_cnt >= (bauddiv_eff - 32'd1));

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            baud_cnt <= 32'd0;
        end else begin
            if (baud_tick) baud_cnt <= 32'd0;
            else baud_cnt <= baud_cnt + 32'd1;
        end
    end

    // ----------------
    // TX engine
    // ----------------
    localparam [2:0] TX_IDLE  = 3'd0;
    localparam [2:0] TX_START = 3'd1;
    localparam [2:0] TX_DATA  = 3'd2;
    localparam [2:0] TX_STOP  = 3'd3;

    reg [2:0] tx_state;
    reg [7:0] tx_shift;
    reg [2:0] tx_bit;

    wire tx_busy = (tx_state != TX_IDLE);

    // tx_pop is a wire derived from state/count (see FIFO section)

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            uart_tx  <= 1'b1;
            tx_state <= TX_IDLE;
            tx_shift <= 8'h00;
            tx_bit   <= 3'd0;
        end else begin
            if (tx_state == TX_IDLE) begin
                uart_tx <= 1'b1;
                if (tx_pop && !tx_empty) begin
                    tx_shift <= tx_pop_byte;
                    tx_bit   <= 3'd0;
                    tx_state <= TX_START;
                    // do not wait for baud_tick to assert start bit; align at next tick
                end
            end else if (baud_tick) begin
                case (tx_state)
                    TX_START: begin
                        uart_tx  <= 1'b0;
                        tx_state <= TX_DATA;
                    end
                    TX_DATA: begin
                        uart_tx  <= tx_shift[0];
                        tx_shift <= {1'b0, tx_shift[7:1]};
                        if (tx_bit == 3'd7) begin
                            tx_state <= TX_STOP;
                        end
                        tx_bit <= tx_bit + 3'd1;
                    end
                    TX_STOP: begin
                        uart_tx  <= 1'b1;
                        tx_state <= TX_IDLE;
                    end
                    default: tx_state <= TX_IDLE;
                endcase
            end
        end
    end

`ifdef UART_SIM_PRINT
    // In simulation, print byte when transmission starts (not cycle-accurate to pin wave).
    always @(posedge clk) begin
        if (rst && tx_state == TX_IDLE && tx_pop && !tx_empty) begin
            $write("%c", tx_pop_byte);
        end
    end
`endif

    // ----------------
    // RX engine (8N1)
    // ----------------
    localparam [2:0] RX_IDLE  = 3'd0;
    localparam [2:0] RX_START = 3'd1;
    localparam [2:0] RX_DATA  = 3'd2;
    localparam [2:0] RX_STOP  = 3'd3;

    reg [2:0]  rx_state;
    reg [7:0]  rx_shift;
    reg [2:0]  rx_bit;
    reg [31:0] rx_wait;

    wire rx_pin = loopback ? uart_tx : uart_rx;

    // rx_pop is a wire derived from mmio read; rx_push is driven by RX FSM

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            rx_state <= RX_IDLE;
            rx_shift <= 8'h00;
            rx_bit   <= 3'd0;
            rx_wait  <= 32'd0;
            rx_push  <= 1'b0;
            rx_push_byte <= 8'h00;
        end else begin
            // default: no push (1-cycle pulse)
            rx_push <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (rx_en && (rx_pin == 1'b0)) begin
                        // start edge detected
                        rx_wait  <= (bauddiv_eff >> 1); // half-bit wait
                        rx_state <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_wait != 0) begin
                        rx_wait <= rx_wait - 32'd1;
                    end else begin
                        // sample start bit center
                        if (rx_pin == 1'b0) begin
                            rx_wait  <= bauddiv_eff - 32'd1;
                            rx_bit   <= 3'd0;
                            rx_shift <= 8'h00;
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end
                end
                RX_DATA: begin
                    if (rx_wait != 0) begin
                        rx_wait <= rx_wait - 32'd1;
                    end else begin
                        // sample data bit (LSB first; shift-right builds correct order)
                        rx_shift <= {rx_pin, rx_shift[7:1]};
                        rx_wait <= bauddiv_eff - 32'd1;
                        if (rx_bit == 3'd7) begin
                            rx_state <= RX_STOP;
                        end
                        rx_bit <= rx_bit + 3'd1;
                    end
                end
                RX_STOP: begin
                    if (rx_wait != 0) begin
                        rx_wait <= rx_wait - 32'd1;
                    end else begin
                        // sample stop bit (should be 1)
                        // accept regardless; overflow handled in FIFO logic
                        rx_push <= 1'b1;
                        rx_push_byte <= rx_shift;
                        rx_state <= RX_IDLE;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // ----------------
    // MMIO read mux
    // ----------------
    always @(*) begin
        case (addr)
            TXDATA_OFF:  rdata = 32'h0;
            RXDATA_OFF:  rdata = rx_valid ? {1'b1, 23'd0, rx_pop_byte} : 32'h0;
            STATUS_OFF:  rdata = {26'd0, overrun, rx_full, rx_valid, tx_empty, tx_full, tx_busy};
            BAUDDIV_OFF: rdata = bauddiv;
            CTRL_OFF:    rdata = {28'd0, 1'b0, loopback, rx_en, tx_en};
            default:     rdata = 32'h0;
        endcase
    end

    assign ack = req;

endmodule
