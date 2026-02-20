/**********************************
* Parameterized Round Robin Arbiter
**********************************/
module RR_ARBITER #(
  parameter NR = 5,              // Number of requesters
  parameter WIDTH = $clog2(NR)   // Data width of arbiter pointer
) (
  input  logic CLK,
  input  logic RSTn,
  input  logic [NR-1:0] REQ,     // Request vector

  output logic [NR-1:0] GRT      // Grant vector
);

logic [WIDTH-1:0] ptr;           // Pointer indicating which bit has the highest priority

//---------- Masked request branch -------------//
logic [NR-1:0] req_mask;      // Mask the high priority region
assign req_mask = {NR{1'b1}} - (2**ptr - 1);
logic [NR-1:0] REQ_masked;    // Masked request vector
assign REQ_masked = req_mask & REQ;






always@(posedge CLK) begin
end

endmodule
