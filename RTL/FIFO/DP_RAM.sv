/**********************************
* Parameterized Dual Port RAM
**********************************/
module DP_RAM #(
	//parameter DLY    = 1,			// clock to output delay
	parameter WIDTH  = 8,			// data width, # of bits per word	
	parameter DEPTH  = 16,			// RAM depth, # of words
	parameter ADDR_W = $clog2(DEPTH)	// address width
)(
	input RSTn,
	input WR_CLK, RD_CLK, 			// write and read clock
	input WR_EN, RD_EN,			// write and read enable
	input [ADDR_W-1:0] WR_ADDR, RD_ADDR,	// write and read address	
	input [WIDTH-1:0]  WR_DATA,		// wrtie data

	output logic [WIDTH-1:0] RD_DATA	// read data
);

logic [WIDTH-1:0] ram_model [0:DEPTH-1];

//--------------------------------------------------
// Write logic
//--------------------------------------------------
integer i;
always_ff @(posedge WR_CLK) begin
	if (~RSTn) begin
		for (i = 0; i < DEPTH; i++) begin
			ram_model[i] <= 'h0;
		end
	end else if (WR_EN)	ram_model[WR_ADDR] <= WR_DATA;
end

//--------------------------------------------------
// Read logic
//--------------------------------------------------
always_ff @(posedge RD_CLK) begin
	if (RD_EN)	RD_DATA <= ram_model[RD_ADDR];
end

endmodule
