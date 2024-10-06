`timescale 1ns / 1ps

module tb_soc_top;

    // Inputs
    reg clk;
    reg rtc_clk;
    reg rst;
    wire [31:0] gpio;

    // Instantiate the Unit Under Test (UUT)
    soc_top uut (
        .clk(clk),
        .rtc_clk(rtc_clk),
        .rst(rst),
        .gpio(gpio)
    );

    // Generate clock signals
    always #5 clk = ~clk;  // 8MHz clock signal
    always #50 rtc_clk = ~rtc_clk;  // 32.768kHz RTC clock signal

    // Initial block for simulation
    initial begin
        // Initialize Inputs
        clk = 0;
        rtc_clk = 0;
        rst = 1;
        
        // Reset the system
        #100;  // Wait 100ns to simulate reset duration
        rst = 0;  // Release reset
        
        // Test some functionality
        #500;
        // At this point, you can simulate read/write requests or other operations depending on the expected behavior of soc_top.
        #100;  // Wait 100ns to simulate reset duration
        rst = 1;  // Release reset 
        #100;  // Wait 100ns to simulate reset duration
        rst = 0;  // Release reset
        // Finish simulation after a specific time
        #5000;
        $finish;
    end
endmodule
