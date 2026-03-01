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

  // Find the lowest 1: and 2's complement
  assign GRT = REQ & (~(REQ - 1'b1));

endmodule
