/**********************************
* AXI4-Lite Manager Interface
**********************************/
module AXI4_LITE_M #(
	parameter WIDTH  = 32,            // data width, # of bits per word	
	parameter ADDR_W = 32             // address width
) (
  // *** Data and address from manager agent **
  input               M_IRREQ, M_IAWREQ, M_IWREQ,     // read and write request
  input [ADDR_W-1:0]  M_IARADDR, M_IAWADDR,
  input [WIDTH-1:0]   M_IWDATA,
  input [WIDTH/8-1:0] M_IWSTRB,
  input [2:0]         M_IARPROT, M_IAWPROT,
  output logic [WIDTH-1:0] M_ORDATA,
  output logic             M_ORERROR,
  output logic             M_OWERROR,

  // *** Global clock and reset ***
  input ACLK, ARESETn,

  // *** AR - Read Address Channel ***
  input        M_ARREADY,
  output logic M_ARVALID,
  output logic [ADDR_W-1:0] M_ARADDR,
  output logic [2:0]        M_ARPROT, // 3'b000: Data, 3'b100, Instruction

  // *** R - Read Data Channel ***
  input [WIDTH-1:0] M_RDATA,
  input [1:0]       M_RRESP,          // 2'b00: OKAY, 2'b01: EXOKAY, 2'b10: SLERR, 2'b11: DECERR
  input             M_RVALID,
  output logic      M_RREADY,

  // *** AW - Write Address Channel ***
  input        M_AWREADY,
  output logic M_AWVALID,
  output logic [ADDR_W-1:0] M_AWADDR,
  output logic [2:0]        M_AWPROT, // 3'b000: Data, 3'b100, Instruction

  // *** W - Write Data Channel ***
  input        M_WREADY,
  output logic M_WVALID,
  output logic [WIDTH-1:0]   M_WDATA,
  output logic [WIDTH/8-1:0] M_WSTRB,

  // *** B - Write Response Channel ***
  input [1:0]  M_BRESP,               // 2'b00: OKAY, 2'b01: EXOKAY, 2'b10: SLERR, 2'b11: DECERR
  input        M_BVALID,
  output logic M_BREADY
);
//--------------------------------------------------
// Parameters: response and protection types
//--------------------------------------------------
localparam RESP_OKAY   = 2'b00;
/* verilator lint_off UNUSEDPARAM */
localparam RESP_EXOKAY = 2'b01;
localparam RESP_SLVERR = 2'b10;
localparam RESP_DECERR = 2'b11;

localparam DATA_PROT  = 3'b000;
/* verilator lint_on UNUSEDPARAM */
localparam INSTR_PROT = 3'b100;

//--------------------------------------------------
// State definitions: seperate states for every channel
//--------------------------------------------------
typedef enum logic [1:0] {R_IDLE, R_RADDR, R_RDATA} r_state_type;
typedef enum logic {W_IDLE, W_WDATA} w_state_type;
typedef enum logic {AW_IDLE, AW_WADDR} aw_state_type;
typedef enum logic {B_IDLE, B_RESP} b_state_type;
r_state_type r_current_state, r_next_state;
w_state_type w_current_state, w_next_state;
aw_state_type aw_current_state, aw_next_state;
b_state_type b_current_state, b_next_state;


//--------------------------------------------------
// Read Operation, R and AR channel combined
// 1) the master must not wait for ARREADY to be asserted before asserting ARVALID
// 2) the master waits for RVALID to be asseted before asserting RREADY
//--------------------------------------------------
logic [ADDR_W-1:0] araddr, reg_araddr;
logic [2:0] arprot, reg_arprot;
logic [WIDTH-1:0] rdata, reg_rdata;
logic [1:0] rresp, reg_rresp;
assign M_ORDATA = rdata;
assign M_ARADDR = araddr;
assign M_ARPROT = arprot;
assign M_ORERROR = (rresp == RESP_OKAY) ? 1'b0 : 1'b1;

always_ff @(posedge ACLK) begin
  if (!ARESETn) begin
    r_current_state <= R_IDLE;
    reg_araddr      <= 'h0;
    reg_arprot      <= INSTR_PROT;
    reg_rdata       <= 'h0;
    reg_rresp       <= RESP_OKAY;
  end else begin
    r_current_state <= r_next_state;
    reg_araddr      <= araddr;
    reg_arprot      <= arprot;
    reg_rdata       <= rdata;
    reg_rresp       <= rresp;
  end
end

always_comb begin
  r_next_state = r_current_state;
  araddr       = reg_araddr;
  arprot       = reg_arprot;
  rdata        = reg_rdata;
  rresp        = reg_rresp;
  M_ARVALID    = 1'b0;
  M_RREADY     = 1'b0;
  case (r_current_state)
    R_IDLE: begin
      if (M_IRREQ)  r_next_state = R_RADDR;
    end
    R_RADDR: begin
      M_ARVALID = 1'b1;         // assert ARVALID
      araddr    = M_IARADDR;    // latch and output ARADDR and ARPROT
      arprot    = M_IARPROT;
      if (M_ARREADY)            // read addr transaction is done
        r_next_state = R_RDATA;
    end
    R_RDATA: begin
      if (M_RVALID) begin
        M_RREADY = 1'b1;        // assert RREADY after RVALID
        rresp    = M_RRESP;     // latch RRESP and RDATA
        rdata    = M_RDATA;
        r_next_state = R_IDLE;  // read data transaction is done
      end
    end
    default: ;
  endcase
end

//--------------------------------------------------
// AW Channel, write address:
// Manager must not wait for AWREADY before asserting AWVALID
//--------------------------------------------------
logic [ADDR_W-1:0] awaddr, reg_awaddr;
assign M_AWADDR = awaddr;
logic [2:0] awprot, reg_awprot;
assign M_AWPROT = awprot;
always_ff @(posedge ACLK) begin
  if (!ARESETn) begin
    aw_current_state <= AW_IDLE;
    reg_awaddr       <= 'h0;
    reg_awprot       <= INSTR_PROT;
  end else begin
    aw_current_state <= aw_next_state;
    reg_awaddr       <= awaddr;
    reg_awprot       <= awprot;
  end
end
always_comb begin
  aw_next_state = aw_current_state;
  awaddr        = reg_awaddr;
  awprot        = reg_awprot;
  M_AWVALID     = 1'b0;
  case(aw_current_state)
    AW_IDLE: begin
      if (M_IAWREQ) aw_next_state = AW_WADDR;
    end
    AW_WADDR: begin
      M_AWVALID = 1'b1;       // assert AWVALID and keep it until AWREADY
      awaddr    = M_IAWADDR;  // output valid AWADDR and AWPROT
      awprot    = M_IAWPROT;
      if (M_AWREADY)  aw_next_state = AW_IDLE;  // AW transaction done
    end
  endcase
end

//--------------------------------------------------
// W Channel, write data:
// Manager must not wait for WREADY before asserting WVALID
//--------------------------------------------------
logic [WIDTH-1:0] wdata, reg_wdata;
assign M_WDATA = wdata;
logic [WIDTH/8-1:0] wstrb, reg_wstrb;
assign M_WSTRB = wstrb;
always_ff @(posedge ACLK) begin
  if (!ARESETn) begin
    w_current_state <= W_IDLE;
    reg_wdata       <= 'h0;
    reg_wstrb       <= 'hf;
  end else begin
    w_current_state <= w_next_state;
    reg_wdata       <= wdata;
    reg_wstrb       <= wstrb;
  end
end
always_comb begin
  w_next_state = w_current_state;
  wdata        = reg_wdata;
  wstrb        = reg_wstrb;
  M_WVALID     = 1'b0;
  case(w_current_state)
    W_IDLE: begin
      if (M_IWREQ) w_next_state = W_WDATA;
    end
    W_WDATA: begin
      M_WVALID = 1'b1;       // assert WVALID anb keep it until WREADY
      wdata    = M_IWDATA;   // output valid WDATA and WSTRB
      wstrb    = M_IWSTRB;
      if (M_WREADY)  w_next_state = W_IDLE;  // W transaction done
    end
  endcase
end

//--------------------------------------------------
// B Channel, write response:
// Manager waits for BVALID before asserting BREADY
//--------------------------------------------------
logic [1:0] wresp, reg_wresp;
assign M_OWERROR = (wresp == RESP_OKAY) ? 1'b0 : 1'b1;
always_ff @(posedge ACLK) begin
  if (!ARESETn) begin
    b_current_state <= B_IDLE;
    reg_wresp       <= RESP_OKAY;
  end else begin
    b_current_state <= b_next_state;
    reg_wresp       <= wresp;
  end
end
always_comb begin
  b_next_state = b_current_state;
  wresp        = reg_wresp;
  M_BREADY     = 1'b0;
  case(b_current_state)
    B_IDLE: begin
      if (M_BVALID) b_next_state = B_RESP;
    end
    B_RESP: begin
      M_BREADY = 1'b1;
      wresp    = M_BRESP;
      b_next_state = B_IDLE;  // B channel transaction done
    end
  endcase
end

endmodule
