/**********************************
* Parameterized Round Robin Arbiter
* V2.0: Enable added, only update priority when EN asserted
**********************************/
module RR_ARBITER #(
  parameter NR = 5,              // Number of requesters
  parameter WIDTH = $clog2(NR)   // Data width of arbiter pointer
) (
  input  logic CLK,
  input  logic RSTn,
  input  logic EN,               // Only perfor arbitration when enabled
  input  logic [NR-1:0] REQ,     // Request vector

  output logic [NR-1:0] GRT      // Grant vector
);

logic [WIDTH-1:0] ptr;           // Pointer indicating which bit has the highest priority
logic [WIDTH-1:0] new_ptr;       // After a grant, move the pointer after the one just received the grant 
integer i;
always_comb begin
	new_ptr = ptr;
	for(i = 0; i < NR; i++) begin
		if (GRT[i])	new_ptr = (i >= NR - 1) ? 0 : i + 1;
	end
end

//--------------------------------------------------
// Masked request branch
//--------------------------------------------------
logic [NR-1:0] req_mask;      // Mask the high priority region
assign req_mask = {NR{1'b1}} - (2**ptr - 1);
logic [NR-1:0] REQ_masked;    // Masked request vector
assign REQ_masked = req_mask & REQ;
logic [NR-1:0] GRT_masked, GRT_unmasked;
FP_ARBITER #(.NR(5)) u0_fp_masked(
	.RSTn(RSTn),
	.REQ(REQ_masked),
	.GRT(GRT_masked)
);


//--------------------------------------------------
// Unmasked request branch
//--------------------------------------------------
FP_ARBITER #(.NR(5)) u1_fp_unmasked(
	.RSTn(RSTn),
	.REQ(REQ),
	.GRT(GRT_unmasked)
);

assign GRT = (REQ_masked == 0) ? GRT_unmasked : GRT_masked;

always_ff @(posedge CLK) begin
	if (!RSTn)	ptr <= {WIDTH{1'b0}};
	else if (|REQ && EN)  ptr <= new_ptr; 
end

endmodule

