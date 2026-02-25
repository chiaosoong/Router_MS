import noc_params::*;

module wavefront_allocator #(
  parameter int VC_NUM = 2
)(
  input  logic clk,
  input  logic RSTn,

  // vc_request[in_port][vc] = 1 means this VC is requesting allocation
  input  logic [PORT_NUM-1:0][VC_NUM-1:0] vc_request,

  // vc_target_port[in_port][vc] = target output port of this VC
  input  port_t [VC_NUM-1:0] vc_target_port [PORT_NUM-1:0],

  // vc_grant_final[in_port][vc] = final grant result
  output logic [PORT_NUM-1:0][VC_NUM-1:0] vc_grant_final
);

  localparam int VC_PTR_W = (VC_NUM <= 1) ? 1 : $clog2(VC_NUM);

  logic [PORT_NUM-1:0][PORT_NUM-1:0] output_port_request;
  logic [PORT_NUM-1:0][PORT_NUM-1:0] output_port_winner;

  logic [PORT_SIZE-1:0] wf_start;
  logic [VC_PTR_W-1:0]  vc_start [PORT_NUM-1:0];

  logic [PORT_NUM-1:0]  in_matched;
  logic [VC_PTR_W-1:0]  selected_vc_idx [PORT_NUM-1:0];

  function automatic int unsigned add_wrap(
    input int unsigned a,
    input int unsigned b,
    input int unsigned n
  );
    int unsigned sum;
    begin
      sum = a + b;
      add_wrap = (sum >= n) ? (sum - n) : sum;
    end
  endfunction

  // Build pure wavefront request matrix:
  // output_port_request[out_port][in_port] = OR of all VC requests to this output.
  always_comb begin
    output_port_request = '0;

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int vc = 0; vc < VC_NUM; vc++) begin
        if (vc_request[in_p][vc]) begin
          output_port_request[vc_target_port[in_p][vc]][in_p] = 1'b1;
        end
      end
    end
  end

  // Single-stage wavefront matching on input-output pairs.
  always_comb begin
    logic [PORT_NUM-1:0] in_taken;
    logic [PORT_NUM-1:0] out_taken;

    output_port_winner = '0;
    in_taken           = '0;
    out_taken          = '0;

    for (int k = 0; k < PORT_NUM; k++) begin
      int unsigned out_idx;
      out_idx = add_wrap(wf_start, k, PORT_NUM);

      for (int d = 0; d < PORT_NUM; d++) begin
        int unsigned in_idx;
        in_idx = add_wrap(out_idx, d, PORT_NUM);

        if (!out_taken[out_idx] && !in_taken[in_idx] && output_port_request[out_idx][in_idx]) begin
          output_port_winner[out_idx][in_idx] = 1'b1;
          out_taken[out_idx]                  = 1'b1;
          in_taken[in_idx]                    = 1'b1;
          break;
        end
      end
    end
  end

  // For each matched input-output pair, choose one VC directly (no input-first pre-selection).
  always_comb begin
    vc_grant_final = '0;
    in_matched     = '0;
    for (int p = 0; p < PORT_NUM; p++) begin
      selected_vc_idx[p] = '0;
    end

    for (int out_p = 0; out_p < PORT_NUM; out_p++) begin
      for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
        if (output_port_winner[out_p][in_p]) begin
          for (int ofs = 0; ofs < VC_NUM; ofs++) begin
            int unsigned vc_idx;
            vc_idx = add_wrap(vc_start[in_p], ofs, VC_NUM);
            if (vc_request[in_p][vc_idx] && (vc_target_port[in_p][vc_idx] == port_t'(out_p))) begin
              vc_grant_final[in_p][vc_idx] = 1'b1;
              in_matched[in_p]             = 1'b1;
              selected_vc_idx[in_p]        = vc_idx[VC_PTR_W-1:0];
              break;
            end
          end
        end
      end
    end
  end

  // Fairness rotation for wavefront start and per-input VC pick start.
  always_ff @(posedge clk) begin
    if (!RSTn) begin
      wf_start <= '0;
      for (int p = 0; p < PORT_NUM; p++) begin
        vc_start[p] <= '0;
      end
    end
    else begin
      if (|output_port_winner) begin
        wf_start <= (wf_start == PORT_NUM-1) ? '0 : (wf_start + 1'b1);
      end

      for (int p = 0; p < PORT_NUM; p++) begin
        if (in_matched[p]) begin
          vc_start[p] <= (selected_vc_idx[p] == VC_NUM-1) ? '0 : (selected_vc_idx[p] + 1'b1);
        end
      end
    end
  end

endmodule
