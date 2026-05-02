`timescale 1ns/1ps

module tb_fpga_verify_mesh_top_concurrent;
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
  string uart_line6;
  string uart_line7;
  string uart_line8;
  bit uart_decode_done;

  int ctrl_evt_count;
  int gen_evt_count;
  int chk_evt_count;
  int mgr_evt_count;

  fpga_verify_top #(
    .CASE_MEM_DEPTH(8),
    .CASE_MEM_FILE("FPGA_VERIFY/sim/top_test_case_concurrent.memh"),
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
    string exp2;
    string exp5_prefix;
    string exp6;
    string exp7;

    exp0 = "CASE_START,0000,0002\n";
    exp1 = "PKT_INJ,0000,0300,00,01,0,0,01,00000002\n";
    exp2 = "PKT_INJ,0000,0301,08,07,1,2,01,00000002\n";
    exp5_prefix = "CASE_DONE,0000,0002,0002,0000,";
    exp6 = "PROGRESS,0001,0001,0002,0002,0002,0000\n";
    exp7 = "ALL_DONE,0001,0002,0002,0000,0000\n";

    uart_line0 = "";
    uart_line1 = "";
    uart_line2 = "";
    uart_line3 = "";
    uart_line4 = "";
    uart_line5 = "";
    uart_line6 = "";
    uart_line7 = "";
    uart_line8 = "";
    uart_decode_done = 1'b0;

    wait(RSTn);
    recv_line(exp0.len(), uart_line0);
    recv_line(exp1.len(), uart_line1);
    recv_line(exp2.len(), uart_line2);
    recv_line(46, uart_line3);
    recv_line(46, uart_line4);
    recv_line(57, uart_line5);
    recv_line(exp6.len(), uart_line6);
    recv_line(exp7.len(), uart_line7);

    if (uart_line0 != exp0) begin
      $error("unexpected uart line0: %s", uart_line0);
      $fatal;
    end
    if (uart_line1 != exp1) begin
      $error("unexpected uart line1: %s", uart_line1);
      $fatal;
    end
    if (uart_line2 != exp2) begin
      $error("unexpected uart line2: %s", uart_line2);
      $fatal;
    end
    if (!starts_with(uart_line3, "PKT_DONE,0000,0300,00,01,0,0,01,PASS,")) begin
      $error("unexpected uart line3: %s", uart_line3);
      $fatal;
    end
    if (!starts_with(uart_line4, "PKT_DONE,0000,0301,08,07,1,2,01,PASS,")) begin
      $error("unexpected uart line4: %s", uart_line4);
      $fatal;
    end
    if (!starts_with(uart_line5, exp5_prefix)) begin
      $error("unexpected uart line5: %s", uart_line5);
      $fatal;
    end
    if (uart_line6 != exp6) begin
      $error("unexpected uart line6: %s", uart_line6);
      $fatal;
    end
    if (uart_line7 != exp7) begin
      $error("unexpected uart line7: %s", uart_line7);
      $fatal;
    end

    $display("[CC_UART0] %s", uart_line0);
    $display("[CC_UART1] %s", uart_line1);
    $display("[CC_UART2] %s", uart_line2);
    $display("[CC_UART3] %s", uart_line3);
    $display("[CC_UART4] %s", uart_line4);
    $display("[CC_UART5] %s", uart_line5);
    $display("[CC_UART6] %s", uart_line6);
    $display("[CC_UART7] %s", uart_line7);
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

    if (ctrl_evt_count != 1 || gen_evt_count != 2 || chk_evt_count != 2 || mgr_evt_count != 3) begin
      $error("unexpected event counts ctrl=%0d gen=%0d chk=%0d mgr=%0d",
             ctrl_evt_count, gen_evt_count, chk_evt_count, mgr_evt_count);
      $fatal;
    end

    $display("tb_fpga_verify_mesh_top_concurrent: PASS");
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
    repeat (60000) @(posedge CLK);
    $error("timeout waiting for concurrent top integration");
    $fatal;
  end
endmodule
