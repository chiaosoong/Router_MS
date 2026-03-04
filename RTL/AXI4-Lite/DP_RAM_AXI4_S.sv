/*******************************************************
* Dual Port RAM with AXI4-Lite Subordinate Interface
* 1) DP RAM is implemented with DPI-C functions
* 1) AXI4-Lite protocol based on FSM
* 2) Subordinate wait for VALID before asserting READY
* NOTICE: RRESP is always OKAY
*******************************************************/
module DP_RAM_AXI4_S #(
	parameter WIDTH  = 32,            // data width, # of bits per word	
	parameter ADDR_W = 32             // address width
) (
  // Global clock and reset
  input                    ACLK, ARESETn,

  // *** AR - Read Address Channel ***
  input [ADDR_W-1:0]       S_ARADDR,
  input [2:0]              S_ARPROT,               // 3'b000: Data, 3'b100, Instruction
  input                    S_ARVALID,
  output logic             S_ARREADY,

  // *** R - Read Data Channel ***
  output logic [WIDTH-1:0] S_RDATA,
  output logic [1:0]       S_RRESP,          // 2'b00: OKAY, 2'b01: EXOKAY, 2'b10: SLVERR, 2'b11: DECERR
  output logic             S_RVALID,
  input                    S_RREADY,

  // *** AW - Write Address Channel ***
  output logic             S_AWREADY,
  input                    S_AWVALID,
  input [ADDR_W-1:0]       S_AWADDR,
  input [2:0]              S_AWPROT,              // 3'b000: Data, 3'b100, Instruction

  // *** W - Write Data Channel ***
  input [WIDTH-1:0]        S_WDATA,
  input [WIDTH/8-1:0]      S_WSTRB,
  input                    S_WVALID,
  output logic             S_WREADY,

  // *** B - Write Response Channel ***
  output logic [1:0]       S_BRESP,               // 2'b00: OKAY, 2'b01: EXOKAY, 2'b10: SLVERR, 2'b11: DECERR
  output logic             S_BVALID,
  input                    S_BREADY
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
// NOTICE: response signals are always OKAY
//--------------------------------------------------
assign S_RRESP = RESP_OKAY;
assign S_BRESP = RESP_OKAY;

//--------------------------------------------------
// State definitions: seperate read and write states
//--------------------------------------------------
typedef enum logic [1:0] {R_IDLE, R_RADDR, R_RDATA} r_state_type;
typedef enum logic [2:0] {W_IDLE, W_WADDR, W_WDATA, W_WADDR_WDATA, W_WRESP} w_state_type;
r_state_type r_current_state, r_next_state;
w_state_type w_current_state, w_next_state;

//--------------------------------------------------
// Read operation:
// 1) the subordinate waits for ARVALID to be asserted before asserting ARREADY
// 2) the subordinate must wait for ARVALID and ARREADY to be asseted before RVALID
//--------------------------------------------------
logic [2:0] arprot, reg_arprot;
logic [ADDR_W-1:0] araddr, reg_araddr;
always_ff @(posedge ACLK) begin
  if (!ARESETn) begin
    r_current_state <= R_IDLE;
    reg_arprot      <= INSTR_PROT;   // instruction
    reg_araddr      <= 'h0;          // reset to start paddr
  end else begin
    r_current_state <= r_next_state;
    reg_arprot      <= arprot;
    reg_araddr      <= araddr;
  end
end

logic mem_ren;  // mem read enable
always_comb begin
  r_next_state = r_current_state;
  araddr       = reg_araddr;
  arprot       = reg_arprot;
  mem_ren      = 1'b0;
  S_ARREADY    = 1'b0;
  S_RVALID     = 1'b0;
  case (r_current_state)
    R_IDLE: begin
      if (S_ARVALID)  r_next_state = R_RADDR;
    end
    R_RADDR: begin
      araddr    = S_ARADDR;   // latch ARADDR and ARPROT
      arprot    = S_ARPROT;
      S_ARREADY = 1'b1;       // assert ARREADY after ARVALID
      r_next_state = R_RDATA; // read address transaction is done
    end
    R_RDATA: begin
      mem_ren  = ~mem_valid_rd;        // perform mem read
      S_RVALID = mem_valid_rd;
      if (S_RREADY && S_RVALID) r_next_state = R_IDLE; // read data (R) trasaction over
    end
    default: ;
  endcase
end
// RVALID is asserted one clocl cycle after entering R_RDATA
// Because mem read is synchronous
logic mem_valid_rd;
always_ff @(posedge ACLK) begin
  if (!ARESETn) mem_valid_rd <= 1'b0;
  else  mem_valid_rd <= (r_current_state == R_RDATA) ? 1'b1 : 1'b0;
end

//--------------------------------------------------
// Write operation
// 1) the subordinate waits for AWVALID before asserting AWREADY
// 2) the subordinate waits for WVALID before asserting WREADY
// 3) the subordinate must wait for AWVALID, AWREADY, WVALID and WREADY before asserting BVALID
//--------------------------------------------------
logic [WIDTH-1:0] wdata, reg_wdata;
logic [WIDTH/8-1:0] wstrb, reg_wstrb;
logic [ADDR_W-1:0] awaddr, reg_awaddr;
logic [2:0] awprot, reg_awprot;
logic waddr_flag, wdata_flag;
logic reg_waddr_flag, reg_wdata_flag;
always_ff @(posedge ACLK) begin
  if (!ARESETn) begin
    w_current_state <= W_IDLE;
    reg_wdata       <= 'h0;
    reg_wstrb       <= 'hf;
    reg_awaddr      <= 'h0;
    reg_awprot      <= INSTR_PROT;
    reg_wdata_flag  <= 1'b0;
    reg_waddr_flag  <= 1'b0;
  end else begin
    w_current_state <= w_next_state;
    reg_wdata       <= wdata;
    reg_wstrb       <= wstrb;
    reg_awaddr      <= awaddr;
    reg_awprot      <= awprot;
    reg_wdata_flag  <= wdata_flag;
    reg_waddr_flag  <= waddr_flag;
  end
end

logic mem_wen;  // mem write enable
always_comb begin
  w_next_state = w_current_state;
  S_AWREADY    = 1'b0;
  S_WREADY     = 1'b0;
  S_BVALID     = 1'b0;
  awaddr       = reg_awaddr;
  awprot       = reg_awprot;
  wdata        = reg_wdata;
  wstrb        = reg_wstrb;
  wdata_flag   = reg_wdata_flag;
  waddr_flag   = reg_waddr_flag;
  mem_wen      = 1'b0;
  case (w_current_state)
    W_IDLE: begin
      {wdata_flag, waddr_flag} = 2'b00;
      case ({S_AWVALID,S_WVALID})
        2'b01: w_next_state = W_WDATA;
        2'b10: w_next_state = W_WADDR;
        2'b11: w_next_state = W_WADDR_WDATA;
        default: w_next_state = W_IDLE;
      endcase
    end
    W_WADDR: begin
      S_AWREADY  = 1'b1;      // assert AWREADY because AWVALID is already asserted
      awaddr     = S_AWADDR;  // latch AWADDR and AWPROT
      awprot     = S_AWPROT;
      waddr_flag = 1'b1;      // assert waddr_flag, indicating already visit W_WADDR
      if (wdata_flag)    w_next_state = W_WRESP;  // already been to W_WDATA state
      else if (S_WVALID) w_next_state = W_WDATA;
      else               w_next_state = W_WADDR;
    end
    W_WDATA: begin
      S_WREADY   = 1'b1;      // assert AWREADY because AWVALID is already asserted
      wdata      = S_WDATA;   // latch WDATA and WSTRB
      wstrb      = S_WSTRB;
      wdata_flag = 1'b1;      // assert wdata_flag, indicating already visit W_WDATA
      if (waddr_flag)     w_next_state = W_WRESP;  // already been to W_WADDR state
      else if (S_AWVALID) w_next_state = W_WADDR;
      else                w_next_state = W_WDATA;
    end
    W_WADDR_WDATA: begin
      S_AWREADY  = 1'b1;
      awaddr     = S_AWADDR;
      awprot     = S_AWPROT;
      waddr_flag = 1'b1;
      S_WREADY   = 1'b1;
      wdata      = S_WDATA;
      wstrb      = S_WSTRB;
      wdata_flag = 1'b1;
      w_next_state = W_WRESP; // Write data and addr are ready, goto response state
    end
    W_WRESP: begin
      S_BVALID = mem_valid_wr;
      mem_wen  = ~mem_valid_wr;        // perform mem write
      if (S_BREADY && S_BVALID) w_next_state = W_IDLE;  // B transaction is done
    end
    default: ;
  endcase
end
// BVALID is asserted one clocl cycle after entering W_WRESP
// Because mem write is synchronous
logic mem_valid_wr;
always_ff @(posedge ACLK) begin
  if (!ARESETn) mem_valid_wr <= 1'b0;
  else  mem_valid_wr <= (w_current_state == W_WRESP) ? 1'b1 : 1'b0;
end

//--------------------------------------------------
// RAM read operation
//--------------------------------------------------
always_ff @(posedge ACLK) begin
  if (!ARESETn)  S_RDATA <= 32'h0000_0013; // NOP = addi x0,x0,0
  else if (mem_ren) begin
    S_RDATA <= pmem_read(araddr); // read from PMEM
    mtrace_read(araddr);          // Trace mem read
  end
end

//--------------------------------------------------
// RAM write operation
//--------------------------------------------------
localparam UART_ADDR = 32'h1000_0000;
localparam RTC0_ADDR = 32'h1000_0004;
localparam RTC1_ADDR = 32'h1000_0008;
always_ff @(posedge ACLK) begin
  if (ARESETn && mem_wen) begin
    if (awaddr == UART_ADDR || awaddr == RTC0_ADDR || awaddr == RTC1_ADDR)
      set_skip_ref();
    pmem_write(awaddr, wdata, {{28{1'b0}}, wstrb});
    mtrace_write(awaddr);
  end
end

endmodule
