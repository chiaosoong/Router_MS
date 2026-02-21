`timescale 1ns/1ps
module TB_RR_ARBITER();
logic CLK, RSTn;
always #10 CLK = ~CLK;	// 500 MHz clock generation

logic [4:0] REQ, GRT;
RR_ARBITER #(.NR(5)) dut_rr_arbiter(
	.CLK(CLK),
	.RSTn(RSTn),
	.REQ(REQ),
	.GRT(GRT)
);

initial begin
	REQ <= 5'b10000;
	CLK = 0;
	RSTn = 0;

	#20 RSTn = 1;

	#50
	REQ <= 5'b10001; #20
	REQ <= 5'b00001; #20
	REQ <= 5'b00010; #20
	REQ <= 5'b11100; #20
	REQ <= 5'b01000; #20
	REQ <= 5'b10000; #20

	REQ <= 5'b01111; #20
	REQ <= 5'b10111; #20
	REQ <= 5'b11011; #20
	REQ <= 5'b11101; #20
	REQ <= 5'b11110; #20
	REQ <= 5'b11111;
end

endmodule
