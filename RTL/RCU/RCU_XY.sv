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
  input logic                     CLK,
  input logic                     IS_HEADER,
  input msg_class_t               MSG,
  input  POS                      DSTX,
  input  POS                      DSTY,
  input  logic                    OVCLOCK,
  output port_t                   REQPRT, // which port the packet wants
  output logic [VC_PER_PORT-1:0]  REQVC   // which VCs are allowable at the port
);

  port_t prt;
  always_comb begin
    if (THISX < DSTX)      prt = EAST;
    else if (THISX > DSTX) prt = WEST;
    else if (THISY > DSTY) prt = SOUTH;
    else if (THISY < DSTY) prt = NORTH;
    else                   prt = LOCAL;
  end

  port_t prt_reg;
  always_ff @(posedge CLK) begin
    if (IS_HEADER)  prt_reg <= prt;
  end

  assign REQPRT = IS_HEADER ? prt : prt_reg;
  always_comb begin
    if (IS_HEADER && (!OVCLOCK))
      REQVC = (MSG == REQ) ? 4'b0011 : 4'b1100;
    else
      REQVC = 'h0;
  end
endmodule
