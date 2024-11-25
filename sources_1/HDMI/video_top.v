// ==============0ooo===================================================0ooo===========
// =  Copyright (C) 2014-2020 Gowin Semiconductor Technology Co.,Ltd.
// =                     All rights reserved.
// ====================================================================================
// 
//  __      __      __
//  \ \    /  \    / /   [File name   ] video_top.v
//   \ \  / /\ \  / /    [Description ] Video demo
//    \ \/ /  \ \/ /     [Timestamp   ] Friday April 10 14:00:30 2020
//     \  /    \  /      [version     ] 2.0
//      \/      \/
//
// ==============0ooo===================================================0ooo===========
// Code Revision History :
// ----------------------------------------------------------------------------------
// Ver:    |  Author    | Mod. Date    | Changes Made:
// ----------------------------------------------------------------------------------
// V1.0    | Caojie     |  4/10/20     | Initial version 
// ----------------------------------------------------------------------------------
// V2.0    | Caojie     | 10/30/20     | DVI IP update 
// ----------------------------------------------------------------------------------
// ==============0ooo===================================================0ooo===========

module video_top
(
    input             I_clk           , //27Mhz
    input             I_rst_n         ,
    output            O_tmds_clk_p    ,
    output            O_tmds_clk_n    ,
    output     [2:0]  O_tmds_data_p   ,//{r,g,b}
    output     [2:0]  O_tmds_data_n
);

//==================================================

reg  [31:0] run_cnt;
wire        running;

//--------------------------
reg        tp0_vs_in  ;
wire        tp0_hs_in  ;
wire        tp0_de_in ;
wire [ 7:0] tp0_data_r/*synthesis syn_keep=1*/;
wire [ 7:0] tp0_data_g/*synthesis syn_keep=1*/;
wire [ 7:0] tp0_data_b/*synthesis syn_keep=1*/;

reg         vs_r;
reg  [9:0]  cnt_vs;

//------------------------------------
//HDMI TX
wire serial_clk;
wire pll_lock;

wire hdmi_rst_n;

wire pix_clk;

reg [23:0]data;
reg addr;


HDMI_patten_generate HDMI_patten_generate2(
    .clk(pix_clk),
    .rst(hdmi_rst_n ),
       
    .data(),
    .addr(),

    .o_de (tp0_de_in ),   
    .o_hs (tp0_hs_in ),
    .o_vs (tp0_vs_in),
    .o_data_r(tp0_data_r),    
    .o_data_g(tp0_data_g),
    .o_data_b(tp0_data_b)    
    );

always@(posedge pix_clk)
begin
    vs_r<=tp0_vs_in;
end

always@(posedge pix_clk or negedge hdmi_rst_n)
begin
    if(!hdmi_rst_n)
        cnt_vs<=0;
    else if(vs_r && !tp0_vs_in) //vs24 falling edge
        cnt_vs<=cnt_vs+1'b1;
end 

//==============================================================================
//TMDS TX(HDMI4)
TMDS_rPLL u_tmds_rpll
(.clkin     (I_clk     )     //input clk 
,.clkout    (serial_clk)     //output clk 
,.lock      (pll_lock  )     //output lock
);

assign hdmi_rst_n = I_rst_n & pll_lock;

CLKDIV u_clkdiv
(.RESETN(hdmi_rst_n)
,.HCLKIN(serial_clk) //clk  x5
,.CLKOUT(pix_clk)    //clk  x1
,.CALIB (1'b1)
);
defparam u_clkdiv.DIV_MODE="5";
defparam u_clkdiv.GSREN="false";

DVI_TX_Top DVI_TX_Top_inst
(
    .I_rst_n       (hdmi_rst_n   ),  //asynchronous reset, low active
    .I_serial_clk  (serial_clk    ),
    .I_rgb_clk     (pix_clk       ),  //pixel clock
    .I_rgb_vs      (tp0_vs_in     ), 
    .I_rgb_hs      (tp0_hs_in     ),    
    .I_rgb_de      (tp0_de_in     ), 
    .I_rgb_r       (  tp0_data_r ),  //tp0_data_r
    .I_rgb_g       (  tp0_data_g  ),  
    .I_rgb_b       (  tp0_data_b  ),  
    .O_tmds_clk_p  (O_tmds_clk_p  ),
    .O_tmds_clk_n  (O_tmds_clk_n  ),
    .O_tmds_data_p (O_tmds_data_p ),  //{r,g,b}
    .O_tmds_data_n (O_tmds_data_n )
);


endmodule