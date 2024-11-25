module dff_set (clk, rst, set_data, data_i, data_o);

    input wire clk;
    input wire rst;
    input wire [31:0] set_data;
    input wire [31:0] data_i;
    output reg [31:0] data_o;

    always @(negedge rst or posedge clk) begin
        data_o <= (rst == 0) ? set_data : data_i;
    end
endmodule