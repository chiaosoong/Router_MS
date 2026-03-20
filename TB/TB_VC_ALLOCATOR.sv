`timescale 1ns/1ps

import noc_params::*;

module TB_VC_ALLOCATOR;

  logic clk;
  logic RSTn;
  vca_if vca_link();

  VC_ALLOCATOR u_vca (
    .clk (clk),
    .RSTn(RSTn),
    .vca (vca_link)
  );

  SU u_su (
    .clk (clk),
    .RSTn(RSTn),
    .vca (vca_link)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic int ovc_global_id(input int out_port, input int local_ovc);
    ovc_global_id = out_port * VC_PER_PORT + local_ovc;
  endfunction

  function automatic int onehot_to_index(input logic [VC_PER_PORT-1:0] onehot);
    onehot_to_index = -1;
    for (int i = 0; i < VC_PER_PORT; i++) begin
      if (onehot[i]) begin
        onehot_to_index = i;
        break;
      end
    end
  endfunction

  function automatic bit is_onehot0(input logic [VC_PER_PORT-1:0] x);
    is_onehot0 = (x == '0) || ((x & (x - 1'b1)) == '0);
  endfunction

  task automatic clear_rcu_inputs();
    for (int i = 0; i < VC_NUM; i++) begin
      vca_link.REQRPT[i] = LOCAL;
      vca_link.REQVC[i]  = '0;
    end
  endtask

  task automatic check_no_multi_grant_per_output();
    int out_cnt [PORT_NUM-1:0];
    for (int p = 0; p < PORT_NUM; p++) out_cnt[p] = 0;

    for (int ivc = 0; ivc < VC_NUM; ivc++) begin
      if (vca_link.GRT_OVC[ivc]) begin
        out_cnt[int'(vca_link.REQRPT[ivc])]++;
      end
    end

    for (int p = 0; p < PORT_NUM; p++) begin
      if (out_cnt[p] > 1) begin
        $error("Output port %0d has %0d grants in one cycle (expected <=1)", p, out_cnt[p]);
        $fatal;
      end
    end
  endtask

  task automatic check_grant_and_sel(
    input int ivc_id,
    input logic exp_grant,
    input logic [VC_PER_PORT-1:0] exp_sel
  );
    if (vca_link.GRT_OVC[ivc_id] !== exp_grant) begin
      $error("IVC%0d grant mismatch. exp=%0b got=%0b",
             ivc_id, exp_grant, vca_link.GRT_OVC[ivc_id]);
      $fatal;
    end
    if (exp_grant && (vca_link.SEL_OVC[ivc_id] !== exp_sel)) begin
      $error("IVC%0d sel mismatch. exp=%b got=%b",
             ivc_id, exp_sel, vca_link.SEL_OVC[ivc_id]);
      $fatal;
    end
  endtask

  task automatic check_general_invariants(input string tag);
    logic [VC_NUM-1:0] expected_update;

    expected_update = '0;

    for (int ivc = 0; ivc < VC_NUM; ivc++) begin
      if (!is_onehot0(vca_link.SEL_OVC[ivc])) begin
        $error("[%s] SEL_OVC[%0d] is not onehot0: %b", tag, ivc, vca_link.SEL_OVC[ivc]);
        $fatal;
      end

      if (!vca_link.GRT_OVC[ivc] && (vca_link.SEL_OVC[ivc] != '0)) begin
        $error("[%s] SEL_OVC[%0d] should be 0 when GRT_OVC=0", tag, ivc);
        $fatal;
      end

      if (vca_link.GRT_OVC[ivc]) begin
        if ((vca_link.SEL_OVC[ivc] & ~vca_link.REQVC[ivc]) != '0) begin
          $error("[%s] SEL_OVC[%0d] selects non-requested VC. SEL=%b REQVC=%b",
                 tag, ivc, vca_link.SEL_OVC[ivc], vca_link.REQVC[ivc]);
          $fatal;
        end

        expected_update[ovc_global_id(int'(vca_link.REQRPT[ivc]), onehot_to_index(vca_link.SEL_OVC[ivc]))] = 1'b1;
      end
    end

    if (vca_link.UPDATE !== expected_update) begin
      $error("[%s] UPDATE mismatch. exp=%b got=%b", tag, expected_update, vca_link.UPDATE);
      $fatal;
    end

    check_no_multi_grant_per_output();
  endtask

  initial begin
    clear_rcu_inputs();
    RSTn = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    if (vca_link.OVC_STATE !== '0) begin
      $error("[RESET] OVC_STATE must be all 0");
      $fatal;
    end

    RSTn = 1'b1;
    @(posedge clk);
    #1;

    // CASE1: REQ IVC0 -> NORTH, first allocation picks local OVC0.
    clear_rcu_inputs();
    vca_link.REQRPT[0] = NORTH;
    vca_link.REQVC[0]  = 4'b0011;
    #1;
    check_grant_and_sel(0, 1'b1, 4'b0001);
    if (vca_link.UPDATE[ovc_global_id(NORTH, 0)] !== 1'b1) begin
      $error("[CASE1] UPDATE for NORTH/OVC0 not asserted");
      $fatal;
    end
    check_general_invariants("CASE1");
    @(posedge clk);
    #1;
    if (vca_link.OVC_STATE[ovc_global_id(NORTH, 0)] !== 1'b1) begin
      $error("[CASE1] SU did not latch OVC_STATE for NORTH/OVC0");
      $fatal;
    end

    // CASE2: Another REQ to NORTH should pick local OVC1.
    clear_rcu_inputs();
    vca_link.REQRPT[4] = NORTH; // in_port1 local_ivc0
    vca_link.REQVC[4]  = 4'b0011;
    #1;
    check_grant_and_sel(4, 1'b1, 4'b0010);
    if (vca_link.UPDATE[ovc_global_id(NORTH, 1)] !== 1'b1) begin
      $error("[CASE2] UPDATE for NORTH/OVC1 not asserted");
      $fatal;
    end
    check_general_invariants("CASE2");
    @(posedge clk);
    #1;
    if (vca_link.OVC_STATE[ovc_global_id(NORTH, 1)] !== 1'b1) begin
      $error("[CASE2] SU did not latch OVC_STATE for NORTH/OVC1");
      $fatal;
    end

    // CASE3: REQ class on NORTH is full now -> no grant.
    clear_rcu_inputs();
    vca_link.REQRPT[8] = NORTH;
    vca_link.REQVC[8]  = 4'b0011;
    #1;
    check_grant_and_sel(8, 1'b0, '0);
    if (vca_link.UPDATE !== '0) begin
      $error("[CASE3] UPDATE must be 0 when no allocation");
      $fatal;
    end
    check_general_invariants("CASE3");

    // CASE4: RESP on NORTH still has free OVC2/3, should allocate OVC2.
    clear_rcu_inputs();
    vca_link.REQRPT[9] = NORTH;
    vca_link.REQVC[9]  = 4'b1100;
    #1;
    check_grant_and_sel(9, 1'b1, 4'b0100);
    if (vca_link.UPDATE[ovc_global_id(NORTH, 2)] !== 1'b1) begin
      $error("[CASE4] UPDATE for NORTH/OVC2 not asserted");
      $fatal;
    end
    check_general_invariants("CASE4");

    // CASE5: multi-input contention to same output, grant count must be <=1.
    clear_rcu_inputs();
    vca_link.REQRPT[1] = SOUTH;
    vca_link.REQVC[1]  = 4'b0011;
    vca_link.REQRPT[5] = SOUTH;
    vca_link.REQVC[5]  = 4'b0011;
    vca_link.REQRPT[10] = SOUTH;
    vca_link.REQVC[10]  = 4'b1100;
    #1;
    check_general_invariants("CASE5");

    // CASE6: same input port (port2) with two local IVC requests, only one can pass stage1.
    clear_rcu_inputs();
    vca_link.REQRPT[8] = EAST;  // in_port2 local0
    vca_link.REQVC[8]  = 4'b0011;
    vca_link.REQRPT[9] = WEST;  // in_port2 local1
    vca_link.REQVC[9]  = 4'b1100;
    #1;
    if ((vca_link.GRT_OVC[8] + vca_link.GRT_OVC[9]) > 1) begin
      $error("[CASE6] same input port got >1 grants");
      $fatal;
    end
    check_general_invariants("CASE6");

    // RANDOM STRESS: random requests + class masks, check invariants each cycle.
    for (int t = 0; t < 30; t++) begin
      clear_rcu_inputs();
      for (int ivc = 0; ivc < VC_NUM; ivc++) begin
        vca_link.REQRPT[ivc] = port_t'($urandom_range(0, PORT_NUM-1));
        case ($urandom_range(0, 3))
          0: vca_link.REQVC[ivc] = 4'b0000;
          1: vca_link.REQVC[ivc] = 4'b0011;
          2: vca_link.REQVC[ivc] = 4'b1100;
          default: vca_link.REQVC[ivc] = 4'b0000;
        endcase
      end
      #1;
      check_general_invariants($sformatf("RAND_%0d", t));
      @(posedge clk);
    end

    $display("TB_VC_ALLOCATOR: PASS");
    $finish;
  end

endmodule
