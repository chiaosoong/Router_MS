/**********************************
* Parameterized Gray Encoder
**********************************/
module GRAY_ENCODER #(
  parameter W = 8
)(
  input  [W-1:0] D,       // input data

  output logic [W-1:0] G  // Gray code
);

integer i;
always_comb begin
  G[W-1] = D[W-1];
  for (i = W-2; i >= 0; i--)
    G[i] = D[i] ^ D[i+1];
end

endmodule
