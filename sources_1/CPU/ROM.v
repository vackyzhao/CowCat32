module ROM (IMEM_addr, IMEM_inst);
    input wire[31:0] IMEM_addr;   // PC
    output reg[31:0] IMEM_inst;    // inst
    reg[31:0] rom_mem[0:11];  // create a memory for inst
    
    always @(*) begin
         IMEM_inst <= rom_mem[IMEM_addr>>2];
    end
endmodule