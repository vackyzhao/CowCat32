// noc_adapter.v
// Bridges the CowCat32 memory-mapped bus to a NoD local port.
//
// Presents the same peripheral interface as GPIO/RTC/DTCM so it can be
// dropped into the existing memory_arbiter without modification.
//
// Register map (offset from NOC_BASE_ADDR):
//   0x000  NOC_TX_DATA   (W)  — payload to send
//   0x004  NOC_TX_DST    (W)  — destination: bits[5:3]=DST_X, bits[2:0]=DST_Y
//   0x008  NOC_RX_DATA   (R)  — received payload
//   0x00C  NOC_RX_STATUS (R)  — bit[0]=rx_valid, bit[1]=tx_busy
//   0x010  NOC_RX_ACK    (W)  — write any value to dequeue RX buffer

`include "param.vh"

module noc_adapter #(
    parameter NODE_X = 0,
    parameter NODE_Y = 0
)(
    input  wire        clk,
    input  wire        rstn,    // active-high reset from CowCat32 (inverted internally)

    // Memory-arbiter peripheral interface
    input  wire [31:0] noc_addr,
    input  wire [31:0] noc_wdata,
    input  wire        noc_rw,     // 1=write, 0=read
    input  wire        noc_we,     // chip-select
    output reg  [31:0] noc_rdata,
    output reg         noc_ready,

    // NoD local port — TX (CPU → NoD)
    output wire [`DATA_WIDTH-1:0] nod_tx_data,
    output wire                   nod_tx_valid,
    input  wire                   nod_tx_ready,

    // NoD local port — RX (NoD → CPU)
    input  wire [`DATA_WIDTH-1:0] nod_rx_data,
    input  wire                   nod_rx_valid,
    output wire                   nod_rx_ready
);

// Internal reset: CowCat32 uses active-high rst; NoD uses active-low rstn
wire rst_n = rstn;

// -----------------------------------------------------------------------
// Register file
// -----------------------------------------------------------------------
reg [31:0] tx_data_reg;
reg [5:0]  tx_dst_reg;     // {DST_X[2:0], DST_Y[2:0]}

wire [31:0] rx_data_wire;
wire        rx_valid_wire;
wire        tx_busy_wire;

// -----------------------------------------------------------------------
// TX/RX sub-modules
// -----------------------------------------------------------------------
reg  send_req;
wire rx_ack;

flit_tx #(
    .SRC_X (NODE_X),
    .SRC_Y (NODE_Y)
) u_tx (
    .clk         (clk),
    .rstn        (rst_n),
    .cpu_payload (tx_data_reg),
    .dst_id      (tx_dst_reg),
    .send_req    (send_req),
    .tx_busy     (tx_busy_wire),
    .nod_data    (nod_tx_data),
    .nod_valid   (nod_tx_valid),
    .nod_ready   (nod_tx_ready)
);

flit_rx u_rx (
    .clk        (clk),
    .rstn       (rst_n),
    .nod_data   (nod_rx_data),
    .nod_valid  (nod_rx_valid),
    .nod_ready  (nod_rx_ready),
    .rx_payload (rx_data_wire),
    .rx_valid   (rx_valid_wire),
    .rx_ack     (rx_ack)
);

// -----------------------------------------------------------------------
// Bus write logic
// -----------------------------------------------------------------------
reg rx_ack_r;
assign rx_ack = rx_ack_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_data_reg <= 32'b0;
        tx_dst_reg  <= 6'b0;
        send_req    <= 1'b0;
        rx_ack_r    <= 1'b0;
        noc_ready   <= 1'b0;
        noc_rdata   <= 32'b0;
    end else begin
        send_req  <= 1'b0;   // default: no request
        rx_ack_r  <= 1'b0;
        noc_ready <= 1'b0;

        if (noc_we) begin
            if (noc_rw) begin
                // Write transactions
                case (noc_addr[7:0])
                    8'h00: begin
                        tx_data_reg <= noc_wdata;
                        noc_ready   <= 1'b1;
                    end
                    8'h04: begin
                        tx_dst_reg <= noc_wdata[5:0];
                        send_req   <= 1'b1;   // trigger TX after DST is set
                        noc_ready  <= 1'b1;
                    end
                    8'h10: begin
                        rx_ack_r  <= 1'b1;
                        noc_ready <= 1'b1;
                    end
                    default: noc_ready <= 1'b1;
                endcase
            end else begin
                // Read transactions
                case (noc_addr[7:0])
                    8'h08: begin
                        noc_rdata <= rx_data_wire;
                        noc_ready <= 1'b1;
                    end
                    8'h0C: begin
                        noc_rdata <= {30'b0, tx_busy_wire, rx_valid_wire};
                        noc_ready <= 1'b1;
                    end
                    default: begin
                        noc_rdata <= 32'b0;
                        noc_ready <= 1'b1;
                    end
                endcase
            end
        end
    end
end

endmodule
