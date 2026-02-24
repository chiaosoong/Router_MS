/**********************************
* Parameterized Gray to Binary Converter
**********************************/
module GRAY2BIN #(
  parameter W = 8
)(
  input  [W-1:0] G,       // Gray code input

  output logic [W-1:0] B  // binary output
);

integer i;
always_comb begin
  B[W-1] = G[W-1];
  for (i = W-2; i >= 0; i--)
    B[i] = B[i+1] ^ G[i];
end

endmodule
