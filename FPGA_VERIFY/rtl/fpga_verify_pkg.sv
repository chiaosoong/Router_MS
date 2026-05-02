package fpga_verify_pkg;
  import noc_params::*;

  localparam int MAX_PKT_FLITS      = 7;
  localparam int MAX_CONCURRENT_PKT = 4;
  localparam int CASE_ID_W          = 16;
  localparam int PKT_ID_W           = 16;
  localparam int START_SLOT_W       = 16;
  localparam int TIMEOUT_W          = 16;
  localparam int RID_W              = 8;
  localparam int LATENCY_W          = 32;
  localparam int REPORT_TEXT_BYTES  = 96;
  localparam int CASE_MEM_LINE_W    = 320;

  typedef enum logic [7:0] {
    ERR_PASS            = 8'd0,
    ERR_TIMEOUT         = 8'd1,
    ERR_DST_MISMATCH    = 8'd2,
    ERR_SRC_MISMATCH    = 8'd3,
    ERR_TYPE_MISMATCH   = 8'd4,
    ERR_LEN_MISMATCH    = 8'd5,
    ERR_CLASS_MISMATCH  = 8'd6,
    ERR_SEQ_MISMATCH    = 8'd7,
    ERR_UNEXPECTED_FLIT = 8'd8,
    ERR_DUPLICATE_TAIL  = 8'd9,
    ERR_INTERNAL_OVF    = 8'd10
  } fpga_error_t;

  typedef enum logic [2:0] {
    EVT_CASE_START = 3'd0,
    EVT_PKT_INJ    = 3'd1,
    EVT_PKT_DONE   = 3'd2,
    EVT_PKT_FAIL   = 3'd3,
    EVT_CASE_DONE  = 3'd4,
    EVT_PROGRESS   = 3'd5,
    EVT_ALL_DONE   = 3'd6
  } fpga_event_t;

  typedef struct packed {
    logic [CASE_ID_W-1:0]             case_id;
    logic [PKT_ID_W-1:0]              pkt_id;
    logic [START_SLOT_W-1:0]          start_slot;
    logic [RID_W-1:0]                 src_rid;
    logic [RID_W-1:0]                 dst_rid;
    logic [2:0]                       msg_class;
    logic [VC_PRT_SIZE-1:0]           vc_id;
    logic [7:0]                       pkt_len;
    logic [TIMEOUT_W-1:0]             timeout_cycles;
    logic [MAX_PKT_FLITS*DATA_WIDTH-1:0] flits_flat;
  } pkt_desc_t;

  typedef struct packed {
    logic                             valid;
    pkt_desc_t                        desc;
    logic [LATENCY_W-1:0]             inject_cycle;
    logic [LATENCY_W-1:0]             finish_cycle;
    logic [LATENCY_W-1:0]             latency;
    logic                             pass;
    logic                             fail;
    logic [7:0]                       expected_seq;
    logic                             seen_head;
    fpga_error_t                      error_code;
  } pkt_state_t;

  typedef struct packed {
    fpga_event_t                      event_type;
    logic [CASE_ID_W-1:0]             case_id;
    logic [PKT_ID_W-1:0]              pkt_id;
    logic [RID_W-1:0]                 src_rid;
    logic [RID_W-1:0]                 dst_rid;
    logic [2:0]                       msg_class;
    logic [VC_PRT_SIZE-1:0]           vc_id;
    logic [7:0]                       pkt_len;
    logic [LATENCY_W-1:0]             latency;
    fpga_error_t                      error_code;
    logic [15:0]                      case_done;
    logic [15:0]                      case_total;
    logic [15:0]                      pkt_done;
    logic [15:0]                      pkt_total;
    logic [15:0]                      pass_count;
    logic [15:0]                      fail_count;
    logic [LATENCY_W-1:0]             latency_sum;
    logic [LATENCY_W-1:0]             latency_min;
    logic [LATENCY_W-1:0]             latency_max;
  } report_event_t;

  function automatic logic [CASE_ID_W-1:0] raw_case_id(input logic [CASE_MEM_LINE_W-1:0] raw);
    raw_case_id = raw[CASE_MEM_LINE_W-1 -: CASE_ID_W];
  endfunction

  function automatic logic raw_is_end_marker(input logic [CASE_MEM_LINE_W-1:0] raw);
    raw_is_end_marker = (&raw[CASE_MEM_LINE_W-1 -: CASE_ID_W]) &&
                        (&raw[CASE_MEM_LINE_W-CASE_ID_W-1 -: PKT_ID_W]);
  endfunction

  function automatic pkt_desc_t unpack_pkt_desc(input logic [CASE_MEM_LINE_W-1:0] raw);
    pkt_desc_t desc;

    desc = '0;
    desc.case_id        = raw[319:304];
    desc.pkt_id         = raw[303:288];
    desc.start_slot     = raw[287:272];
    desc.src_rid        = raw[271:264];
    desc.dst_rid        = raw[263:256];
    desc.msg_class      = raw[255:252];
    desc.vc_id          = raw[251:248];
    desc.pkt_len        = raw[247:240];
    desc.timeout_cycles = raw[239:224];
    desc.flits_flat     = raw[223:0];
    unpack_pkt_desc     = desc;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] get_flit(input pkt_desc_t desc, input int index);
    get_flit = desc.flits_flat[index*DATA_WIDTH +: DATA_WIDTH];
  endfunction
endpackage : fpga_verify_pkg
