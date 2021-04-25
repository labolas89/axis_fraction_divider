// *************************************************************************************************
// Project History  :
//
//   - March. 24, 2021 : First release by ui-jong Lee
//
// -------------------------------------------------------------------------------------------------
// File Revision and Comment for current project
//
//   $Revision: 1.0 $
//
//   Note     :
//
// *************************************************************************************************

`define msb(n, limit)   (n <= limit ? limit : n - 1)
`define min(a, b)       (a < b ? a : b)
`define align(n, width)   (((width-((width/n)*n)) > 0 ? width/n + 1 : width/n) * n)

`timescale 1 ns / 1 ps

module axis_fraction_divider #
(
    parameter integer DIVISOR_WIDTH        /*verilator public*/ = 32,
    parameter integer DIVISOR_USER_WIDTH   /*verilator public*/ = 0,
    parameter integer DIVIDEND_WIDTH       /*verilator public*/ = 32,
    parameter integer DIVIDEND_USER_WIDTH  /*verilator public*/ = 0,
    parameter integer FRACTIONAL_WIDTH     /*verilator public*/ = 16,
    parameter integer DETECT_DIV_ZERO      /*verilator public*/ = 1,
    parameter integer COMB_FF_INTERVAL     /*verilator public*/ = 2
)
(
    aclk,
    aclken,
    aresetn,

    s_axis_divisor_tvalid,
    s_axis_divisor_tdata,
    s_axis_divisor_tuser,

    s_axis_dividend_tvalid,
    s_axis_dividend_tdata,
    s_axis_dividend_tuser,

    m_axis_dout_tvalid,
    m_axis_dout_tdata,
    m_axis_dout_tuser
);

//--------------------------------------------------------------------------------------------------
//                              IO
//--------------------------------------------------------------------------------------------------

input  wire                                                                  aclk                  ;
input  wire                                                                  aclken                ;
input  wire                                                                  aresetn               ;
             
input  wire                                                                  s_axis_divisor_tvalid ;
input  wire [`align(8, DIVISOR_WIDTH)-1:0]                                   s_axis_divisor_tdata  ;
input  wire [`msb(DIVISOR_USER_WIDTH,0):0]                                   s_axis_divisor_tuser  ;
             
input  wire                                                                  s_axis_dividend_tvalid;
input  wire [`align(8, DIVIDEND_WIDTH)-1:0]                                  s_axis_dividend_tdata ;
input  wire [`msb(DIVIDEND_USER_WIDTH,0):0]                                  s_axis_dividend_tuser ;
             
output reg                                                                   m_axis_dout_tvalid    ;
output reg  [`align(8, (DIVIDEND_WIDTH+FRACTIONAL_WIDTH))-1:0]               m_axis_dout_tdata     ;
output reg  [`msb(DETECT_DIV_ZERO+DIVISOR_USER_WIDTH+DIVIDEND_USER_WIDTH,0):0] m_axis_dout_tuser   ;


//--------------------------------------------------------------------------------------------------
//                              Local Parameter
//--------------------------------------------------------------------------------------------------

localparam TDATA_WIDTH = DIVIDEND_WIDTH + FRACTIONAL_WIDTH;
localparam TUSER_WIDTH = DIVISOR_USER_WIDTH + DIVIDEND_USER_WIDTH;

localparam [1:0] TUSER_BIT_ORDER = {
        (DIVISOR_USER_WIDTH>0),
        (DIVIDEND_USER_WIDTH>0)
    };

//--------------------------------------------------------------------------------------------------
//                              Reg / Wire
//--------------------------------------------------------------------------------------------------

genvar                                          i, ui                           ;

// for disable verilator message "Feedback to clock or circular logic"
/* verilator lint_off UNOPTFLAT */

reg                                             valid       [0:TDATA_WIDTH]     ;
reg     [TDATA_WIDTH-1:0]                       dividend    [0:TDATA_WIDTH]     ;
reg     [DIVISOR_WIDTH-1:0]                     divisor     [0:TDATA_WIDTH]     ;
reg     [TDATA_WIDTH-1:0]                       quotient    [0:TDATA_WIDTH]     ;
wire    [`msb(DETECT_DIV_ZERO+TUSER_WIDTH,0):0] concat_tuser                    ;


wire                                            zero_detect                     ;
wire                                            trans                           ;


//--------------------------------------------------------------------------------------------------
//                              Logic
//--------------------------------------------------------------------------------------------------

generate 
if (TUSER_WIDTH > 0) begin:divider_user_gen

    wire    [`msb(TUSER_WIDTH,1):0]             tuser                           ;
    reg     [`msb(TUSER_WIDTH,0):0]             user_data   [0:TDATA_WIDTH]     ;

    if      (TUSER_BIT_ORDER == 2'b00)
        assign tuser = {2'b0};
    else if (TUSER_BIT_ORDER == 2'b01)
        assign tuser = {1'b0, s_axis_dividend_tuser};
    else if (TUSER_BIT_ORDER == 2'b10)
        assign tuser = {1'b0, s_axis_divisor_tuser};
    else if (TUSER_BIT_ORDER == 2'b11)
        assign tuser = {s_axis_dividend_tuser, s_axis_divisor_tuser};
    
    always @(posedge aclk) begin
        if (~aresetn) begin
            user_data[0]    <= {(`msb(TUSER_WIDTH,0)+1){1'b0}};
        end
        else if (aclken) begin
            if (trans)
                user_data[0]    <= tuser[`msb(TUSER_WIDTH,0):0];
        end
    end


    for (ui=0; ui<TDATA_WIDTH; ui=ui+1) begin:divider_fifo_user_gen

        localparam IS_FF_TURN = ((ui+1)-((ui+1)/COMB_FF_INTERVAL)*COMB_FF_INTERVAL) == 0;

        if (IS_FF_TURN) begin:divider_fifo_user_gen_ff
            always @(posedge aclk) begin
                if (~aresetn)
                    user_data[ui+1]  <= {(`msb(TUSER_WIDTH,0)+1){1'b0}};
                else if (aclken) begin
                    if (valid[ui])
                        user_data[ui+1]  <= user_data[ui];
                end
            end
        end
        else begin:divider_fifo_user_gen_comb
            always @* begin
                user_data[ui+1] = user_data[ui];
            end
        end
    end

    if (DETECT_DIV_ZERO!=0) 
        assign concat_tuser = 
            {user_data[TDATA_WIDTH], (divisor[TDATA_WIDTH] == {(DIVISOR_WIDTH){1'b0}})};
    else
        assign concat_tuser = user_data[TDATA_WIDTH];
end
else begin:divider_user_gen_not
    if (DETECT_DIV_ZERO!=0) 
        assign concat_tuser = divisor[TDATA_WIDTH] == {(DIVISOR_WIDTH){1'b0}};
    else
        assign concat_tuser = 1'b0;
end
endgenerate

assign zero_detect = s_axis_divisor_tdata == {(`align(8, DIVISOR_WIDTH)){1'b0}};
assign trans = s_axis_divisor_tvalid & s_axis_dividend_tvalid;

always @(posedge aclk) begin
    if (~aresetn) begin
        m_axis_dout_tvalid <= 1'b0;
        m_axis_dout_tdata  <= {(`align(8, TDATA_WIDTH)){1'b0}};
        m_axis_dout_tuser  <= {(`msb(DETECT_DIV_ZERO+TUSER_WIDTH,0)+1){1'b0}};
    end
    else if (aclken) begin
        m_axis_dout_tvalid <= valid[TDATA_WIDTH];
        m_axis_dout_tdata  <= {{(`align(8, TDATA_WIDTH)-TDATA_WIDTH){1'b0}}, quotient[TDATA_WIDTH]};
        m_axis_dout_tuser  <= concat_tuser;
    end
end

always @(posedge aclk) begin
    if (~aresetn) begin
        valid[0]        <= 1'b0;
        dividend[0]     <= {(TDATA_WIDTH){1'b0}};
        divisor[0]      <= {(DIVISOR_WIDTH){1'b0}};
        quotient[0]     <= {(TDATA_WIDTH){1'b0}};
    end
    else if (aclken) begin
        valid[0]        <= trans;
        if (trans) begin
            dividend[0] <= {s_axis_dividend_tdata[DIVIDEND_WIDTH-1:0], {(FRACTIONAL_WIDTH){1'b0}}};
            divisor[0]  <= s_axis_divisor_tdata[DIVISOR_WIDTH-1:0];
            quotient[0] <= {(TDATA_WIDTH){1'b0}};
        end
    end
end


generate
for (i=0; i<TDATA_WIDTH; i=i+1) begin:divider_fifo_gen

    wire [TDATA_WIDTH-1:0]      tmp_dvdnd = dividend[i];
    wire [DIVISOR_WIDTH-1:0]    tmp_dvsr  = divisor[i];
    wire [TDATA_WIDTH-1:0]      tmp_qtnt = quotient[i];
    wire [TDATA_WIDTH-1:0]      new_qtnt;
    wire qtnt;
    wire [i:0] lower_dvsr;
    wire [TDATA_WIDTH-1:0] dvdnd;

    if (i == 0)
        assign new_qtnt = {qtnt, tmp_qtnt[TDATA_WIDTH-2:0]};
    else if (i == (TDATA_WIDTH-1))
        assign new_qtnt = {tmp_qtnt[TDATA_WIDTH-1:1], qtnt};
    else
        assign new_qtnt = {tmp_qtnt[TDATA_WIDTH-1:TDATA_WIDTH-i], qtnt, tmp_qtnt[TDATA_WIDTH-i-2:0]};

    wire [i:0] upper_dvdnd = tmp_dvdnd[TDATA_WIDTH-1 : TDATA_WIDTH-i-1];

    if (i > (DIVISOR_WIDTH-1))
        assign lower_dvsr = {{(i - (DIVISOR_WIDTH-1)){1'b0}}, tmp_dvsr};
    else 
        assign lower_dvsr = tmp_dvsr[i : 0];

    if ((i+1) > (DIVISOR_WIDTH-1))
        assign qtnt = (upper_dvdnd >= lower_dvsr);
    else
        assign qtnt = (|tmp_dvsr[DIVISOR_WIDTH-1 : i+1]) ? 1'b0 : (upper_dvdnd >= lower_dvsr);

    wire [i:0] remainder = qtnt ? (upper_dvdnd - lower_dvsr) : upper_dvdnd;

    if (i > (TDATA_WIDTH-2))
        assign dvdnd = remainder;
    else
        assign dvdnd = {remainder, tmp_dvdnd[TDATA_WIDTH-i-2 : 0]};

    localparam IS_FF_TURN = ((i+1)-((i+1)/COMB_FF_INTERVAL)*COMB_FF_INTERVAL) == 0;

    if (IS_FF_TURN) begin:divider_fifo_gen_ff
        always @(posedge aclk) begin
            if (~aresetn) begin
                valid[i+1]      <= 1'b0;
                dividend[i+1]   <= {(TDATA_WIDTH){1'b0}};
                divisor[i+1]    <= {(DIVISOR_WIDTH){1'b0}};
                quotient[i+1]   <= {(TDATA_WIDTH){1'b0}};
            end
            else if (aclken) begin
                valid[i+1]      <= valid[i];

                if (valid[i]) begin
                    dividend[i+1]   <= dvdnd;
                    divisor[i+1]    <= divisor[i];
                    quotient[i+1]   <= new_qtnt;
                end
            end
        end

    end
    else begin:divider_fifo_gen_comb
        always @* begin
            valid[i+1]      = valid[i];
            dividend[i+1]   = dvdnd;
            divisor[i+1]    = divisor[i];
            quotient[i+1]   = new_qtnt;
        end
    end
end
endgenerate


////////////////////////////////////////////////////////////////////////////////////////////////////
endmodule
////////////////////////////////////////////////////////////////////////////////////////////////////
