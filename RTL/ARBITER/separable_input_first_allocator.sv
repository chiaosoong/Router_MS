import noc_params::*;

module separable_input_first_allocator #(
  parameter int VC_NUM = 2
)(
  input  logic clk,
  input  logic RSTn,   

  // vc_request[in_port][vc] = 1 表示该输入端口的该VC请求分配
  input  logic [PORT_NUM-1:0][VC_NUM-1:0] vc_request,

  // vc_target_port[in_port][vc] = 该VC想要去的输出端口
  input  port_t [VC_NUM-1:0] vc_target_port [PORT_NUM-1:0],

  // vc_grant_final[in_port][vc] = 最终赢得分配
  output logic [PORT_NUM-1:0][VC_NUM-1:0] vc_grant_final
);

  //----------------------------------------------------------
  // 第一阶段结果：每个输入端口选中的 VC
  //----------------------------------------------------------
  logic [PORT_NUM-1:0][VC_NUM-1:0] vc_selected_per_input;

  //----------------------------------------------------------
  // 第二阶段使用的请求矩阵：
  // output_port_request[out_port][in_port]
  //----------------------------------------------------------
  logic [PORT_NUM-1:0][PORT_NUM-1:0] output_port_request;

  //----------------------------------------------------------
  // 第二阶段结果：
  // output_port_winner[out_port][in_port]
  //----------------------------------------------------------
  logic [PORT_NUM-1:0][PORT_NUM-1:0] output_port_winner;


  //==========================================================
  // 第一阶段：
  // 每个输入端口内部，在多个VC之间做RR
  //==========================================================
  genvar in_port;
  generate
    for (in_port = 0; in_port < PORT_NUM; in_port++) begin : GEN_VC_ARBITER
      RR_ARBITER #(
        .NR(VC_NUM)
      ) vc_rr (
        .CLK (clk),
        .RSTn(RSTn),
        .REQ (vc_request[in_port]),
        .GRT (vc_selected_per_input[in_port])
      );
    end
  endgenerate

  //==========================================================
  // 第二阶段：
  // 每个输出端口在多个输入端口之间做RR
  //==========================================================
  genvar out_port;
  generate
    for (out_port = 0; out_port < PORT_NUM; out_port++) begin : GEN_PORT_ARBITER
      RR_ARBITER #(
        .NR(PORT_NUM)
      ) port_rr (
        .CLK (clk),
        .RSTn(RSTn),
        .REQ (output_port_request[out_port]),
        .GRT (output_port_winner[out_port])
      );
    end
  endgenerate

  //==========================================================
  // 组合逻辑：
  // 1) 根据第一阶段选中的VC，生成第二阶段端口请求
  // 2) 根据两级仲裁结果，生成最终VC grant
  //==========================================================
  always_comb begin
    output_port_request = '0;
    vc_grant_final      = '0;

    // -------- 第一阶段到第二阶段的映射 --------
    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int vc = 0; vc < VC_NUM; vc++) begin
        if (vc_selected_per_input[in_p][vc]) begin
          output_port_request[
            vc_target_port[in_p][vc]
          ][in_p] = 1'b1;
          break;
        end
      end
    end

    // -------- 生成最终 grant --------
    for (int out_p = 0; out_p < PORT_NUM; out_p++) begin
      for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
        if (output_port_winner[out_p][in_p]) begin
          for (int vc = 0; vc < VC_NUM; vc++) begin
            if (vc_selected_per_input[in_p][vc]) begin
              vc_grant_final[in_p][vc] = 1'b1;
              break;
            end
          end
        end
      end
    end
  end

endmodule