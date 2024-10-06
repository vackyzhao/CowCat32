module alu_mux( pc,
                d1,
                d2,
                imm,
               
                alu_forward,
                din,
                trim_forward,
                A_sel,
                B_sel,
                A_out,
                B_out
                );
    
    input  [31:0] d1, d2, imm, pc, alu_forward, din, trim_forward;
    input  [2:0] A_sel; 
    input  [2:0] B_sel;
    output reg [31:0] A_out, B_out;
    
    always @(*) begin
        casex(A_sel)
            3'b000: A_out = $unsigned(pc);
            3'b001: A_out = d1;
            3'b010: A_out = alu_forward;
            3'b011: A_out = din;
            3'b1xx: A_out = trim_forward;
            default: A_out = d1;
        endcase
        casex(B_sel)
            3'b000: B_out = d2;
            3'b001: B_out = imm;
            3'b010: B_out = alu_forward;
            3'b011: B_out = din;
            3'b1xx: B_out = trim_forward;
            default: B_out = d2;
        endcase
    end
    
endmodule
