`timescale 1ns/1ps

import noc_params::*;

module TB_separable_input_first_allocator;

  localparam int VC_NUM = 2;

  logic clk;
  logic RSTn;
  logic [PORT_NUM-1:0][VC_NUM-1:0] vc_request;
  port_t [VC_NUM-1:0] vc_target_port [PORT_NUM-1:0];
  logic [PORT_NUM-1:0][VC_NUM-1:0] vc_grant_final;

  separable_input_first_allocator #(
    .VC_NUM(VC_NUM)
  ) dut (
    .clk           (clk),
    .RSTn          (RSTn),
    .vc_request    (vc_request),
    .vc_target_port(vc_target_port),
    .vc_grant_final(vc_grant_final)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic clear_inputs();
    vc_request = '0;
    for (int p = 0; p < PORT_NUM; p++) begin
      for (int v = 0; v < VC_NUM; v++) begin
        vc_target_port[p][v] = LOCAL;
      end
    end
  endtask

  task automatic check_common_invariants(string tag);
    int cnt;

    // grant must be subset of request
    for (int p = 0; p < PORT_NUM; p++) begin
      for (int v = 0; v < VC_NUM; v++) begin
        if (vc_grant_final[p][v] && !vc_request[p][v]) begin
          $error("[%s] Illegal grant: vc_grant_final[%0d][%0d]=1 while vc_request=0", tag, p, v);
          $fatal;
        end
      end
    end

    // each input port can grant at most one VC
    for (int p = 0; p < PORT_NUM; p++) begin
      cnt = 0;
      for (int v = 0; v < VC_NUM; v++) begin
        cnt += vc_grant_final[p][v];
      end
      if (cnt > 1) begin
        $error("[%s] Input port %0d has %0d grants (must be <=1)", tag, p, cnt);
        $fatal;
      end
    end

    // each output port can be occupied by at most one granted input
    for (int op = 0; op < PORT_NUM; op++) begin
      cnt = 0;
      for (int ip = 0; ip < PORT_NUM; ip++) begin
        for (int iv = 0; iv < VC_NUM; iv++) begin
          if (vc_grant_final[ip][iv] && (vc_target_port[ip][iv] == port_t'(op))) begin
            cnt++;
          end
        end
      end
      if (cnt > 1) begin
        $error("[%s] Output port %0d serves %0d grants (must be <=1)", tag, op, cnt);
        $fatal;
      end
    end
  endtask

  initial begin
    clear_inputs();
    RSTn = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    if (vc_grant_final !== '0) begin
      $error("[RESET] vc_grant_final should be 0 during reset");
      $fatal;
    end

    RSTn = 1'b1;
    @(posedge clk);
    #1;

    // Case 1: single request should grant directly
    clear_inputs();
    vc_request[2][1]     = 1'b1;
    vc_target_port[2][1] = EAST;
    #1;
    check_common_invariants("CASE1");
    if (vc_grant_final[2][1] !== 1'b1) begin
      $error("[CASE1] Expected vc_grant_final[2][1]=1, got 0");
      $fatal;
    end

    // Case 2: same input port, two VCs request -> only one VC can pass stage1
    clear_inputs();
    vc_request[1][0]     = 1'b1;
    vc_request[1][1]     = 1'b1;
    vc_target_port[1][0] = NORTH;
    vc_target_port[1][1] = SOUTH;
    #1;
    check_common_invariants("CASE2");
    if ((vc_grant_final[1][0] + vc_grant_final[1][1]) > 1) begin
      $error("[CASE2] Input 1 granted more than one VC");
      $fatal;
    end

    // Case 3: two inputs contend for same output -> at most one winner
    clear_inputs();
    vc_request[0][0]     = 1'b1;
    vc_request[3][0]     = 1'b1;
    vc_target_port[0][0] = WEST;
    vc_target_port[3][0] = WEST;
    #1;
    check_common_invariants("CASE3");
    if ((vc_grant_final[0][0] + vc_grant_final[3][0]) > 1) begin
      $error("[CASE3] Same output got multiple grants");
      $fatal;
    end

    // Case 4: two inputs request different outputs -> both can be granted
    clear_inputs();
    vc_request[0][0]     = 1'b1;
    vc_request[4][1]     = 1'b1;
    vc_target_port[0][0] = NORTH;
    vc_target_port[4][1] = EAST;
    #1;
    check_common_invariants("CASE4");
    if (!(vc_grant_final[0][0] && vc_grant_final[4][1])) begin
      $error("[CASE4] Expected two non-conflicting grants to both pass");
      $fatal;
    end

    // Random checks: validate structural invariants under traffic
    for (int t = 0; t < 50; t++) begin
      clear_inputs();
      for (int ip = 0; ip < PORT_NUM; ip++) begin
        for (int iv = 0; iv < VC_NUM; iv++) begin
          vc_request[ip][iv] = $urandom_range(0, 1);
          vc_target_port[ip][iv] = port_t'($urandom_range(0, PORT_NUM-1));
        end
      end
      #1;
      check_common_invariants($sformatf("RAND_%0d", t));
      @(posedge clk);
    end

    $display("TB_separable_input_first_allocator: PASS");
    $finish;
  end

endmodule
