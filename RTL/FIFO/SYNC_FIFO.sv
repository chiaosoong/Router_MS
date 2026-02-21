/**********************************
* Synchronous FIFO
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

logic [PTR_W-1:0] wr_ptr, rd_ptr;
logic [PTR_W-1:0] wr_ptr, rd_ptr;

DP_RAM #(
	.WIDTH(WIDTH),
	.DEPTH(DEPTH),
	.ADDR_W(PTR_W)
) u0_dp_ram (
	.RSTn(RSTn),
	.WR_CLK(CLK),
	.RD_CLK(CLK),
	.WR_EN(WR_EN),
	.RD_EN(RD_EN),
	.WR_ADDR(wr_ptr),
	.RD_ADDR(rd_ptr),
	.WD_DATA(DATA_IN),
	.RD_DATA(DATA_OUT)
);

//--------------------------------------------------
// Write logic
//--------------------------------------------------

endmodule
