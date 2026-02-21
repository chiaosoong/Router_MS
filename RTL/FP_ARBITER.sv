/**********************************
* Parameterized Fixed Priority Arbiter:
* LSB has the highest priority
**********************************/
module FP_ARBITER #(
	parameter NR = 5               // Number of requesters
) (
	input 		      RSTn,
	input  logic [NR-1:0] REQ,     // Request vector
	output logic [NR-1:0] GRT      // Grant vector
);

integer i;
logic [NR-1:0] c;
assign c[0] = 1'b1;
always_comb begin
	if (~RSTn)	GRT = {NR{1'b0}};
	else begin
		for (i = 0; i < NR; i++) begin
			GRT[i] = REQ[i] & c[i];
			if (i < NR-1) c[i+1] = ~REQ[i] & c[i];
		end
	end
end

endmodule
