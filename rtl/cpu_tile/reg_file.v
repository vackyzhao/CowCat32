module reg_file (
    input wire clk_regs,    // clk
    input wire rst,

    //ID
    input wire[4:0] rs1,    
    input wire[4:0] rs2,

    // WB
    input wire[31:0] din,
    input wire [4:0] rd,
    input wire reg_wrt,

    //ID_EX
    output wire[31:0] d1_temp,
    output wire[31:0] d2_temp
);
    reg[31:0] regs[0:31];
    assign d1_temp = (rs1 == 0) ? 0 : regs[rs1];
    assign d2_temp = (rs2 == 0) ? 0 : regs[rs2];
    initial
    begin
                         regs[0]<=0;          regs[1]<=0;          regs[2]<=0;          regs[3]<=0; 
                         regs[4]<=0;          regs[5]<=0;          regs[6]<=0;          regs[7]<=0; 
                         regs[8]<=0;          regs[9]<=0;          regs[10]<=0;         regs[11]<=0; 
                         regs[12]<=0;         regs[13]<=0;         regs[14]<=0;         regs[15]<=0; 
                         regs[16]<=0;         regs[17]<=0;         regs[18]<=0;         regs[19]<=0; 
                         regs[20]<=0;         regs[21]<=0;         regs[22]<=0;         regs[23]<=0; 
                         regs[24]<=0;         regs[25]<=0;         regs[26]<=0;         regs[27]<=0; 
                         regs[28]<=0;         regs[29]<=0;         regs[30]<=0;         regs[31]<=0;  
    end
    
    always @(negedge rst or posedge clk_regs)begin
    
        if(rst==0) begin
                     regs[0]<=0;          regs[1]<=0;          regs[2]<=0;          regs[3]<=0; 
                     regs[4]<=0;          regs[5]<=0;          regs[6]<=0;          regs[7]<=0; 
                     regs[8]<=0;          regs[9]<=0;          regs[10]<=0;         regs[11]<=0; 
                     regs[12]<=0;         regs[13]<=0;         regs[14]<=0;         regs[15]<=0; 
                     regs[16]<=0;         regs[17]<=0;         regs[18]<=0;         regs[19]<=0; 
                     regs[20]<=0;         regs[21]<=0;         regs[22]<=0;         regs[23]<=0; 
                     regs[24]<=0;         regs[25]<=0;         regs[26]<=0;         regs[27]<=0; 
                     regs[28]<=0;         regs[29]<=0;         regs[30]<=0;         regs[31]<=0;  
        end
        else if(reg_wrt & (rd != 5'b0)) begin
            regs[rd] <= din;
        end
        else 
        regs[rd] = regs[rd];
    end   
endmodule
