/********************************************/
/* ctrl_regs.v                              */
/* control registers                        */
/*                                          */
/* 2012, rok.krajnc@gmail.com               */
/********************************************/



module ctrl_regs #(
  parameter QAW = 22,             // qmem address width
  parameter QDW = 32,             // qmem data width
  parameter QSW = QDW/8           // qmem select width
)(
  // system
  input  wire           clk,
  input  wire           rst,
  // qmem bus
  input  wire [QAW-1:0] adr,
  input  wire           cs,
  input  wire           we,
  input  wire [QSW-1:0] sel,
  input  wire [QDW-1:0] dat_w,
  output reg  [QDW-1:0] dat_r,
  output reg            ack,
  output wire           err,
  // registers
  output reg            sys_rst,
  output reg            minimig_rst,
  output wire           uart_txd,
  output reg  [  4-1:0] spi_cs_n,
  output wire           spi_clk,
  output wire           spi_do,
  input  wire           spi_di
);


initial sys_rst = 1'b0; // initial value for sys_rst



////////////////////////////////////////
// parameters                         //
////////////////////////////////////////

// system reset       = 0x800000
localparam REG_SYS_RST  = 3'h0;
// minimig reset      = 0x800004
localparam REG_MIN_RST  = 3'h1;
// UART TxD           = 0x800008
localparam REG_UART_TX  = 3'h2;
// timer              = 0x80000c
localparam REG_TIMER    = 3'h3;
// SPI clock divider  = 0x800010
localparam REG_SPI_DIV  = 3'h4;
// SPI CS             = 0x800014
localparam REG_SPI_CS   = 3'h5;
// SPI_DAT            = 0x800018
localparam REG_SPI_DAT  = 3'h6;

// address width for register decoding
localparam RAW          = 3; 

// UART TxD counter value for 115200 @ 50MHz system clock
localparam TXD_CNT      = 9'd434;

// timer precounter value for 1ms @ 50MHz system clock
localparam TIMER_CNT    = 16'd50_000;

// SPI counter value for 400kHz @ 50MHz system clock (SD init clock)
localparam SPI_CNT      = 6'd63;



////////////////////////////////////////
// address register                   //
////////////////////////////////////////

reg  [RAW+2-1:0] adr_r;

always @ (posedge clk, posedge rst) begin
  if (rst)
    adr_r <= #1 {(RAW+2){1'b0}};
  else
    adr_r <= #1 adr[RAW+2-1:0];
end



////////////////////////////////////////
// UART transmit                      //
////////////////////////////////////////

// TODO maybe add TX buffer - fifo?

// TX counter
reg  [  4-1:0] tx_counter;
reg  [  9-1:0] tx_timer;
wire           tx_ready;
reg            tx_en;

always @ (posedge clk, posedge rst) begin
  if (rst)
    tx_counter <= #1 4'd0;
  else if (tx_en && tx_ready)
    tx_counter <= #1 4'd10 - 4'd1;
  else if ((|tx_counter) && (~|tx_timer))
    tx_counter <= #1 tx_counter - 4'd1;
end

// TX timer
// set for 115200 Baud
always @ (posedge clk, posedge rst) begin
  if (rst)
    tx_timer <= #1 TXD_CNT - 9'd1;
  else if (tx_en && tx_ready)
    tx_timer <= #1 TXD_CNT - 9'd1;
  else if (|tx_timer)
    tx_timer <= #1 tx_timer - 9'd1;
  else if (|tx_counter)
    tx_timer <= #1 TXD_CNT - 9'd1;
end

// TX register
// 8N1 transmit format
reg  [ 10-1:0] tx_reg;

always @ (posedge clk, posedge rst) begin
  if (rst)
    tx_reg <= #1 10'b1111111111;
  else if (tx_en && tx_ready)
    tx_reg <= #1 {1'b1, dat_w[7:0], 1'b0};
  else if (~|tx_timer)
    tx_reg <= #1 {1'b1, tx_reg[9:1]};
end

// TX ready
assign tx_ready = (~|tx_counter) && (~|tx_timer);

// UART TXD
assign uart_txd = tx_reg[0];



////////////////////////////////////////
// timer                              //
////////////////////////////////////////

reg  [ 16-1:0] timer;
reg  [ 16-1:0] pre_timer;
reg            timer_en;

// pre counter
always @ (posedge clk, posedge rst) begin
  if (rst)
    pre_timer <= #1 TIMER_CNT - 16'd1;
  else if (timer_en)
    pre_timer <= #1 TIMER_CNT - 16'd1;
  else if (~|pre_timer)
    pre_timer <= #1 TIMER_CNT - 16'd1;
  else 
    pre_timer <= #1 pre_timer - 16'd1;
end

// counter
// using pre_timer, this increases each milisecond
always @ (posedge clk, posedge rst) begin
  if (rst)
    timer <= #1 16'h0000;
  else if (timer_en)
    timer <= #1 dat_w[15:0];
  else if (~|pre_timer)
    timer <= #1 timer + 16'h1;
end



////////////////////////////////////////
// SPI                                //
////////////////////////////////////////

// this is SPI mode 3 (CPOL=1, CPHA=1)
// clock default state is HI, data are captured on clock's rising edge and data are propagated on a falling edge

reg            spi_act;
reg            spi_act_d;
reg  [  6-1:0] spi_div;
reg  [  6-1:0] spi_div_r;
reg            spi_div_en;
reg  [  4-1:0] spi_cnt;
reg  [  8-1:0] spi_dat_w;
reg            spi_dat_en;
reg  [  8-1:0] spi_dat_r;

// SPI active
always @ (posedge clk, posedge rst) begin
  if (rst)
    spi_act <= #1 1'b0;
  else if (spi_act && (~|spi_cnt) && (~|spi_div))
    spi_act <= #1 1'b0;
  else if (spi_dat_en && !spi_act_d)
    spi_act <= #1 1'b1;
end

// SPI active - last cycle
always @ (posedge clk, posedge rst) begin
  if (rst)
    spi_act_d <= #1 1'b0;
  else if (spi_act && (~|spi_cnt) && (~|spi_div))
    spi_act_d  <= #1 1'b1;
  else if (spi_act_d && (~|spi_div))
    spi_act_d  <= #1 1'b0;
end

// SPI clock divider
always @ (posedge clk, posedge rst) begin
  if (rst)
    spi_div <= #1 SPI_CNT - 6'd1;
  else if (spi_div_en)
    spi_div <= #1 dat_w[5:0];
  else if (spi_act && (~|spi_div))
    spi_div <= #1 spi_div_r;
  else if ((spi_act || spi_act_d) && ( |spi_div))
    spi_div <= #1 spi_div - 6'd1;
end

// SPI counter
always @ (posedge clk, posedge rst) begin
  if (rst)
    spi_cnt <= #1 4'b1111;
  else if (spi_act && (~|spi_div))
    spi_cnt <= #1 spi_cnt - 1;
end

// SPI clock
assign spi_clk = spi_cnt[0];

// SPI write data
always @ (posedge clk) begin
  if (spi_dat_en && !(spi_act || spi_act_d))
    spi_dat_w <= #1 dat_w[7:0];
  else if (spi_act && spi_clk && (~|spi_div) && (~(&spi_cnt)))
    spi_dat_w <= #1 {spi_dat_w[6:0], 1'b1};
end

// SPI data out
assign spi_do = spi_dat_w[7];

// SPI read data
always @ (posedge clk) begin
  if (spi_act && !spi_clk && (~|spi_div))
    spi_dat_r <= #1 {spi_dat_r[6:0], spi_di};
end



////////////////////////////////////////
// register enable                    //
////////////////////////////////////////

always @ (*) begin
  if (cs && we) begin
    case(adr[5:2])
      REG_UART_TX : tx_en       = 1'b1;
      REG_TIMER   : timer_en    = 1'b1;
      REG_SPI_DIV : spi_div_en  = 1'b1;
      REG_SPI_DAT : spi_dat_en  = 1'b1;
      default : begin
        tx_en       = 1'b0;
        timer_en    = 1'b0;
        spi_div_en  = 1'b0;
        spi_dat_en  = 1'b0;
      end
    endcase
  end else begin
    tx_en       = 1'b0;
    timer_en    = 1'b0;
    spi_div_en  = 1'b0;
    spi_dat_en  = 1'b0;
  end
end



////////////////////////////////////////
// register write                     //
////////////////////////////////////////

always @ (posedge clk, posedge rst) begin
  if (rst) begin
    sys_rst       <= #1 1'b0;
    minimig_rst   <= #1 1'b1;
    spi_div_r     <= #1 SPI_CNT - 6'd1;
    spi_cs_n      <= #1 4'b1111;
  end else if (cs && we) begin
    case(adr[4:2])
      REG_SYS_RST : sys_rst       <= #1 dat_w[    0];
      REG_MIN_RST : minimig_rst   <= #1 dat_w[    0];
      REG_SPI_DIV : spi_div_r     <= #1 dat_w[ 5: 0];
      REG_SPI_CS  : spi_cs_n      <= #1 ~((|dat_w[7:4]) ? ((dat_w[7:4] & dat_w[3:0]) | (~dat_w[7:4] & ~spi_cs_n)) : dat_w[3:0]);
    endcase
  end
end



////////////////////////////////////////
// register read                      //
////////////////////////////////////////

always @ (*) begin
  case(adr_r[4:2])
    REG_TIMER     : dat_r = {16'h0000, timer}; 
    REG_SPI_DAT   : dat_r = {24'h000000, spi_dat_r};
    default       : dat_r = 32'hxxxxxxxx;
  endcase
end



////////////////////////////////////////
// ack & err                          //
////////////////////////////////////////

// ack
always @ (*) begin
  case(adr[4:2])
    REG_UART_TX   : ack = cs && tx_ready;
    REG_SPI_DAT   : ack = cs && !(spi_act | spi_act_d);
    default       : ack = cs;
  endcase
end

// err
assign err = 1'b0;



endmodule

