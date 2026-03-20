import noc_params::*;

module SU (
  input logic clk,
  input logic RSTn,
  vca_if.su vca
);

  logic [VC_NUM-1:0] ovc_state_q;

  assign vca.OVC_STATE = ovc_state_q;

  always_ff @(posedge clk) begin
    if (!RSTn) begin
      ovc_state_q <= '0;
    end
    else begin
      ovc_state_q <= ovc_state_q | vca.UPDATE;
    end
  end

endmodule