/**********************************
* NoC Router Top Module
**********************************/
module TOP
import noc_param::*;
(
  input             CLK,
  input             RSTn,
  router_flit_if.tx router_oflit [PORT_NUM],
  router_flit_if.rx router_iflit [PORT_NUM]
);
endmodule
