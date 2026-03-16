// flit_tx.v
// TX path: converts a 32-bit CPU write into a 2-flit NoD packet.
//
// Packetisation:
//   Flit 0 (HEAD): flit_type=2'b00, RTID=DRID={DST_X,DST_Y}, SRID={SRC_X,SRC_Y}
//   Flit 1 (TAIL): flit_type=2'b10, payload[127:96]=cpu_payload, rest=0
//
// The module accepts one message at a time. While a packet is in flight
// (state != IDLE), it asserts tx_busy so the adapter can backpressure
// the CPU.

`include "param.vh"

module flit_tx #(
    parameter SRC_X = 0,
    parameter SRC_Y = 0
)(
    input  wire        clk,
    input  wire        rstn,

    // CPU-side trigger
    input  wire [31:0] cpu_payload,   // latched NOC_TX_DATA value
    input  wire [5:0]  dst_id,        // {DST_X[2:0], DST_Y[2:0]}
    input  wire        send_req,      // pulse: begin injection
    output reg         tx_busy,       // 1 while packet is in flight

    // NoD local port (output)
    output reg  [`DATA_WIDTH-1:0] nod_data,
    output reg                    nod_valid,
    input  wire                   nod_ready
);

// FSM states
localparam IDLE  = 2'd0;
localparam HEAD  = 2'd1;
localparam TAIL  = 2'd2;

reg [1:0] state;

// Registered packet fields
reg [31:0] payload_r;
reg [5:0]  dst_r;

wire [5:0] src_id = {SRC_X[2:0], SRC_Y[2:0]};

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        state     <= IDLE;
        tx_busy   <= 1'b0;
        nod_valid <= 1'b0;
        nod_data  <= {`DATA_WIDTH{1'b0}};
        payload_r <= 32'b0;
        dst_r     <= 6'b0;
    end else begin
        case (state)

            IDLE: begin
                nod_valid <= 1'b0;
                if (send_req) begin
                    payload_r <= cpu_payload;
                    dst_r     <= dst_id;
                    tx_busy   <= 1'b1;
                    state     <= HEAD;
                end
            end

            HEAD: begin
                // Build and present HEAD flit
                nod_data  <= {
                    2'b00,          // [129:128] flit type = HEAD
                    102'b0,         // [127:26]  payload region (unused in HEAD)
                    dst_r,          // [25:20]   RTID = destination (single-NoD)
                    4'b0,           // [19:16]   SCID = 0
                    4'b0,           // [15:12]   DCID = 0
                    src_id,         // [11:6]    SRID
                    dst_r           // [5:0]     DRID
                };
                nod_valid <= 1'b1;
                if (nod_valid && nod_ready) begin
                    // HEAD accepted — drop valid for one cycle before TAIL
                    nod_valid <= 1'b0;
                    state     <= TAIL;
                end
            end

            TAIL: begin
                // Build and present TAIL flit — payload sits in [127:96]
                nod_data  <= {
                    2'b10,          // [129:128] flit type = TAIL
                    payload_r,      // [127:96]  32-bit CPU payload
                    96'b0           // [95:0]    unused
                };
                nod_valid <= 1'b1;
                if (nod_valid && nod_ready) begin
                    // TAIL accepted — done
                    nod_valid <= 1'b0;
                    tx_busy   <= 1'b0;
                    state     <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
