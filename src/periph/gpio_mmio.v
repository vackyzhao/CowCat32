`timescale 1ns/1ps

// Very small GPIO MMIO block.
// Address map (offset from BASE):
//  0x00 DATA  (R/W) output data
//  0x04 DIR   (R/W) 1=output,0=input
//  0x08 IN    (R)   sampled input
module gpio_mmio (
    input  wire        clk,
    input  wire        rst,

    input  wire        req,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,

    output reg  [31:0] rdata,
    output wire        ack,

    input  wire [31:0] gpio_in,
    output reg  [31:0] gpio_out,
    output reg  [31:0] gpio_dir
);

    localparam integer DATA_OFF = 32'h00;
    localparam integer DIR_OFF  = 32'h04;
    localparam integer IN_OFF   = 32'h08;

    function [31:0] apply_wmask;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0]  be;
        reg   [31:0] m;
        begin
            m = { {8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}} };
            apply_wmask = (oldv & ~m) | (newv & m);
        end
    endfunction

    wire [31:0] off = addr[31:0];

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            gpio_out <= 32'h0;
            gpio_dir <= 32'h0;
        end else if (req && we) begin
            case (off)
                DATA_OFF: gpio_out <= apply_wmask(gpio_out, wdata, wstrb);
                DIR_OFF:  gpio_dir <= apply_wmask(gpio_dir, wdata, wstrb);
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (off)
            DATA_OFF: rdata = gpio_out;
            DIR_OFF:  rdata = gpio_dir;
            IN_OFF:   rdata = gpio_in;
            default:  rdata = 32'h0;
        endcase
    end

    assign ack = req;

endmodule
