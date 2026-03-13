`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/04/06 22:51:03
// Design Name: 
// Module Name: data_mem
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module data_mem(
    input                   rst,
    input                   clk, 
    input [3:0]             dm_ctl,
    input [31:0]            addr,
    input [31:0]            dm_store,
    output[31:0]            dm_load,
    output reg              dm_ack 
);

    reg [7:0] bram[255:0];
    integer i;

    // Request-driven fixed-latency transaction state.
    reg        busy;
    reg [1:0]  wait_cnt;
    reg        ack_pending;
    reg [3:0]  pending_dm_ctl;
    reg [31:0] pending_addr;
    reg [31:0] pending_store;

    // Request decode from existing dm_ctl:
    // 1000: load request tag; 0001/0011/1111: store requests.
    wire req_load  = (dm_ctl == 4'b1000);
    wire req_sb    = (dm_ctl == 4'b0001);
    wire req_sh    = (dm_ctl == 4'b0011);
    wire req_sw    = (dm_ctl == 4'b1111);
    wire dm_req_i  = req_load | req_sb | req_sh | req_sw;

    // Read path uses latched address while a request is in flight.
    wire [31:0] rd_addr = busy ? pending_addr : addr;
    wire [7:0] addr_b0 = rd_addr[7:0];
    wire [7:0] addr_b1 = rd_addr[7:0] + 8'd1;
    wire [7:0] addr_b2 = rd_addr[7:0] + 8'd2;
    wire [7:0] addr_b3 = rd_addr[7:0] + 8'd3;
    assign dm_load = {bram[addr_b3], bram[addr_b2], bram[addr_b1], bram[addr_b0]};

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            bram[i] = i[7:0];
        end
        bram[80] = 8'd10;
        busy = 1'b0;
        wait_cnt = 2'd0;
        ack_pending = 1'b0;
        pending_dm_ctl = 4'b0000;
        pending_addr = 32'b0;
        pending_store = 32'b0;
    end

    // Transaction engine: one request at a time, fixed 4-cycle latency.
    always@(negedge rst or posedge clk) begin
        if (!rst) begin
            busy <= 1'b0;
            wait_cnt <= 2'd0;
            ack_pending <= 1'b0;
            pending_dm_ctl <= 4'b0000;
            pending_addr <= 32'b0;
            pending_store <= 32'b0;
            for (i = 0; i < 256; i = i + 1)
                bram[i] <= 8'b0;
        end else begin
            ack_pending <= 1'b0;

            if (busy) begin
                if (wait_cnt == 2'd3) begin
                    // Request completes in this cycle.
                    busy <= 1'b0;
                    wait_cnt <= 2'd0;
                    ack_pending <= 1'b1;

                    case (pending_dm_ctl)
                        4'b0001: begin // SB
                            bram[pending_addr[7:0]] <= pending_store[7:0];
                        end
                        4'b0011: begin // SH
                            bram[pending_addr[7:0]] <= pending_store[7:0];
                            bram[pending_addr[7:0] + 8'd1] <= pending_store[15:8];
                        end
                        4'b1111: begin // SW
                            bram[pending_addr[7:0]] <= pending_store[7:0];
                            bram[pending_addr[7:0] + 8'd1] <= pending_store[15:8];
                            bram[pending_addr[7:0] + 8'd2] <= pending_store[23:16];
                            bram[pending_addr[7:0] + 8'd3] <= pending_store[31:24];
                        end
                        default: begin
                            // Load or unsupported mask: no writeback.
                        end
                    endcase
                end else begin
                    wait_cnt <= wait_cnt + 2'd1;
                end
            end else if (dm_req_i) begin
                // Accept a new request.
                busy <= 1'b1;
                wait_cnt <= 2'd0;
                pending_dm_ctl <= dm_ctl;
                pending_addr <= addr;
                pending_store <= dm_store;
            end
        end
    end

    // Ack changes on negedge to avoid same-edge race with pipeline posedge flops.
    always@(negedge rst or negedge clk) begin
        if (!rst)
            dm_ack <= 1'b1;
        else
            dm_ack <= ack_pending;
    end

endmodule

