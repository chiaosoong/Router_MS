module tb_fpga_board_top;
  logic CLK_IN;
  logic RESET_N_IN;
  logic UART_TX;
  logic [3:0] DBG_LED;

  logic saw_uart_start;
  logic saw_led1_toggle;
  logic led1_prev;

  fpga_board_top #(
    .CLOCK_HZ(4),
    .UART_BAUD(4),
    .CASE_MEM_DEPTH(8),
    .CASE_MEM_FILE("FPGA_VERIFY/sim/top_test_case.memh"),
    .HEARTBEAT_W(4)
  ) dut (
    .CLK_IN(CLK_IN),
    .RESET_N_IN(RESET_N_IN),
    .UART_TX(UART_TX),
    .DBG_LED(DBG_LED)
  );

  initial begin
    CLK_IN = 1'b0;
    forever #5 CLK_IN = ~CLK_IN;
  end

  initial begin
    RESET_N_IN = 1'b0;
    saw_uart_start = 1'b0;
    saw_led1_toggle = 1'b0;
    led1_prev = 1'b0;
    repeat (4) @(posedge CLK_IN);
    RESET_N_IN = 1'b1;
  end

  always @(negedge UART_TX) begin
    if (RESET_N_IN) begin
      saw_uart_start = 1'b1;
    end
  end

  always @(posedge CLK_IN) begin
    if (!RESET_N_IN) begin
      led1_prev <= 1'b0;
    end else begin
      if (DBG_LED[1] != led1_prev) begin
        saw_led1_toggle <= 1'b1;
      end
      led1_prev <= DBG_LED[1];
    end
  end

  initial begin
    repeat (8) @(posedge CLK_IN);
    if (DBG_LED[0] !== 1'b1) begin
      $error("board_top reset sync LED did not deassert");
      $fatal;
    end

    wait(dut.u_fpga_verify_top.all_done);
    wait(dut.u_fpga_verify_top.global_pass_count == 16'd1);
    repeat (64) @(posedge CLK_IN);

    if (!saw_uart_start) begin
      $error("board_top never drove UART_TX start bit");
      $fatal;
    end

    if (!saw_led1_toggle) begin
      $error("board_top heartbeat LED never toggled");
      $fatal;
    end

    if (DBG_LED[2] !== ~UART_TX) begin
      $error("board_top UART activity LED mismatch");
      $fatal;
    end

    if (dut.u_fpga_verify_top.completed_pkt_count != 16'd1) begin
      $error("unexpected completed packet count: %0d", dut.u_fpga_verify_top.completed_pkt_count);
      $fatal;
    end

    $display("tb_fpga_board_top: PASS");
    $finish;
  end

  initial begin
    repeat (200000) @(posedge CLK_IN);
    $error("timeout waiting for fpga_board_top");
    $fatal;
  end
endmodule
