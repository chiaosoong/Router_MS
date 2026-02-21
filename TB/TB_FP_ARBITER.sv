`timescale 1ns/1ps
module TB_FP_ARBITER();
logic [5:0] REQ, GRT;
logic RSTn;
FP_ARBITER #(.NR(6)) dut_fp_arbiter(
	.RSTn(RSTn),
	.REQ(REQ),
	.GRT(GRT)
);

initial begin
	REQ <= 6'b100000;
	RSTn <= 1'b0;
	#50
	RSTn <= 1'b1;
	REQ <= 6'b110001; #10
	REQ <= 6'b111110; #10
	REQ <= 6'b100100; #10
	REQ <= 6'b111000; #10
	REQ <= 6'b110000; #10
	REQ <= 6'b100000; #10
	REQ <= 6'b100001; #10
	REQ <= 6'b101100; #10
	REQ <= 6'b111111;
end

endmodule
