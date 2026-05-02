module fpga_board_top #(
  parameter int CLOCK_HZ       = 100_000_000,
  parameter int UART_BAUD      = 115200,
  parameter int CASE_MEM_DEPTH = 16384,
  parameter string CASE_MEM_FILE = "FPGA_VERIFY/mem/case_rom.memh",
  parameter int HEARTBEAT_W      = 26
) (
  input  logic        CLK_IN,
  input  logic        RESET_N_IN,
  output logic        UART_TX,
  output logic [3:0]  DBG_LED
);
  localparam int UART_CLKS_PER_BIT = (UART_BAUD <= 0) ? 1 : (CLOCK_HZ / UART_BAUD);
  logic rst_meta;
  logic rst_sync_n;
  logic [HEARTBEAT_W-1:0] heartbeat_ctr;

  fpga_verify_top #(
    .CASE_MEM_DEPTH(CASE_MEM_DEPTH),
    .CASE_MEM_FILE(CASE_MEM_FILE),
    .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT)
  ) u_fpga_verify_top (
    .CLK(CLK_IN),
    .RSTn(rst_sync_n),
    .UART_TX(UART_TX)
  );

  always_ff @(posedge CLK_IN or negedge RESET_N_IN) begin
    if (!RESET_N_IN) begin
      rst_meta   <= 1'b0;
      rst_sync_n <= 1'b0;
    end else begin
      rst_meta   <= 1'b1;
      rst_sync_n <= rst_meta;
    end
  end

  always_ff @(posedge CLK_IN or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
      heartbeat_ctr <= '0;
    end else begin
      heartbeat_ctr <= heartbeat_ctr + 1'b1;
    end
  end

  always_comb begin
    DBG_LED[0] = rst_sync_n;
    DBG_LED[1] = heartbeat_ctr[HEARTBEAT_W-1];
    DBG_LED[2] = ~UART_TX;
    DBG_LED[3] = 1'b0;
  end

endmodule
