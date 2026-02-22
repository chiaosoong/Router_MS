`timescale 1ns/1ps
module TB_GRAY();
parameter W = 16;
logic [W-1:0] D, G;
GRAY_ENCODER #(.W(W)) dut_gray_encoder (.*);
integer i;
initial begin
  for (i = 0; i <= 2**W -1; i++) begin
    D <= i; #10;
  end
  $finish();
end

endmodule
