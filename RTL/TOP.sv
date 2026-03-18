/**********************************
* NoC Router Top Module
**********************************/
module TOP
import noc_param::*;
(
  input             CLK,
  input             RSTn,
  router_flit_if.tx OFLIT[PORT_NUM],
  router_flit_if.rx IFLIT[PORT_NUM]
);
endmodule
