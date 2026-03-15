package noc_params;
//--------------------------------------------------
// Gloal parameter
//--------------------------------------------------
  // Data width in the NoC is 32-bit
  localparam int DATA_WIDTH = 32;

//--------------------------------------------------
// NoC topology
//--------------------------------------------------
  // Processing element ID, 3*3 2D mesh
  // X, Y position: (x,y), 0~2
  typedef enum logic [1:0] {P0, P1, P2} POS;
  localparam int POS_NUM   = 3;
  localparam int POS_SIZE  = $clog2(POS_NUM);

//--------------------------------------------------
// Router port
//--------------------------------------------------
  typedef enum logic [2:0] {LOCAL, NORTH, SOUTH, WEST, EAST} port_t;
  localparam int PORT_NUM  = 5;
  localparam int PORT_SIZE = (PORT_NUM <= 1) ? 1 : $clog2(PORT_NUM);

//--------------------------------------------------
// Head flit fields parameters
//--------------------------------------------------
  // Message class: response or request
  typedef enum logic [2:0] {REQ, RESP} msg_class_t;
  typedef int CLASS_NUM = 2;  // There are only req and resp msg
  // Flit type
  typedef enum logic [1:0] {
    FLIT_HEAD     = 2'b00,
    FLIT_BODY     = 2'b01,
    FLIT_TAIL     = 2'b10,
    FLIT_HEADTAIL = 2'b11     // Only one flit, acts as both head and tail
  } flit_type_t;

//--------------------------------------------------
// VC parameters
//--------------------------------------------------
  // There are 2 VCs per message class, thus 4 VCs at each port
  localparam int VC_PER_CLASS = 2;
  typedef enum logic {VC0, VC1} vc_t;
  localparam int VC_PER_PORT  = VC_PER_CLASS * CLASS_NUM;
  localparam int VC_NUM = VC_PER_PORT * PORT_NUM;
  typedef logic [VC_NUM-1:0] vc_req;
  localparam int VC_SIZE = (VC_NUM <= 1) ? 1 : $clog2(VC_NUM);
  // FIFO depth
  localparam int FIFO_DEPTH = 4;

endpackage : noc_params
