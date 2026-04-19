/**********************************
* NoC Router Top Module
**********************************/
module TOP
import noc_params::*;
#(
  parameter POS THISX = P0,
  parameter POS THISY = P0,
  parameter int DOWNSTREAM_VC_DEPTH = FIFO_DEPTH + 2
)(
  input  logic CLK,
  input  logic RSTn,
  router_vc_flit_if.tx OFLIT[PORT_NUM],
  router_vc_flit_if.rx IFLIT[PORT_NUM]
);

  ROUTER_3STAGE_VC #(
    .THISX(THISX),
    .THISY(THISY),
    .DOWNSTREAM_VC_DEPTH(DOWNSTREAM_VC_DEPTH)
  ) u_router_3stage_vc (
    .CLK  (CLK),
    .RSTn (RSTn),
    .IFLIT(IFLIT),
    .OFLIT(OFLIT)
  );

endmodule
