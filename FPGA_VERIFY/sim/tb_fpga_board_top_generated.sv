module tb_fpga_board_top_generated;
  logic CLK_IN;
  logic RESET_N_IN;
  logic UART_TX;
  logic [3:0] DBG_LED;

  logic saw_uart_start;
  logic saw_led1_toggle;
  logic led1_prev;
  int exp_cases;
  int exp_packets;

  fpga_board_top #(
    .CLOCK_HZ(4),
    .UART_BAUD(4),
    .CASE_MEM_DEPTH(16384),
    .CASE_MEM_FILE("FPGA_VERIFY/mem/case_rom.memh"),
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
    repeat (12) @(posedge CLK_IN);

    if (DBG_LED[0] !== 1'b1) begin
      $error("board_top reset sync LED did not deassert");
      $fatal;
    end

    exp_cases   = dut.u_fpga_verify_top.case_total;
    exp_packets = dut.u_fpga_verify_top.pkt_total;

    wait((dut.u_fpga_verify_top.completed_pkt_count == exp_packets[15:0]) &&
         dut.u_fpga_verify_top.all_done);
    wait(dut.u_fpga_verify_top.global_pass_count == exp_packets[15:0]);
    wait((dut.u_fpga_verify_top.completed_case_count == exp_cases[15:0]) &&
         (dut.u_fpga_verify_top.global_fail_count == 16'd0));
    wait((!dut.u_fpga_verify_top.fifo_valid) &&
         (!dut.u_fpga_verify_top.manager_valid) &&
         (!dut.u_fpga_verify_top.controller_valid) &&
         (!dut.u_fpga_verify_top.generator_valid) &&
         (!dut.u_fpga_verify_top.checker_valid));
    repeat (128) @(posedge CLK_IN);

    if (!saw_uart_start) begin
      $error("board_top generated run never drove UART_TX start bit");
      $fatal;
    end

    if (!saw_led1_toggle) begin
      $error("board_top generated run heartbeat LED never toggled");
      $fatal;
    end

    if (DBG_LED[2] !== ~UART_TX) begin
      $error("board_top generated run UART activity LED mismatch");
      $fatal;
    end

    if (dut.u_fpga_verify_top.completed_case_count != exp_cases[15:0]) begin
      $error(
        "unexpected completed_case_count: exp=%0d got=%0d",
        exp_cases,
        dut.u_fpga_verify_top.completed_case_count
      );
      $fatal;
    end

    if (dut.u_fpga_verify_top.completed_pkt_count != exp_packets[15:0]) begin
      $error(
        "unexpected completed_pkt_count: exp=%0d got=%0d",
        exp_packets,
        dut.u_fpga_verify_top.completed_pkt_count
      );
      $fatal;
    end

    if (dut.u_fpga_verify_top.global_pass_count != exp_packets[15:0]) begin
      $error(
        "unexpected global_pass_count: exp=%0d got=%0d",
        exp_packets,
        dut.u_fpga_verify_top.global_pass_count
      );
      $fatal;
    end

    if (dut.u_fpga_verify_top.global_fail_count != 16'd0) begin
      $error(
        "unexpected global_fail_count: got=%0d",
        dut.u_fpga_verify_top.global_fail_count
      );
      $fatal;
    end

    if (dut.u_fpga_verify_top.all_done_sent != 1'b1) begin
      $error("board_top generated run never marked all_done_sent");
      $fatal;
    end

    $display(
      "tb_fpga_board_top_generated: PASS cases=%0d packets=%0d pass=%0d fail=%0d",
      exp_cases,
      exp_packets,
      dut.u_fpga_verify_top.global_pass_count,
      dut.u_fpga_verify_top.global_fail_count
    );
    $finish;
  end

  initial begin
    repeat (200000000) @(posedge CLK_IN);
    $error(
      "timeout waiting for fpga_board_top generated run: cases=%0d packets=%0d completed_case=%0d completed_pkt=%0d pass=%0d fail=%0d all_done=%0b",
      dut.u_fpga_verify_top.case_total,
      dut.u_fpga_verify_top.pkt_total,
      dut.u_fpga_verify_top.completed_case_count,
      dut.u_fpga_verify_top.completed_pkt_count,
      dut.u_fpga_verify_top.global_pass_count,
      dut.u_fpga_verify_top.global_fail_count,
      dut.u_fpga_verify_top.all_done
    );
    $fatal;
  end
endmodule
