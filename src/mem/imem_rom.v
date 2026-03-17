`timescale 1ns/1ps

// Instruction ROM (read-only), word addressed.
// - Combinational read for simple bring-up.
// - Use $readmemh for initialization in simulation.
//   For synthesis, replace/init with FPGA ROM/BRAM as needed.
module imem_rom #(
    // Default IMEM size: 2048 words = 8KiB (FPGA-friendly). Override as needed.
    parameter integer DEPTH_WORDS = 2048
) (
    input  wire [31:0] addr,
    output wire [31:0] rdata
);

    reg [31:0] mem [0:DEPTH_WORDS-1];

`ifndef SYNTHESIS
    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
            mem[i] = 32'h0000_0013; // NOP
        end
    end
`endif

    wire [$clog2(DEPTH_WORDS)-1:0] widx = addr[2 +: $clog2(DEPTH_WORDS)];
    assign rdata = mem[widx];

endmodule
