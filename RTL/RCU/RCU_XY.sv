/**********************************
* Routing Calculation Unit: Dimension-order routing (XY-routing)
* Computes: 1) output port; 2) candidate output VC
**********************************/
module RCU_XY
import noc_params::*;
#(
  parameter POS THISX = P0,  // Local PE ID
  parameter POS THISY = P0
)(
  input logic       CLK,
  input logic       IS_HEADER,
  input msg_class_t MSG,
  input  POS        DSTX,
  input  POS        DSTY,
  output port_t     PRT,
  output vc_req     CandidateOVC
);

  port_t prt;
  always_comb begin
    if (THISX < DSTX)      prt = EAST;
    else if (THISX > DSTX) prt = WEST;
    else if (THISY > DSTY) prt = SOUTH;
    else if (THISY < DSTY) prt = NORTH;
    else                   prt = LOCL;
  end

  port_t prt_reg;
  always_ff @(posedge CLK) begin
    if (IS_HEADER)  prt_reg <= prt;
  end

  assign PRT = IS_HEADER ? prt : prt_reg;
endmodule
