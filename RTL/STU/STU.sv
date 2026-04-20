/**********************************
* Switch Traversal Unit
* - Drives the output link from Stage-2 registers
* - Computes which Stage-2 entries can leave this cycle
**********************************/
module STU
import noc_params::*;
(
  input  logic [PORT_NUM-1:0] s2_valid,
  input  logic [PORT_NUM-1:0][DATA_WIDTH-1:0] s2_flit_data,
  input  logic [PORT_NUM-1:0] s2_is_head,
  input  logic [PORT_NUM-1:0] s2_is_tail,
  input  port_t s2_outport [PORT_NUM-1:0],
  input  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] s2_ovc,
  input  logic [PORT_NUM-1:0] oflit_ready,

  output logic [PORT_NUM-1:0] oflit_valid,
  output logic [PORT_NUM-1:0][DATA_WIDTH-1:0] oflit_data,
  output logic [PORT_NUM-1:0] oflit_is_head,
  output logic [PORT_NUM-1:0] oflit_is_tail,
  output logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] oflit_vc_id,

  output logic [PORT_NUM-1:0] s2_pop,
  output logic [PORT_NUM-1:0] s2_slot_available,
  output logic [PORT_NUM-1:0] output_busy
);

  always_comb begin
    oflit_valid       = '0;
    oflit_data        = '0;
    oflit_is_head     = '0;
    oflit_is_tail     = '0;
    oflit_vc_id       = '0;
    s2_pop            = '0;
    s2_slot_available = '0;
    output_busy       = '0;

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      int out_p;
      out_p = int'(s2_outport[in_p]);

      if (s2_valid[in_p]) begin
        oflit_valid[out_p]   = 1'b1;
        oflit_data[out_p]    = s2_flit_data[in_p];
        oflit_is_head[out_p] = s2_is_head[in_p];
        oflit_is_tail[out_p] = s2_is_tail[in_p];
        oflit_vc_id[out_p]   = s2_ovc[in_p];
      end
    end

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      int out_p;
      out_p = int'(s2_outport[in_p]);

      s2_pop[in_p]            = s2_valid[in_p] && oflit_ready[out_p];
      s2_slot_available[in_p] = ~s2_valid[in_p] || s2_pop[in_p];

      if (s2_valid[in_p] && ~s2_pop[in_p]) begin
        output_busy[out_p] = 1'b1;
      end
    end
  end

endmodule
