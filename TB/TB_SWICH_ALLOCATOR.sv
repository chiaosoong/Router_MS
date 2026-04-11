`timescale 1ns/1ps

import noc_params::*;

module TB_SWICH_ALLOCATOR;

  logic clk;
  logic RSTn;

  port_t reqSA [VC_NUM-1:0];

  logic [VC_NUM-1:0] inputGrantSA;
  logic [VC_PER_PORT-1:0] inputVCselect [PORT_NUM-1:0];
  port_t outputselect [PORT_NUM-1:0];
  logic g_in0_east_a, g_in1_east_a, g_in0_east_b, g_in1_east_b;
  logic [2:0] east_win_mask_a, east_win_mask_b, east_win_mask_c;

  SWITCH_ALLOCATOR dut (
    .clk          (clk),
    .RSTn         (RSTn),
    .reqSA        (reqSA),
    .inputGrantSA (inputGrantSA),
    .inputVCselect(inputVCselect),
    .outputselect (outputselect)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic int ivc_id(input int in_port, input int local_vc);
    ivc_id = (in_port * VC_PER_PORT) + local_vc;
  endfunction

  function automatic port_t port_from_index(input int idx);
    case (idx)
      0:       port_from_index = LOCAL;
      1:       port_from_index = NORTH;
      2:       port_from_index = SOUTH;
      3:       port_from_index = WEST;
      default: port_from_index = EAST;
    endcase
  endfunction

  function automatic bit is_onehot0(input logic [VC_PER_PORT-1:0] v);
    is_onehot0 = (v == '0) || ((v & (v - 1'b1)) == '0);
  endfunction

  task automatic clear_reqs();
    for (int i = 0; i < VC_NUM; i++) begin
      reqSA[i] = LOCAL;
    end
  endtask

  task automatic check_onehot0_inputVCselect();
    for (int p = 0; p < PORT_NUM; p++) begin
      if (!is_onehot0(inputVCselect[p])) begin
        $error("inputVCselect[%0d]=%b is not onehot0", p, inputVCselect[p]);
        $fatal;
      end
    end
  endtask

  task automatic check_max_one_grant_per_output();
    int out_cnt [PORT_NUM-1:0];
    for (int p = 0; p < PORT_NUM; p++) out_cnt[p] = 0;

    for (int ivc = 0; ivc < VC_NUM; ivc++) begin
      if (inputGrantSA[ivc]) begin
        out_cnt[int'(reqSA[ivc])]++;
      end
    end

    for (int p = 0; p < PORT_NUM; p++) begin
      if (out_cnt[p] > 1) begin
        $error("Output %0d has %0d grants in one cycle", p, out_cnt[p]);
        $fatal;
      end
    end
  endtask

  task automatic check_one_grant_total();
    int cnt;
    cnt = 0;
    for (int i = 0; i < VC_NUM; i++) begin
      if (inputGrantSA[i]) cnt++;
    end
    if (cnt != 1) begin
      $error("Expected exactly 1 total grant, got %0d", cnt);
      $fatal;
    end
  endtask

  task automatic set_input_all_vc_to_port(input int in_port, input port_t dst);
    for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
      reqSA[ivc_id(in_port, local_vc)] = dst;
    end
  endtask

  task automatic check_onehot_per_inputGrant_slice();
    logic [VC_PER_PORT-1:0] sl;
    for (int p = 0; p < PORT_NUM; p++) begin
      sl = inputGrantSA[(p*VC_PER_PORT) +: VC_PER_PORT];
      if (!is_onehot0(sl)) begin
        $error("inputGrantSA slice for input %0d is not onehot0: %b", p, sl);
        $fatal;
      end
    end
  endtask

  initial begin
    clear_reqs();
    RSTn = 1'b0;
    repeat (2) @(posedge clk);
    RSTn = 1'b1;

    // CASE0: all default LOCAL requests (current design has implicit always-valid requests)
    @(negedge clk);
    clear_reqs();
    #1;
    check_one_grant_total();
    check_onehot0_inputVCselect();
    check_onehot_per_inputGrant_slice();
    check_max_one_grant_per_output();

    // CASE1: each input requests a distinct output (all VCs of an input map to same output)
    @(negedge clk);
    clear_reqs();
    set_input_all_vc_to_port(0, NORTH);
    set_input_all_vc_to_port(1, SOUTH);
    set_input_all_vc_to_port(2, WEST);
    set_input_all_vc_to_port(3, EAST);
    set_input_all_vc_to_port(4, LOCAL);
    #1;
    // Distinct outputs => all 5 inputs should be granted (one per input)
    if ($countones(inputGrantSA) != PORT_NUM) begin
      $error("CASE1 expected %0d grants, got %0d", PORT_NUM, $countones(inputGrantSA));
      $fatal;
    end
    if (outputselect[NORTH] !== LOCAL ||
        outputselect[SOUTH] !== NORTH ||
        outputselect[WEST]  !== SOUTH ||
        outputselect[EAST]  !== WEST  ||
        outputselect[LOCAL] !== EAST) begin
      $error("CASE1 outputselect mismatch");
      $fatal;
    end
    check_onehot0_inputVCselect();
    check_onehot_per_inputGrant_slice();
    check_max_one_grant_per_output();

    // CASE2: in0 and in1 contend for EAST (all their VCs point to EAST)
    @(negedge clk);
    clear_reqs();
    set_input_all_vc_to_port(0, EAST);
    set_input_all_vc_to_port(1, EAST);
    set_input_all_vc_to_port(2, NORTH);
    set_input_all_vc_to_port(3, SOUTH);
    set_input_all_vc_to_port(4, WEST);
    #1;
    if ($countones(inputGrantSA) != 4) begin
      $error("CASE2 expected 4 total grants (EAST contested), got %0d", $countones(inputGrantSA));
      $fatal;
    end
    check_onehot0_inputVCselect();
    check_onehot_per_inputGrant_slice();
    check_max_one_grant_per_output();

    // keep same requests for one more cycle, EAST winner should rotate
    g_in0_east_a = |inputGrantSA[(0*VC_PER_PORT) +: VC_PER_PORT];
    g_in1_east_a = |inputGrantSA[(1*VC_PER_PORT) +: VC_PER_PORT];
    @(posedge clk);
    #1;
    g_in0_east_b = |inputGrantSA[(0*VC_PER_PORT) +: VC_PER_PORT];
    g_in1_east_b = |inputGrantSA[(1*VC_PER_PORT) +: VC_PER_PORT];
    if ((g_in0_east_a == g_in0_east_b) || (g_in1_east_a == g_in1_east_b)) begin
      $error("CASE2B EAST contention did not rotate between input0/input1");
      $fatal;
    end
    check_onehot0_inputVCselect();
    check_onehot_per_inputGrant_slice();
    check_max_one_grant_per_output();

    // CASE3: same input(in2) different target settings on different VCs; still only one VC selected
    @(negedge clk);
    clear_reqs();
    reqSA[ivc_id(2,0)] = NORTH;
    reqSA[ivc_id(2,1)] = SOUTH;
    reqSA[ivc_id(2,2)] = WEST;
    reqSA[ivc_id(2,3)] = EAST;
    #1;
    if (!is_onehot0(inputVCselect[2]) || inputVCselect[2] == '0) begin
      $error("CASE3 expected exactly one selected VC on input2, got %b", inputVCselect[2]);
      $fatal;
    end
    check_onehot0_inputVCselect();
    check_onehot_per_inputGrant_slice();
    check_max_one_grant_per_output();

    // CASE4: all inputs request LOCAL (heavy single-output contention)
    @(negedge clk);
    clear_reqs();
    for (int i = 0; i < VC_NUM; i++) reqSA[i] = LOCAL;
    #1;
    check_one_grant_total();
    if (outputselect[LOCAL] !== LOCAL &&
        outputselect[LOCAL] !== NORTH &&
        outputselect[LOCAL] !== SOUTH &&
        outputselect[LOCAL] !== WEST  &&
        outputselect[LOCAL] !== EAST) begin
      $error("CASE4 outputselect[LOCAL] illegal enum value");
      $fatal;
    end
    check_onehot0_inputVCselect();
    check_onehot_per_inputGrant_slice();
    check_max_one_grant_per_output();

    // CASE5: 3-way contention on EAST, observe progression over 3 cycles
    @(negedge clk);
    clear_reqs();
    set_input_all_vc_to_port(0, EAST);
    set_input_all_vc_to_port(1, EAST);
    set_input_all_vc_to_port(2, EAST);
    set_input_all_vc_to_port(3, NORTH);
    set_input_all_vc_to_port(4, SOUTH);
    #1;
    east_win_mask_a[0] = |inputGrantSA[(0*VC_PER_PORT) +: VC_PER_PORT];
    east_win_mask_a[1] = |inputGrantSA[(1*VC_PER_PORT) +: VC_PER_PORT];
    east_win_mask_a[2] = |inputGrantSA[(2*VC_PER_PORT) +: VC_PER_PORT];
    if ($countones(east_win_mask_a) != 1) begin
      $error("CASE5A expected exactly one EAST winner among inputs 0/1/2");
      $fatal;
    end
    @(posedge clk);
    #1;
    east_win_mask_b[0] = |inputGrantSA[(0*VC_PER_PORT) +: VC_PER_PORT];
    east_win_mask_b[1] = |inputGrantSA[(1*VC_PER_PORT) +: VC_PER_PORT];
    east_win_mask_b[2] = |inputGrantSA[(2*VC_PER_PORT) +: VC_PER_PORT];
    if ($countones(east_win_mask_b) != 1 || east_win_mask_b == east_win_mask_a) begin
      $error("CASE5B expected EAST winner to rotate");
      $fatal;
    end
    @(posedge clk);
    #1;
    east_win_mask_c[0] = |inputGrantSA[(0*VC_PER_PORT) +: VC_PER_PORT];
    east_win_mask_c[1] = |inputGrantSA[(1*VC_PER_PORT) +: VC_PER_PORT];
    east_win_mask_c[2] = |inputGrantSA[(2*VC_PER_PORT) +: VC_PER_PORT];
    if ($countones(east_win_mask_c) != 1 ||
        east_win_mask_c == east_win_mask_b ||
        east_win_mask_c == east_win_mask_a) begin
      $error("CASE5C expected third distinct EAST winner");
      $fatal;
    end
    check_onehot0_inputVCselect();
    check_onehot_per_inputGrant_slice();
    check_max_one_grant_per_output();

    $display("TB_SWICH_ALLOCATOR: PASS");
    $finish;
  end

endmodule
