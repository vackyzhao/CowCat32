`timescale 1ns/1ps

// Boot-time copy engine:
// - Runs after external reset deasserts
// - Copies .rodata/.data initial payloads from init_data_rom into DMEM
// - Asserts boot_done when finished
// CPU must remain in reset until boot_done=1.
module boot_copy_init (
    input  wire        clk,
    input  wire        rst,

    // source ROM
    output reg  [31:0] rom_word_index,
    input  wire [31:0] rom_rdata,

    // destination DMEM init port
    output wire        init_req,
    output wire [31:0] init_addr,
    output wire [31:0] init_wdata,
    output wire [3:0]  init_wstrb,

    output wire        boot_done,
    output wire        boot_busy
);

    localparam [2:0]
        ST_HDR0 = 3'd0,
        ST_HDR1 = 3'd1,
        ST_HDR2 = 3'd2,
        ST_HDR3 = 3'd3,
        ST_RO   = 3'd4,
        ST_DATA = 3'd5,
        ST_DONE = 3'd6;

    reg [2:0]  st;
    reg [31:0] ro_dst_addr;
    reg [31:0] ro_words;
    reg [31:0] data_dst_addr;
    reg [31:0] data_words;
    reg [31:0] copy_idx;

    assign init_req   = (st == ST_RO && (copy_idx < ro_words)) ||
                        (st == ST_DATA && (copy_idx < data_words));
    assign init_addr  = (st == ST_RO)   ? (ro_dst_addr   + {copy_idx[29:0], 2'b00}) :
                        (st == ST_DATA) ? (data_dst_addr + {copy_idx[29:0], 2'b00}) :
                                          32'h0000_0000;
    assign init_wdata = rom_rdata;
    assign init_wstrb = init_req ? 4'hF : 4'h0;

    assign boot_done = (st == ST_DONE);
    assign boot_busy = !boot_done;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            st            <= ST_HDR0;
            rom_word_index<= 32'd0;
            ro_dst_addr   <= 32'd0;
            ro_words      <= 32'd0;
            data_dst_addr <= 32'd0;
            data_words    <= 32'd0;
            copy_idx      <= 32'd0;
        end else begin
            case (st)
                ST_HDR0: begin
                    ro_dst_addr    <= rom_rdata;
                    rom_word_index <= 32'd1;
                    st             <= ST_HDR1;
                end
                ST_HDR1: begin
                    ro_words       <= rom_rdata;
                    rom_word_index <= 32'd2;
                    st             <= ST_HDR2;
                end
                ST_HDR2: begin
                    data_dst_addr  <= rom_rdata;
                    rom_word_index <= 32'd3;
                    st             <= ST_HDR3;
                end
                ST_HDR3: begin
                    data_words <= rom_rdata;
                    copy_idx   <= 32'd0;
                    if (ro_words != 32'd0) begin
                        rom_word_index <= 32'd4;
                        st             <= ST_RO;
                    end else if (rom_rdata != 32'd0) begin
                        rom_word_index <= 32'd4 + ro_words;
                        st             <= ST_DATA;
                    end else begin
                        st <= ST_DONE;
                    end
                end
                ST_RO: begin
                    if (copy_idx + 32'd1 < ro_words) begin
                        copy_idx      <= copy_idx + 32'd1;
                        rom_word_index<= 32'd4 + (copy_idx + 32'd1);
                    end else begin
                        copy_idx <= 32'd0;
                        if (data_words != 32'd0) begin
                            rom_word_index <= 32'd4 + ro_words;
                            st             <= ST_DATA;
                        end else begin
                            st <= ST_DONE;
                        end
                    end
                end
                ST_DATA: begin
                    if (copy_idx + 32'd1 < data_words) begin
                        copy_idx      <= copy_idx + 32'd1;
                        rom_word_index<= 32'd4 + ro_words + (copy_idx + 32'd1);
                    end else begin
                        st <= ST_DONE;
                    end
                end
                default: begin
                    st <= ST_DONE;
                end
            endcase
        end
    end

endmodule
