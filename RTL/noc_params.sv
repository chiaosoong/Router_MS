package noc_params;

  // Processing element ID, 3*3 2D mesh
  // X, Y position: (x,y), 0~2
  typedef enum logic [1:0] {P0, P1, P2} POS;
  localparam int POS_NUM   = 3;
  localparam int POS_SIZE  = $clog2(POS_NUM);

  // Message class: response or request
  typedef enum logic [2:0] {REQ, RESP} msg_class_t;
  typedef enum logic [1:0] {
    FLIT_HEAD     = 2'b00,
    FLIT_BODY     = 2'b01,
    FLIT_TAIL     = 2'b10,
    FLIT_HEADTAIL = 2'b11     // Only one flit, acts as both head and tail
  } flit_type_t;

  typedef enum logic [2:0] {LOCAL, NORTH, SOUTH, WEST, EAST} port_t;
  localparam int PORT_NUM  = 5;
  localparam int PORT_SIZE = (PORT_NUM <= 1) ? 1 : $clog2(PORT_NUM);

  localparam int VC_NUM    = 4;
  localparam int VC_SIZE   = (VC_NUM <= 1) ? 1 : $clog2(VC_NUM);

endpackage : noc_params
