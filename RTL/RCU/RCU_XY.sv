/********************************** 
* Routing Calculation Unit:
* Dimension-order routing (XY-routing)
**********************************/
module RCU_XY
import noc_params::*;
#(
  parameter POS THIS_X = P0,  // Local PE ID
  parameter POS THIS_Y = P0
)(
  input  POS    DSTX,
  input  POS    DSTY,
  output port_t PRT
);

  always_comb begin
    if (THIS_X < DSTX)      PRT = EAST;
    else if (THIS_X > DSTX) PRT = WEST;
    else if (THIS_Y > DSTY) PRT = SOUTH;
    else if (THIS_Y < DSTY) PRT = NORTH;
    else                    PRT = LOCL;
  end

endmodule
