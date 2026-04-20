/**********************************
* VC Allocation Unit
* - Allocates output VCs for header flits in Stage 1
* - Request traffic uses local OVCs 0/1, response traffic uses 2/3
* - This block is combinational; TOP owns the actual busy/credit state
**********************************/
module VAU
import noc_params::*;
#(
  parameter int CREDIT_W = 1
)(
  input  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] rc_valid,
  input  port_t      rc_port      [PORT_NUM-1:0][VC_PER_PORT-1:0],
  input  msg_class_t rc_msg_class [PORT_NUM-1:0][VC_PER_PORT-1:0],
  input  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] ovc_busy_state,
  input  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][CREDIT_W-1:0] ovc_credit,

  output logic [PORT_NUM-1:0][VC_PER_PORT-1:0] va_grant,
  output port_t va_outport [PORT_NUM-1:0][VC_PER_PORT-1:0],
  output logic [PORT_NUM-1:0][VC_PER_PORT-1:0][VC_PRT_SIZE-1:0] va_ovc
);

  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] ovc_busy_shadow;

  always_comb begin
    va_grant        = '0;
    va_ovc          = '0;
    ovc_busy_shadow = ovc_busy_state;

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        int class_base;

        va_outport[in_p][local_vc] = rc_port[in_p][local_vc];

        if (rc_valid[in_p][local_vc]) begin
          class_base = (rc_msg_class[in_p][local_vc] == RESP) ? VC_PER_CLASS : 0;

          // First-fit over the message-class VC subset.
          for (int offset = 0; offset < VC_PER_CLASS; offset++) begin
            int candidate_ovc;
            int out_p;

            candidate_ovc = class_base + offset;
            out_p         = int'(rc_port[in_p][local_vc]);

            if (~ovc_busy_shadow[out_p][candidate_ovc] &&
                (ovc_credit[out_p][candidate_ovc] != '0)) begin
              va_grant[in_p][local_vc]          = 1'b1;
              va_ovc[in_p][local_vc]            = candidate_ovc[VC_PRT_SIZE-1:0];
              ovc_busy_shadow[out_p][candidate_ovc] = 1'b1;
              break;
            end
          end
        end
      end
    end
  end

endmodule
