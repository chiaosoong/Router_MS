/**********************************
* Parametrized synchronous FIFO:
* the design uses a counter to
* indicate whether FIFO is full/empty
**********************************/
module SYNC_FIFO #(
	parameter WIDTH  = 8,			// data width, # of bits per word
	parameter DEPTH  = 16,			// FIFO depth, # of words
	parameter PTR_W  = $clog2(DEPTH)	// pointer width
)(
	input CLK,
	input RSTn,
	input WR_EN, RD_EN,			// write and read enable
	input [WIDTH-1:0] DATA_IN,		// FIFO write data

	output FIFO_FULL, FIFO_EMPTY,		// indicates whether FIFO is full/empty
	output [WIDTH-1:0] DATA_OUT		// FIFO read data
);

// pointer to write and read address
logic [PTR_W-1:0] wr_pointer, rd_pointer;
// counter indicating # of occupied FIFO word
logic [PTR_W:0] fifo_cnt;

DP_RAM #(
	.WIDTH(WIDTH),
	.DEPTH(DEPTH),
	.ADDR_W(PTR_W)
) u0_dp_ram (
	.RSTn(RSTn),
	.WR_CLK(CLK),
	.RD_CLK(CLK),
	.WR_EN(WR_EN && ~FIFO_FULL),
	.RD_EN(RD_EN && ~FIFO_EMPTY),
	.WR_ADDR(wr_ptr),
	.RD_ADDR(rd_ptr),
	.WR_DATA(DATA_IN),
	.RD_DATA(DATA_OUT)
);

//--------------------------------------------------
// write pointer: increments when write enable and FIFO not full
//--------------------------------------------------
always_ff @(posedge CLK) begin
	if (~RSTn)	wr_pointer <= 'h0;
	else begin
		if (WR_EN && (~FIFO_FULL))
			wr_pointer <= wr_pointer + 'h1;
	end
end

//--------------------------------------------------
// read pointer: increments when read enable and FIFO not empty
//--------------------------------------------------
always_ff @(posedge CLK) begin
	if (~RSTn)	rd_pointer <= 'h0;
	else begin
		if (RD_EN && (~FIFO_EMPTY))
			rd_pointer <= rd_pointer + 'h1;
	end
end

//--------------------------------------------------
// FIFO counter: indicates FIFO empty/full
//--------------------------------------------------
always_ff @(posedge CLK) begin
	if (~RSTn)	fifo_cnt <= 'h0;
	else if (RD_EN && ~WR_EN && ~FIFO_EMPTY)	// If not empty and a read
		fifo_cnt <= fifo_cnt - 'b1;
	else if (WR_EN && ~RD_EN && ~FIFO_FULL)		// If not full and a write
		fifo_cnt <= fifo_cnt + 'h1;
end

endmodule
