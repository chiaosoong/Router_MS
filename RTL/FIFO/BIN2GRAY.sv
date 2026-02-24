/**********************************
* Parameterized Binary to Gray Converter
**********************************/
module BIN2GRAY #(
  parameter W = 8
)(
  input  [W-1:0] B,       // input binary data

  output logic [W-1:0] G  // Gray code
);

integer i;
always_comb begin
  G[W-1] = B[W-1];
  for (i = W-2; i >= 0; i--)
    G[i] = B[i] ^ B[i+1];
end

endmodule
