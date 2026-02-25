package noc_params;


  typedef enum logic [2:0] {LOCAL, NORTH, SOUTH, WEST, EAST} port_t;
  localparam int PORT_NUM  = 5;
  localparam int PORT_SIZE = (PORT_NUM <= 1) ? 1 : $clog2(PORT_NUM);

  localparam int VC_NUM    = 2;
  localparam int VC_SIZE   = (VC_NUM <= 1) ? 1 : $clog2(VC_NUM);

endpackage : noc_params
