// flit_rx.v
// RX path: receives a 2-flit NoD packet and exposes the payload to the CPU.
//
// Packet format expected:
//   Flit 0 (HEAD): routing info, no payload
//   Flit 1 (TAIL): payload in bits [127:96]
//
// One packet is buffered. The CPU reads it via the NOC_RX_DATA register
// and clears it by writing to NOC_RX_ACK. While a packet is buffered,
// rx_valid=1. Subsequent incoming packets are held at the NoD output
// (nod_ready=0) until the buffer is cleared.

`include "param.vh"

module flit_rx (
    input  wire        clk,
    input  wire        rstn,

    // NoD local port (input)
    input  wire [`DATA_WIDTH-1:0] nod_data,
    input  wire                   nod_valid,
    output reg                    nod_ready,

    // CPU-side read interface
    output reg  [31:0] rx_payload,    // latched payload for CPU to read
    output reg         rx_valid,      // 1 = a received packet is waiting
    input  wire        rx_ack         // pulse from CPU (write to NOC_RX_ACK)
);

// FSM states
localparam IDLE  = 2'd0;   // waiting for HEAD
localparam WAIT  = 2'd1;   // HEAD received, waiting for TAIL
localparam HOLD  = 2'd2;   // TAIL received, holding for CPU to read

reg [1:0] state;

wire [1:0] flit_type = nod_data[`DATA_WIDTH-1:`DATA_WIDTH-2];

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state      <= IDLE;
        nod_ready  <= 1'b1;
        rx_payload <= 32'b0;
        rx_valid   <= 1'b0;
    end else begin
        case (state)

            IDLE: begin
                rx_valid  <= 1'b0;
                nod_ready <= 1'b1;
                if (nod_valid && nod_ready && flit_type == 2'b00) begin
                    // HEAD received — wait for TAIL
                    state <= WAIT;
                end
            end

            WAIT: begin
                nod_ready <= 1'b1;
                if (nod_valid && nod_ready && flit_type == 2'b10) begin
                    // TAIL received — latch payload from [127:96]
                    rx_payload <= nod_data[127:96];
                    rx_valid   <= 1'b1;
                    nod_ready  <= 1'b0;   // stop accepting until CPU reads
                    state      <= HOLD;
                end
            end

            HOLD: begin
                // Wait for CPU to acknowledge
                if (rx_ack) begin
                    rx_valid  <= 1'b0;
                    nod_ready <= 1'b1;
                    state     <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
