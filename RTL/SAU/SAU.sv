/**********************************
* Switch Allocation Unit
* - Builds Stage-2 switch requests from Stage-1 pipeline registers
* - Reuses the existing separable input-first allocator
**********************************/
module SAU
import noc_params::*;
(
  input  logic CLK,
  input  logic RSTn,

  input  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] s1_valid,
  input  port_t s1_outport [PORT_NUM-1:0][VC_PER_PORT-1:0],
  input  logic [PORT_NUM-1:0] s2_slot_available,
  input  logic [PORT_NUM-1:0] output_busy,

  output logic [PORT_NUM-1:0][VC_PER_PORT-1:0] sa_request,
  output logic [PORT_NUM-1:0][VC_PER_PORT-1:0] sa_grant
);

  port_t [VC_PER_PORT-1:0] target_port [PORT_NUM-1:0];

  always_comb begin
    sa_request = '0;

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        target_port[in_p][local_vc] = s1_outport[in_p][local_vc];

        // A Stage-1 request can participate in SA only when:
        // 1) it is valid,
        // 2) the per-input Stage-2 register can accept a new flit, and
        // 3) the targeted output is not already blocked by a stalled Stage-3 flit.
        if (s1_valid[in_p][local_vc] &&
            s2_slot_available[in_p] &&
            ~output_busy[int'(s1_outport[in_p][local_vc])]) begin
          sa_request[in_p][local_vc] = 1'b1;
        end
      end
    end
  end

  SEPARABLE_INPUT_FIRST_ALLOCATOR #(
    .VC_PER_PORT(VC_PER_PORT)
  ) u_switch_allocator (
    .clk           (CLK),
    .RSTn          (RSTn),
    .vc_request    (sa_request),
    .vc_target_port(target_port),
    .vc_grant_final(sa_grant)
  );

endmodule
