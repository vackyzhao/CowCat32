`timescale 1ns / 1ps

module b_adder (input [31:0]pc,
                input [31:0]imm,
                output reg[31:0]pc_br);
always @(*)
begin
    pc_br = $unsigned($unsigned(pc) + $signed(imm));
end
endmodule
