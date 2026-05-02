`timescale 1ns/1ps

module tb_fpga_verify_mesh_top_multiflit;
  import noc_params::*;
  import fpga_verify_pkg::*;

  localparam int UART_CLKS_PER_BIT_TB = 4;

  logic CLK;
  logic RSTn;
  logic UART_TX;
  string uart_line0;
  string uart_line1;
  string uart_line2;
  string uart_line3;
  string uart_line4;
  string uart_line5;
  bit uart_decode_done;

  int ctrl_evt_count;
  int gen_evt_count;
  int chk_evt_count;
  int mgr_evt_count;

  fpga_verify_top #(
    .CASE_MEM_DEPTH(8),
    .CASE_MEM_FILE("FPGA_VERIFY/sim/top_test_case_multiflit.memh"),
    .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT_TB)
  ) dut (
    .CLK(CLK),
    .RSTn(RSTn),
    .UART_TX(UART_TX)
  );

  function automatic bit starts_with(input string line, input string prefix);
    int idx;
    begin
      if (line.len() < prefix.len()) begin
        return 1'b0;
      end
      for (idx = 0; idx < prefix.len(); idx++) begin
        if (line[idx] != prefix[idx]) begin
          return 1'b0;
        end
      end
      return 1'b1;
    end
  endfunction

  task automatic recv_line(
    input  int    exp_len,
    output string got
  );
    int char_idx;
    int bit_idx;
    byte ch;
    begin
      @(negedge UART_TX);
      repeat (UART_CLKS_PER_BIT_TB + (UART_CLKS_PER_BIT_TB/2)) @(posedge CLK);
      got = "";
      for (char_idx = 0; char_idx < exp_len; char_idx++) begin
        ch = 8'h00;
        for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
          ch[bit_idx] = UART_TX;
          if (bit_idx != 7) begin
            repeat (UART_CLKS_PER_BIT_TB) @(posedge CLK);
          end
        end
        got = {got, ch};
        if (char_idx != exp_len-1) begin
          repeat (UART_CLKS_PER_BIT_TB * 3) @(posedge CLK);
        end
      end
    end
  endtask

  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  initial begin
    string exp0;
    string exp1;
    string exp3_prefix;
    string exp4;
    string exp5;

    exp0 = "CASE_START,0000,0001\n";
    exp1 = "PKT_INJ,0000,0200,00,08,0,0,03,00000002\n";
    exp3_prefix = "CASE_DONE,0000,0001,0001,0000,";
    exp4 = "PROGRESS,0001,0001,0001,0001,0001,0000\n";
    exp5 = "ALL_DONE,0001,0001,0001,0000,0000\n";

    uart_line0 = "";
    uart_line1 = "";
    uart_line2 = "";
    uart_line3 = "";
    uart_line4 = "";
    uart_line5 = "";
    uart_decode_done = 1'b0;

    wait(RSTn);
    recv_line(exp0.len(), uart_line0);
    recv_line(exp1.len(), uart_line1);
    recv_line(46, uart_line2);
    recv_line(57, uart_line3);
    recv_line(exp4.len(), uart_line4);
    recv_line(exp5.len(), uart_line5);

    if (uart_line0 != exp0) begin
      $error("unexpected uart line0: %s", uart_line0);
      $fatal;
    end
    if (uart_line1 != exp1) begin
      $error("unexpected uart line1: %s", uart_line1);
      $fatal;
    end
    if (!starts_with(uart_line2, "PKT_DONE,0000,0200,00,08,0,0,03,PASS,")) begin
      $error("unexpected uart line2: %s", uart_line2);
      $fatal;
    end
    if (!starts_with(uart_line3, exp3_prefix)) begin
      $error("unexpected uart line3: %s", uart_line3);
      $fatal;
    end
    if (uart_line4 != exp4) begin
      $error("unexpected uart line4: %s", uart_line4);
      $fatal;
    end
    if (uart_line5 != exp5) begin
      $error("unexpected uart line5: %s", uart_line5);
      $fatal;
    end

    $display("[MF_UART0] %s", uart_line0);
    $display("[MF_UART1] %s", uart_line1);
    $display("[MF_UART2] %s", uart_line2);
    $display("[MF_UART3] %s", uart_line3);
    $display("[MF_UART4] %s", uart_line4);
    $display("[MF_UART5] %s", uart_line5);
    uart_decode_done = 1'b1;
  end

  initial begin
    ctrl_evt_count = 0;
    gen_evt_count  = 0;
    chk_evt_count  = 0;
    mgr_evt_count  = 0;
    RSTn = 1'b0;
    repeat (5) @(posedge CLK);
    RSTn = 1'b1;
    wait(uart_decode_done);
    repeat (100) @(posedge CLK);

    if (ctrl_evt_count != 1 || gen_evt_count != 1 || chk_evt_count != 1 || mgr_evt_count != 3) begin
      $error("unexpected event counts ctrl=%0d gen=%0d chk=%0d mgr=%0d",
             ctrl_evt_count, gen_evt_count, chk_evt_count, mgr_evt_count);
      $fatal;
    end

    if (dut.checker_event.latency <= 32'd6) begin
      $error("multi-flit latency should be larger than single-flit case, got %0d", dut.checker_event.latency);
      $fatal;
    end

    $display("tb_fpga_verify_mesh_top_multiflit: PASS");
    $finish;
  end

  always @(posedge CLK) begin
    if (RSTn) begin
      if (dut.controller_valid && dut.controller_ready) ctrl_evt_count++;
      if (dut.generator_valid  && dut.generator_ready)  gen_evt_count++;
      if (dut.checker_valid    && dut.checker_ready)    chk_evt_count++;
      if (dut.manager_valid    && dut.manager_ready)    mgr_evt_count++;
    end
  end

  initial begin
    repeat (50000) @(posedge CLK);
    $error("timeout waiting for multi-flit top integration");
    $fatal;
  end
endmodule
