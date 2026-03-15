/**********************************
* Input Virtual Channel Unit
* 1) There are VC_NUM VCs per port and PORT_NUM ports
* 2) Input Buffers are async FIFOs
**********************************/
module IVC
import noc_params::*;
(
  input                         VA_GRT_READY,
  input                         WCLK, RCLK,
  input                         WRSTn, RRSTn,
  output logic                  VALID,
  output logic [DATA_WIDTH-1:0] FLIT_DATA
);

  ASYNC_FIFO #(
    .WIDTH  (DATA_WIDTH),
	  .DEPTH  (FIFODEPTH)
  )(
	  .WCLK   (WCLK),
    .RCLK   (RCLK),
	WRSTn, RRSTn,
	WINC, RINC,     // write and read enable
	      WDATA,          // FIFO write data

	WFULL, REMPTY,  // indicates whether FIFO is full/empty
	RDATA           // FIFO read data
);
endmodule
