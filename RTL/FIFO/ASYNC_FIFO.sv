/**********************************
* TOP file for Parametrized Asynchronous FIFO
**********************************/
module ASYNC_FIFO #(
	parameter WIDTH   = 8,             // data width, # of bits per word
	parameter DEPTH   = 16,            // FIFO depth, # of words
	parameter ADDR_W  = $clog2(DEPTH), // pointer width
  parameter PTR_W   = ADDR_W + 1     // address width
)(
	input WCLK, RCLK,
	input WRSTn, RRSTn,
	input WINC, RINC,                 // write and read enable
	input [WIDTH-1:0] WDATA,          // FIFO write data

	output logic WFULL, REMPTY,       // indicates whether FIFO is full/empty
	output logic [WIDTH-1:0] RDATA    // FIFO read data
);

// wr/rd address
logic [ADDR_W-1:0] waddr, raddr;
// pointer to tell full/empty
// an extra MSB than w/raddr
logic [PTR_W-1:0] wptr, rptr;

DP_RAM #(
	.WIDTH(WIDTH),
	.DEPTH(DEPTH),
	.ADDR_W(ADDR_W)
) u0_dp_ram (
	.RSTn(WRSTn | RRSTn),
	.WR_CLK(WCLK),
	.RD_CLK(RCLK),
	.WR_EN(WINC && !WFULL),
	.RD_EN(RINC && !REMPTY),
	.WR_ADDR(waddr),
	.RD_ADDR(raddr),
	.WR_DATA(WDATA),
	.RD_DATA(RDATA)
);

FIFO_WPTR_FULL #(
	.DEPTH(DEPTH),
	.ADDR_W(ADDR_W),
  .PTR_W(PTR_W)
) u1_wptr_full(
  .WCLK(WCLK),
  .WINC(WINC),
  .WRSTn(WRSTn),
  .WQ2_RPTR(wq2_rptr),
  .WFULL(WFULL),
  .WPTR(wptr),
  .WADDR(waddr)
);

FIFO_RPTR_EMPTY #(
	.DEPTH(DEPTH),
	.ADDR_W(ADDR_W),
  .PTR_W(PTR_W)
) u2_rptr_empty(
  .RCLK(RCLK),
  .RINC(RINC),
  .RRSTn(RRSTn),
  .RQ2_WPTR(rq2_wptr),
  .REMPTY(REMPTY),
  .RPTR(rptr),
  .RADDR(raddr)
);

logic [PTR_W-1:0] wq2_rptr, rq2_wptr;
CDC_2DFF #(
  .W(PTR_W)
) u3_rptr_2dff (
  .CLK(WCLK),
  .RSTn(WRSTn),
  .CE(1'b1),
  .D(rptr),
  .Q2(wq2_rptr)
);

CDC_2DFF #(
  .W(PTR_W)
) u4_wptr_2dff (
  .CLK(RCLK),
  .RSTn(RRSTn),
  .CE(1'b1),
  .D(wptr),
  .Q2(rq2_wptr)
);

endmodule
