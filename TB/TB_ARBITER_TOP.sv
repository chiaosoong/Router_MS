`timescale 1ns/1ps
module TB_ARBITER_TOP();
logic ACLK, ARESETn;
always #10 ACLK = ~ACLK;	// 500 MHz clock generation

logic M1_ARVALID, M0_ARVALID, S_ARVALID, S_RVALID;
logic M1_RVALID, M0_RVALID, M1_RREADY, M0_RREADY,S_RREADY;
ARBITER_TOP dut_arbiter_top(.*);
initial begin
	ACLK = 0;
	ARESETn = 0;
  M1_ARVALID = 0;
  M0_ARVALID = 0;
  S_RVALID   = 0;
  M0_RREADY  = 0;
  M1_RREADY  = 0;

	#20 ARESETn = 1;
  @(posedge ACLK);
  axi_rd_contention();
	#55;
  axi_rd_contention();
	#55;
  axi_rd_contention();
	#55;
  axi_rd_contention();
	#55;
  axi_rd_0();
	#55;
  axi_rd_1();
	#55;
  axi_rd_contention();
	$finish();
end

task axi_rd_contention();
  begin
    @(posedge ACLK);
    #2;
    M1_ARVALID = 1;
    M0_ARVALID = 1;
    @(posedge ACLK);
    #2;
    S_RVALID = 1;
    M0_RREADY  = 1;
    M1_RREADY  = 1; // read transaction done
    @(posedge ACLK);
    S_RVALID = 0;
    M1_ARVALID = 0;
    M0_ARVALID = 0;
    M0_RREADY  = 0;
    M1_RREADY  = 0;
  end
endtask

task axi_rd_0();
  begin
    @(posedge ACLK);
    #2;
    M1_ARVALID = 0;
    M0_ARVALID = 1;
    @(posedge ACLK);
    #2;
    S_RVALID = 1;
    M0_RREADY  = 1;
    M1_RREADY  = 1; // read transaction done
    @(posedge ACLK);
    S_RVALID = 0;
    M1_ARVALID = 0;
    M0_ARVALID = 0;
    M0_RREADY  = 0;
    M1_RREADY  = 0;
  end
endtask

task axi_rd_1();
  begin
    @(posedge ACLK);
    #2;
    M1_ARVALID = 1;
    M0_ARVALID = 0;
    @(posedge ACLK);
    #2;
    S_RVALID = 1;
    M0_RREADY  = 1;
    M1_RREADY  = 1; // read transaction done
    @(posedge ACLK);
    S_RVALID = 0;
    M1_ARVALID = 0;
    M0_ARVALID = 0;
    M0_RREADY  = 0;
    M1_RREADY  = 0;
  end
endtask
endmodule

