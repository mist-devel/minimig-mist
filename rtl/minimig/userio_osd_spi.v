//SPI interface module (8 bits)
//this is a slave module, clock is controlled by host
//clock is high when bus is idle
//ingoing data is sampled at the positive clock edge
//outgoing data is shifted/changed at the negative clock edge
//msb is sent first
//         ____   _   _   _   _
//sck   ->    |_| |_| |_| |_|
//data   ->     777 666 555 444
//sample ->      ^   ^   ^   ^
//strobe is asserted at the end of every byte and signals that new data must
//be registered at the out output. At the same time, new data is read from the in input.
//The data at input in is also sent as the first byte after _scs is asserted (without strobe!). 


module userio_osd_spi
(
	input 	clk,		    //pixel clock
	input	_scs,			//SPI chip select
	input	sdi,		  	//SPI data in
	output	sdo,	 		//SPI data out
	input	sck,	  		//SPI clock
	input	[7:0] in,		//parallel input data
	output reg	[7:0] out,		//parallel output data
	output	reg rx,		//byte received
	output	reg cmd		//first byte received
);


//locals
reg [2:0] bit_cnt;		//bit counter
reg [7:0] sdi_reg;		//input shift register	(rising edge of SPI clock)
reg [7:0] sdo_reg;		//output shift register	 (falling edge of SPI clock)

reg new_byte;			//new byte (8 bits) received
reg rx_sync;			//synchronization to clk (first stage)
reg first_byte;		//first byte is going to be received

//------ SPI bit counter ------//
always @(posedge sck or posedge _scs)
	if (_scs)
		bit_cnt <= 0;                 //always clear bit counter when CS is not active
	else
		bit_cnt <= bit_cnt + 1'd1;    //increment bit counter when new bit has been received

//------ input shift register ------//
always @(posedge sck) begin
	sdi_reg <= #1 {sdi_reg[6:0],sdi};
	if (bit_cnt==7) new_byte <= ~new_byte;
end

//----- rx signal ------//
//this signal toggles just after new byte has been received
//synchronized to clk
always @(posedge clk) begin
	rx_sync <= new_byte;
	rx <= rx_sync;
	if (rx ^ rx_sync) out <= sdi_reg;
end

//------ cmd signal generation ------//
//this signal becomes active after reception of first byte
//when any other byte is received it's deactivated indicating data bytes
always @(posedge sck or posedge _scs)
	if (_scs)
		first_byte <= #1 1'b1;		//set when CS is not active
	else if (bit_cnt == 3'd7)
		first_byte <= #1 1'b0;		//cleared after reception of first byte

always @(posedge sck)
	if (bit_cnt == 3'd7)
		cmd <= #1 first_byte;		//active only when first byte received
	
//------ serial data output register ------//
always @(negedge sck)	//output change on falling SPI clock
	if (bit_cnt == 3'd0)
		sdo_reg <= #1 in;
	else
		sdo_reg <= #1 {sdo_reg[6:0],1'b0};

//------ SPI output signal ------//
assign sdo = ~_scs & sdo_reg[7];	//force zero if SPI not selected


endmodule
