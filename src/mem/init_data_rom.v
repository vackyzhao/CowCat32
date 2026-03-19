`timescale 1ns/1ps

// Generic init-data ROM used by the boot copy engine.
// Memory format (word-indexed):
//   word 0: rodata destination byte address
//   word 1: rodata word count
//   word 2: data   destination byte address
//   word 3: data   word count
//   word 4..      : rodata payload words, then data payload words
module init_data_rom #(
    parameter integer DEPTH_WORDS = 512
) (
    input  wire [31:0] word_index,
    output wire [31:0] rdata
);

    reg [31:0] mem [0:DEPTH_WORDS-1];
`ifndef SYNTHESIS
    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0000;
        end
    end
`endif

    wire [$clog2(DEPTH_WORDS)-1:0] ridx = word_index[$clog2(DEPTH_WORDS)-1:0];
    assign rdata = mem[ridx];

endmodule
