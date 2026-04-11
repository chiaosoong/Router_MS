import noc_params::*;

module SWITCH_ALLOCATOR (
  input  logic clk,
  input  logic RSTn,

  // Requested output port per global input VC.目标端口
  input  port_t reqSA [VC_NUM-1:0],
 // 发出有效请求
  //input  logic [VC_NUM-1:0] reqSA_valid, 

  // Grant result per global input VC.
  output logic [VC_NUM-1:0] inputGrantSA,

  // Selected local VC per input port (one-hot).
  output logic [VC_PER_PORT-1:0] inputVCselect [PORT_NUM-1:0],

  // Selected input port per output port.
  output port_t outputselect [PORT_NUM-1:0]
);

  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] request_cmd;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] grant;
  port_t [VC_PER_PORT-1:0] vc_target_port [PORT_NUM-1:0];

  SEPARABLE_INPUT_FIRST_ALLOCATOR #(
    .VC_PER_PORT(VC_PER_PORT)
  ) u_sif_alloc (
    .clk           (clk),
    .RSTn          (RSTn),
    .vc_request    (request_cmd),
    .vc_target_port(vc_target_port),
    .vc_grant_final(grant)
  );

  function port_t port_from_index(input int idx);
    case (idx)
      0:       port_from_index = LOCAL;
      1:       port_from_index = NORTH;
      2:       port_from_index = SOUTH;
      3:       port_from_index = WEST;
      default: port_from_index = EAST;
    endcase
  endfunction

  always_comb begin
    request_cmd   = '0;
    inputGrantSA  = '0;
    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      inputVCselect[in_p] = '0;
    end

    for (int out_p = 0; out_p < PORT_NUM; out_p++) begin
      outputselect[out_p] = LOCAL;
    end

    // Build SIF inputs from flat reqSA.
    for (int in_port = 0; in_port < PORT_NUM; in_port++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        int ivc_id;
        ivc_id = (in_port * VC_PER_PORT) + local_vc;

        request_cmd[in_port][local_vc]   = 1'b1;
        //request_cmd[in_port][local_vc]    = reqSA_valid[ivc_id];
        vc_target_port[in_port][local_vc] = reqSA[ivc_id];
      end
    end

    // Flatten grants and generate selections.
    for (int in_port = 0; in_port < PORT_NUM; in_port++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        int ivc_id;
        ivc_id = (in_port * VC_PER_PORT) + local_vc;

        inputGrantSA[ivc_id] = grant[in_port][local_vc];
        if (grant[in_port][local_vc]) begin
          inputVCselect[in_port][local_vc] = 1'b1;
          outputselect[reqSA[ivc_id]] = port_from_index(in_port);
        end
      end
    end
  end

endmodule

