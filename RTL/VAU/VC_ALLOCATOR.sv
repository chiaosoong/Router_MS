import noc_params::*;

module VC_ALLOCATOR (
  input logic clk,
  input logic RSTn,
  vca_if.vca vca
);


  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] request_cmd;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] grant;
  port_t [VC_PER_PORT-1:0]              vc_target_port [PORT_NUM-1:0];

  logic [VC_PER_PORT-1:0] free_mask_per_ivc     [VC_NUM-1:0];
  logic [VC_PER_PORT-1:0] selected_ovc_per_ivc  [VC_NUM-1:0];

  SEPARABLE_INPUT_FIRST_ALLOCATOR u_sif_alloc (
    .clk           (clk),
    .RSTn          (RSTn),
    .vc_request    (request_cmd),
    .vc_target_port(vc_target_port),
    .vc_grant_final(grant)
  );

  always_comb begin
    request_cmd       = '0;
    vca.SEL_OVC       = '{default: '0};
    vca.GRT_OVC       = '0;
    vca.UPDATE        = '0;
    free_mask_per_ivc = '{default: '0};
    selected_ovc_per_ivc = '{default: '0};

    for (int in_port = 0; in_port < PORT_NUM; in_port++) begin
      for (int local_ivc = 0; local_ivc < VC_PER_PORT; local_ivc++) begin
        int ivc_id;
        int out_port;
        logic out_port_valid;
        logic [VC_PER_PORT-1:0] occupied_local_mask;
        msg_class_t req_class;

        ivc_id = (in_port * VC_PER_PORT) + local_ivc;

        out_port = int'(vca.REQRPT[ivc_id]);
        out_port_valid = (out_port >= 0) && (out_port < PORT_NUM);
        if (out_port_valid) begin
          vc_target_port[in_port][local_ivc] = vca.REQRPT[ivc_id];
        end
        else begin
          vc_target_port[in_port][local_ivc] = LOCAL;
        end

        occupied_local_mask = get_occupied_local_mask(out_port, vca.OVC_STATE); //对应的输出端口上四个vc的占用情况
        free_mask_per_ivc[ivc_id] = vca.REQVC[ivc_id] & ~occupied_local_mask; //选出输出端口既空闲又被请求的vc

        if (out_port_valid && (free_mask_per_ivc[ivc_id] != '0)) begin //选择候选OVC
          req_class = get_msg_class_from_reqvc(vca.REQVC[ivc_id]);
          if (req_class == REQ) begin
            selected_ovc_per_ivc[ivc_id] = select_req_ovc_fixed(free_mask_per_ivc[ivc_id]);
          end
          else begin
            selected_ovc_per_ivc[ivc_id] = select_resp_ovc_fixed(free_mask_per_ivc[ivc_id]);
          end

          if (selected_ovc_per_ivc[ivc_id] != '0) begin
            request_cmd[in_port][local_ivc] = 1'b1;
          end
        end
      end
    end

    for (int in_port = 0; in_port < PORT_NUM; in_port++) begin
      for (int local_ivc = 0; local_ivc < VC_PER_PORT; local_ivc++) begin
        if (grant[in_port][local_ivc]) begin
          int ivc_id;
          int out_port;
          int local_ovc;

          ivc_id = (in_port * VC_PER_PORT) + local_ivc;
          out_port = int'(vc_target_port[in_port][local_ivc]);
          local_ovc = onehot_to_index(selected_ovc_per_ivc[ivc_id]);

          vca.GRT_OVC[ivc_id] = 1'b1;
          vca.SEL_OVC[ivc_id] = selected_ovc_per_ivc[ivc_id];

          if ((out_port >= 0) && (out_port < PORT_NUM) &&
              (local_ovc >= 0) && (local_ovc < VC_PER_PORT)) begin
            vca.UPDATE[(out_port * VC_PER_PORT) + local_ovc] = 1'b1;
          end
        end
      end
    end
  end

  function logic [VC_PER_PORT-1:0] get_occupied_local_mask(
    input int out_port,
    input logic [VC_NUM-1:0] ovc_state
  );
    get_occupied_local_mask = '0;
    if ((out_port >= 0) && (out_port < PORT_NUM)) begin
      for (int local_ovc = 0; local_ovc < VC_PER_PORT; local_ovc++) begin
        get_occupied_local_mask[local_ovc] = ovc_state[(out_port * VC_PER_PORT) + local_ovc];
      end
    end
  endfunction

  function msg_class_t get_msg_class_from_reqvc(input logic [VC_PER_PORT-1:0] reqvc_mask);
    if (reqvc_mask[1:0] != '0) get_msg_class_from_reqvc = REQ;
    else get_msg_class_from_reqvc = RESP;
  endfunction

  function logic [VC_PER_PORT-1:0] select_req_ovc_fixed(
    input logic [VC_PER_PORT-1:0] free_mask
  );
    select_req_ovc_fixed = '0;
    if (free_mask[0]) select_req_ovc_fixed = 4'b0001;
    else if (free_mask[1]) select_req_ovc_fixed = 4'b0010;
  endfunction

  function logic [VC_PER_PORT-1:0] select_resp_ovc_fixed(
    input logic [VC_PER_PORT-1:0] free_mask
  );
    select_resp_ovc_fixed = '0;
    if (free_mask[2]) select_resp_ovc_fixed = 4'b0100;
    else if (free_mask[3]) select_resp_ovc_fixed = 4'b1000;
  endfunction

  function int onehot_to_index(input logic [VC_PER_PORT-1:0] onehot);
    onehot_to_index = -1;
    for (int i = 0; i < VC_PER_PORT; i++) begin
      if (onehot[i]) begin
        onehot_to_index = i;
        break;
      end
    end
  endfunction

endmodule
