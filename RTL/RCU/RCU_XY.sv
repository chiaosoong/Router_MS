/**********************************
* Routing Computation Unit
* - One instance serves one input VC front flit
* - Only header flits generate a routing request
**********************************/
module RCU_XY
import noc_params::*;
#(
  parameter POS THISX = P0,
  parameter POS THISY = P0
)(
  input  logic                  front_valid,
  input  logic                  front_is_head,
  input  logic [DATA_WIDTH-1:0] front_data,

  output logic       rc_valid,
  output port_t      rc_port,
  output msg_class_t rc_msg_class
);

  logic [3:0] dstx_raw;
  logic [3:0] dsty_raw;
  POS dstx;
  POS dsty;

  assign dstx_raw = front_data[31:28];
  assign dsty_raw = front_data[27:24];

  always_comb begin
    case (dstx_raw)
      4'd0:    dstx = P0;
      4'd1:    dstx = P1;
      4'd2:    dstx = P2;
      default: dstx = P0;
    endcase

    case (dsty_raw)
      4'd0:    dsty = P0;
      4'd1:    dsty = P1;
      4'd2:    dsty = P2;
      default: dsty = P0;
    endcase
  end

  always_comb begin
    rc_valid     = front_valid && front_is_head;
    rc_msg_class = (front_data[2:0] == RESP) ? RESP : REQ;

    // Dimension-order XY routing: resolve X first, then Y.
    if (THISX < dstx)      rc_port = EAST;
    else if (THISX > dstx) rc_port = WEST;
    else if (THISY > dsty) rc_port = SOUTH;
    else if (THISY < dsty) rc_port = NORTH;
    else                   rc_port = LOCAL;
  end

endmodule
