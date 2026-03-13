module alu(alu_a,
           alu_b,
           alu_ctl,
           alu_out);
    input [31:0] alu_a, alu_b;
    input [4:0] alu_ctl;
    output reg[31:0] alu_out;
    parameter
    ADD = 5'b0000_1,
    SLT = 5'b0001_0,
    SLTU = 5'b0001_1,
    AND = 5'b0010_0,
    OR = 5'b0010_1,
    XOR = 5'b0011_0,
    SLL = 5'b0011_1,
    SRL = 5'b0100_0,
    SUB = 5'b0100_1,
    SRA = 5'b0101_0,
    BEQ = 5'b0101_1,
    BNE = 5'b0110_0,
    BLT = 5'b0110_1,
    BLTU = 5'b0111_0,
    BGE = 5'b0111_1,
    BGEU = 5'b1000_0,
    LUI = 5'b1000_1,
    ADDU = 5'b1001_0;
    always@(*)
    begin
        case(alu_ctl)
            ADD: alu_out = $signed(alu_a) + $signed(alu_b);
            SLT: begin
                if ($signed(alu_a) < $signed(alu_b))
                    alu_out = 1;
                else
                    alu_out = 0;
            end
            SLTU: begin
                if ($unsigned(alu_a)<$unsigned(alu_b))
                    alu_out = 1;
                else
                    alu_out = 0;
            end
            AND: alu_out = alu_a & alu_b;
            OR: alu_out  = alu_a | alu_b;
            XOR: alu_out = alu_a ^ alu_b;
            SLL: alu_out = $signed(alu_a) << $unsigned(alu_b);
            SRL: alu_out = $signed(alu_a) >> $unsigned(alu_b);
            SUB: alu_out = $signed($signed(alu_a) - $signed(alu_b));
            SRA: alu_out = $signed(alu_a) >>> $unsigned(alu_b);
            BEQ: begin
                if (alu_a == alu_b)
                    alu_out = 1;
                else
                    alu_out = 0;
            end
            BNE: begin
                if (alu_a != alu_b)
                    alu_out = 1;
                else
                    alu_out = 0;
            end
            BLT: begin
                if ($signed(alu_a) < $signed(alu_b))
                    alu_out = 1;
                else
                    alu_out = 0;
            end
            BLTU: begin
                if ($unsigned(alu_a) < $unsigned(alu_b))
                    alu_out = 1;
                else
                    alu_out = 0;
            end
            BGE: begin
                if ($signed(alu_a) >= $signed(alu_b))
                    alu_out = 1;
                else
                    alu_out = 0;
            end
            
            BGEU: begin
                if ($unsigned(alu_a) >= $unsigned(alu_b))
                    alu_out = 1;
                else
                    alu_out = 0;
            end
            LUI: alu_out      = $signed(alu_b);
            ADDU:alu_out      = $unsigned($unsigned(alu_a) + $signed(alu_b));
            default : alu_out = 32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx;
            
        endcase
    end
    
endmodule
