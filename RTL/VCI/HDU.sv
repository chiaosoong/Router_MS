/**********************************
* Header Decode Unit: Decode head flit, output
* 1) Destination & source PE ID
* 2) Flit ID: header/body/tail/tail/headtail
* 3) Packet length
* 4) Message class: request/response packet
**********************************/
module HDU
import noc_params::*;
(
  input              IS_HEADER,
  input [32:0]       HEADER,
  output logic       HDU_ERROR,   // indicates decode error
  output POS         DSTX, DSTY,
  output POS         SRCX, SRCY,
  output logic [1:0] FLIT,
  output logic [3:0] LEN,
  output msg_class_t MSG          // Message class, req or resp
);

  // Only parse the header flit
  assign HDU_ERROR = IS_HEADER && (HEAD[15:14] != FLIT_HEAD);

  assign DSTX = HEADER[31:28];
  assign DSTX = HEADER[27:24];

  assign SRCX = HEADER[23:20];
  assign SRCY = HEADER[19:16];

  assign FLIT = HEADER[15:14];

  assign LEN  = HEADER[13:10];

  assign MSG  = HEADER[2:0];
endmodule
