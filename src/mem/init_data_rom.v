`timescale 1ns/1ps

// AUTO-GENERATED. Do not edit by hand.
// Source: out/uart_hello.data.vh

module init_data_rom #(
    parameter integer DEPTH_WORDS = 10
) (
    input  wire [31:0] word_index,
    output wire [31:0] rdata
);

    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
        mem[32'h00000000] = 32'h20000000;
        mem[32'h00000001] = 32'h00000006;
        mem[32'h00000002] = 32'h20000018;
        mem[32'h00000003] = 32'h00000000;
        mem[32'h00000004] = 32'h6c6c6548;
        mem[32'h00000005] = 32'h7266206f;
        mem[32'h00000006] = 32'h43206d6f;
        mem[32'h00000007] = 32'h61697620;
        mem[32'h00000008] = 32'h52415520;
        mem[32'h00000009] = 32'h000a2154;
    end

    wire [$clog2(DEPTH_WORDS)-1:0] ridx = word_index[$clog2(DEPTH_WORDS)-1:0];
    assign rdata = mem[ridx];

endmodule
