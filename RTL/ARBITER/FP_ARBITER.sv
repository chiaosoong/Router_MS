/**********************************
* Parameterized Fixed Priority Arbiter:
* LSB has the highest priority
**********************************/
module FP_ARBITER #(
    parameter NR = 5
) (
    input  logic [NR-1:0] REQ,
    output logic [NR-1:0] GRT
);

// GRT[i] is high only if REQ[i] is high AND 
// no request from 0 to i-1 is active
/*
logic seen_req;    // has seen request at low bits
integer i;
always_comb begin
  GRT      = '0;
  seen_req = 0;
  for(i = 0; i < NR; i++) begin
    GRT[i]   = REQ[i] && ~seen_req;
    seen_req = seen_req | REQ[i];
  end
end
*/

// Find the lowest 1: and 2's complement
// Hihg-performance adder is needed
assign GRT = REQ & (~REQ + 1'b1);

endmodule
