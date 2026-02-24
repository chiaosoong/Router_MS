/**********************************
* Asynchronous FIFO Write Logic
**********************************/
module FIFO_WPTR_FULL #(
	parameter DEPTH   = 16,            // FIFO depth, # of words
	parameter ADDR_W  = $clog2(DEPTH), // pointer width
  parameter PTR_W   = ADDR_W + 1     // address width
)(
  input WCLK,
  input WINC,
  input WRSTn,
  input  [PTR_W-1:0] WQ2_RPTR,       // read pointer after 2-DFF synchronizer

  output logic              WFULL,   // FIFO full flag
  output logic [PTR_W-1:0]  WPTR,    // write pointer, Gray code
  output logic [ADDR_W-1:0] WADDR    // write address, binary code
);

//--------------------------------------------------
// Write pointer logic:
// Increments wr pointer when WINC is asserted
// and FIFO is not full
//--------------------------------------------------
// read and write pointer in binary
logic [PTR_W-1:0] wptr_bin;
assign WADDR = wptr_bin[ADDR_W-1:0];

always_ff @(posedge WCLK) begin
  if (~WRSTn) begin
    wptr_bin <= 0;
  end
  else if (WINC && ~WFULL) begin
    wptr_bin <= wptr_bin + 1'b1;
  end
end

//--------------------------------------------------
// Write full logic:
// When rd and wr pointers (both Gray code)
// equal except for MSB and MSB - 1, FIFO is full
//--------------------------------------------------
assign WFULL = (WPTR == {~WQ2_RPTR[PTR_W-1:PTR_W-2], WQ2_RPTR[PTR_W-3:0]});

//--------------------------------------------------
// Gray code and binary converter
//--------------------------------------------------
BIN2GRAY #(
  .W(PTR_W)
) u0_wptr_bin2gray (
  .G(WPTR), .B(wptr_bin)
);

endmodule
