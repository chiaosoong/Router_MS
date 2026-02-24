/**********************************
* Asynchronous FIFO Read Logic
**********************************/
module FIFO_RPTR_EMPTY #(
	parameter DEPTH   = 16,            // FIFO depth, # of words
	parameter ADDR_W  = $clog2(DEPTH), // pointer width
  parameter PTR_W   = ADDR_W + 1     // address width
)(
  input RCLK,
  input RINC,
  input RRSTn,
  input  [PTR_W-1:0] RQ2_WPTR,       // write pointer after 2-DFF synchronizer

  output logic              REMPTY,  // FIFO empty flag
  output logic [PTR_W-1:0]  RPTR,    // read pointer, Gray code
  output logic [ADDR_W-1:0] RADDR    // read address, binary code
);

//--------------------------------------------------
// Read pointer logic:
// Increments rd pointer when RINC is asserted
// and FIFO is not empty
//--------------------------------------------------
// read and write pointer in binary
logic [PTR_W-1:0] rptr_bin;
assign RADDR = rptr_bin[ADDR_W-1:0];

always_ff @(posedge RCLK) begin
  if (~RRSTn) begin
    rptr_bin <= 0;
  end
  else if (RINC && !REMPTY) begin
    rptr_bin <= rptr_bin + 1'b1;
  end
end

//--------------------------------------------------
// Read empty logic:
// When rd and wr pointers equal bitwise, FIFO is empty
//--------------------------------------------------
assign REMPTY = (RPTR[PTR_W-1:0] == RQ2_WPTR[PTR_W-1:0]);

//--------------------------------------------------
// Gray code and binary converter
//--------------------------------------------------
BIN2GRAY #(
  .W(PTR_W)
) u0_rptr_bin2gray (
  .G(RPTR), .B(rptr_bin)
);

endmodule
