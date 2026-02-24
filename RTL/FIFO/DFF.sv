/**********************************
* Parameterized D Flip-Flop:
* With asynchronous active low reset & enable
**********************************/
module DFF #(
  parameter W = 8
)(
  input CLK,
  input CE,
  input RSTn,
  input  [W-1:0] D,        // input data

  output logic [W-1:0] Q   // delayed output
);

always_ff @(posedge CLK) begin
  if (~RSTn)    Q <= 'h0;
  else if (CE)  Q <= D;
end

endmodule
