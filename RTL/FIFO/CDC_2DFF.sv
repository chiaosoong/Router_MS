/**********************************
* Parameterized 2 D Flip-Flops CDC Unit:
* Most suitable for low to high CDC
**********************************/
module CDC_2DFF #(
  parameter W = 8
)(
  input CLK,
  input CE,
  input RSTn,
  input  [W-1:0] D,        // input data

  output logic [W-1:0] Q2  // delayed output
);

logic [W-1:0] Q1;
DFF #(.W(W)) u0_cdc_2dff (
  .CLK(CLK),
  .RSTn(RSTn),
  .CE(CE),
  .D(D),
  .Q(Q1)
);
DFF #(.W(W)) u1_cdc_2dff (
  .CLK(CLK),
  .RSTn(RSTn),
  .CE(CE),
  .D(Q1),
  .Q(Q2)
);
endmodule
