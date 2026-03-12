module pc_reg (clk, rst, pc_br, alu_out, pc_sel, pc, hold, flush);
    input clk;  
    input rst;
    input hold;
    input flush;
    input [31:0] pc_br;   
    input [31:0] alu_out;   
    input [1:0] pc_sel;       
    reg [31:0] pc_MUX;
    output [31:0] pc;
    pp_register pc_pp(.d(pc_MUX), .q(pc), .rst(rst), .hold(hold), .flush(1), .clk(clk));
    always@(*)
    begin
    case(pc_sel)
        0 : pc_MUX = pc + 4;
        1 : pc_MUX = pc_br;
        2 : pc_MUX = alu_out;
        default pc_MUX = 0;
        endcase
    end
    
    /*always @(negedge rst or posedge clk) begin
        if(rst == 0)
            pc <= 32'b0;    //rst  turn pc to 0
        else begin
            pc <= pc_MUX; 
        end
    end*/
endmodule