// lobsterpawn_top.v
// LobsterPawn SoC top-level — 2-tile demonstration configuration.
//
// Tile 0 at NoD position (X=0, Y=0)
// Tile 1 at NoD position (X=4, Y=4)
//
// All other 23 NoD ports are tied off.
// Extend by adding more cpu_tile_top instances and connecting more ports.

`include "param.vh"

module lobsterpawn_top (
    input  wire        clk,
    input  wire        rtc_clk,
    input  wire        rst,

    // GPIO exposed from tile 0 only (for board-level connectivity)
    inout  wire [31:0] gpio_tile0,
    inout  wire [31:0] gpio_tile1
);

// -----------------------------------------------------------------------
// NoD local port signals — one set per tile
// -----------------------------------------------------------------------
wire [`DATA_WIDTH-1:0] tx_data_t0, rx_data_t0;
wire                   tx_valid_t0, tx_ready_t0;
wire                   rx_valid_t0, rx_ready_t0;

wire [`DATA_WIDTH-1:0] tx_data_t1, rx_data_t1;
wire                   tx_valid_t1, tx_ready_t1;
wire                   rx_valid_t1, rx_ready_t1;

// -----------------------------------------------------------------------
// CPU Tile 0  —  NoD port (X=0, Y=0)
// -----------------------------------------------------------------------
cpu_tile_top #(.NODE_X(0), .NODE_Y(0)) tile0 (
    .clk         (clk),
    .rtc_clk     (rtc_clk),
    .rst         (rst),
    .gpio        (gpio_tile0),
    .nod_tx_data  (tx_data_t0),
    .nod_tx_valid (tx_valid_t0),
    .nod_tx_ready (tx_ready_t0),
    .nod_rx_data  (rx_data_t0),
    .nod_rx_valid (rx_valid_t0),
    .nod_rx_ready (rx_ready_t0)
);

// -----------------------------------------------------------------------
// CPU Tile 1  —  NoD port (X=4, Y=4)
// -----------------------------------------------------------------------
cpu_tile_top #(.NODE_X(4), .NODE_Y(4)) tile1 (
    .clk         (clk),
    .rtc_clk     (rtc_clk),
    .rst         (rst),
    .gpio        (gpio_tile1),
    .nod_tx_data  (tx_data_t1),
    .nod_tx_valid (tx_valid_t1),
    .nod_tx_ready (tx_ready_t1),
    .nod_rx_data  (rx_data_t1),
    .nod_rx_valid (rx_valid_t1),
    .nod_rx_ready (rx_ready_t1)
);

// -----------------------------------------------------------------------
// NoD — 5×5 mesh, tie off all ports except (0,0) and (4,4)
// -----------------------------------------------------------------------
// Helper macro for tying off an unused local port
// (unused input to NoD = tie valid low; unused output from NoD = tie ready low)

NoD #(.NODID(0)) u_nod (
    .CDCLK    (clk),
    .CDRESETn (~rst),

    // Tile 0 at (X=0, Y=0)
    .CDIDATA_X0_Y0 (tx_data_t0),  .CDIVALID_X0_Y0 (tx_valid_t0), .CDIREADY_X0_Y0 (tx_ready_t0),
    .CDODATA_X0_Y0 (rx_data_t0),  .CDOVALID_X0_Y0 (rx_valid_t0), .CDOREADY_X0_Y0 (rx_ready_t0),

    // Unused ports (X=0 column, Y=1..4)
    .CDIDATA_X0_Y1(130'b0),.CDIVALID_X0_Y1(1'b0),.CDIREADY_X0_Y1(),.CDODATA_X0_Y1(),.CDOVALID_X0_Y1(),.CDOREADY_X0_Y1(1'b0),
    .CDIDATA_X0_Y2(130'b0),.CDIVALID_X0_Y2(1'b0),.CDIREADY_X0_Y2(),.CDODATA_X0_Y2(),.CDOVALID_X0_Y2(),.CDOREADY_X0_Y2(1'b0),
    .CDIDATA_X0_Y3(130'b0),.CDIVALID_X0_Y3(1'b0),.CDIREADY_X0_Y3(),.CDODATA_X0_Y3(),.CDOVALID_X0_Y3(),.CDOREADY_X0_Y3(1'b0),
    .CDIDATA_X0_Y4(130'b0),.CDIVALID_X0_Y4(1'b0),.CDIREADY_X0_Y4(),.CDODATA_X0_Y4(),.CDOVALID_X0_Y4(),.CDOREADY_X0_Y4(1'b0),

    // Unused ports (X=1 column)
    .CDIDATA_X1_Y0(130'b0),.CDIVALID_X1_Y0(1'b0),.CDIREADY_X1_Y0(),.CDODATA_X1_Y0(),.CDOVALID_X1_Y0(),.CDOREADY_X1_Y0(1'b0),
    .CDIDATA_X1_Y1(130'b0),.CDIVALID_X1_Y1(1'b0),.CDIREADY_X1_Y1(),.CDODATA_X1_Y1(),.CDOVALID_X1_Y1(),.CDOREADY_X1_Y1(1'b0),
    .CDIDATA_X1_Y2(130'b0),.CDIVALID_X1_Y2(1'b0),.CDIREADY_X1_Y2(),.CDODATA_X1_Y2(),.CDOVALID_X1_Y2(),.CDOREADY_X1_Y2(1'b0),
    .CDIDATA_X1_Y3(130'b0),.CDIVALID_X1_Y3(1'b0),.CDIREADY_X1_Y3(),.CDODATA_X1_Y3(),.CDOVALID_X1_Y3(),.CDOREADY_X1_Y3(1'b0),
    .CDIDATA_X1_Y4(130'b0),.CDIVALID_X1_Y4(1'b0),.CDIREADY_X1_Y4(),.CDODATA_X1_Y4(),.CDOVALID_X1_Y4(),.CDOREADY_X1_Y4(1'b0),

    // Unused ports (X=2 column)
    .CDIDATA_X2_Y0(130'b0),.CDIVALID_X2_Y0(1'b0),.CDIREADY_X2_Y0(),.CDODATA_X2_Y0(),.CDOVALID_X2_Y0(),.CDOREADY_X2_Y0(1'b0),
    .CDIDATA_X2_Y1(130'b0),.CDIVALID_X2_Y1(1'b0),.CDIREADY_X2_Y1(),.CDODATA_X2_Y1(),.CDOVALID_X2_Y1(),.CDOREADY_X2_Y1(1'b0),
    .CDIDATA_X2_Y2(130'b0),.CDIVALID_X2_Y2(1'b0),.CDIREADY_X2_Y2(),.CDODATA_X2_Y2(),.CDOVALID_X2_Y2(),.CDOREADY_X2_Y2(1'b0),
    .CDIDATA_X2_Y3(130'b0),.CDIVALID_X2_Y3(1'b0),.CDIREADY_X2_Y3(),.CDODATA_X2_Y3(),.CDOVALID_X2_Y3(),.CDOREADY_X2_Y3(1'b0),
    .CDIDATA_X2_Y4(130'b0),.CDIVALID_X2_Y4(1'b0),.CDIREADY_X2_Y4(),.CDODATA_X2_Y4(),.CDOVALID_X2_Y4(),.CDOREADY_X2_Y4(1'b0),

    // Unused ports (X=3 column)
    .CDIDATA_X3_Y0(130'b0),.CDIVALID_X3_Y0(1'b0),.CDIREADY_X3_Y0(),.CDODATA_X3_Y0(),.CDOVALID_X3_Y0(),.CDOREADY_X3_Y0(1'b0),
    .CDIDATA_X3_Y1(130'b0),.CDIVALID_X3_Y1(1'b0),.CDIREADY_X3_Y1(),.CDODATA_X3_Y1(),.CDOVALID_X3_Y1(),.CDOREADY_X3_Y1(1'b0),
    .CDIDATA_X3_Y2(130'b0),.CDIVALID_X3_Y2(1'b0),.CDIREADY_X3_Y2(),.CDODATA_X3_Y2(),.CDOVALID_X3_Y2(),.CDOREADY_X3_Y2(1'b0),
    .CDIDATA_X3_Y3(130'b0),.CDIVALID_X3_Y3(1'b0),.CDIREADY_X3_Y3(),.CDODATA_X3_Y3(),.CDOVALID_X3_Y3(),.CDOREADY_X3_Y3(1'b0),
    .CDIDATA_X3_Y4(130'b0),.CDIVALID_X3_Y4(1'b0),.CDIREADY_X3_Y4(),.CDODATA_X3_Y4(),.CDOVALID_X3_Y4(),.CDOREADY_X3_Y4(1'b0),

    // Unused ports (X=4, Y=0..3)
    .CDIDATA_X4_Y0(130'b0),.CDIVALID_X4_Y0(1'b0),.CDIREADY_X4_Y0(),.CDODATA_X4_Y0(),.CDOVALID_X4_Y0(),.CDOREADY_X4_Y0(1'b0),
    .CDIDATA_X4_Y1(130'b0),.CDIVALID_X4_Y1(1'b0),.CDIREADY_X4_Y1(),.CDODATA_X4_Y1(),.CDOVALID_X4_Y1(),.CDOREADY_X4_Y1(1'b0),
    .CDIDATA_X4_Y2(130'b0),.CDIVALID_X4_Y2(1'b0),.CDIREADY_X4_Y2(),.CDODATA_X4_Y2(),.CDOVALID_X4_Y2(),.CDOREADY_X4_Y2(1'b0),
    .CDIDATA_X4_Y3(130'b0),.CDIVALID_X4_Y3(1'b0),.CDIREADY_X4_Y3(),.CDODATA_X4_Y3(),.CDOVALID_X4_Y3(),.CDOREADY_X4_Y3(1'b0),

    // Tile 1 at (X=4, Y=4)
    .CDIDATA_X4_Y4 (tx_data_t1),  .CDIVALID_X4_Y4 (tx_valid_t1), .CDIREADY_X4_Y4 (tx_ready_t1),
    .CDODATA_X4_Y4 (rx_data_t1),  .CDOVALID_X4_Y4 (rx_valid_t1), .CDOREADY_X4_Y4 (rx_ready_t1)
);

endmodule
