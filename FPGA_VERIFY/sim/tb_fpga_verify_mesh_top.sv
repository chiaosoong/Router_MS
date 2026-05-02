`timescale 1ns/1ps

module tb_fpga_verify_mesh_top;
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
  int uart_start_count;
  bit saw_case_done;
  bit saw_progress;
  bit saw_all_done;

  fpga_verify_top #(
    .CASE_MEM_DEPTH(8),
    .CASE_MEM_FILE("FPGA_VERIFY/sim/top_test_case.memh"),
    .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT_TB)
  ) dut (
    .CLK(CLK),
    .RSTn(RSTn),
    .UART_TX(UART_TX)
  );

  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  always @(negedge UART_TX) begin
    uart_start_count = uart_start_count + 1;
  end

  always @(UART_TX) begin
    if (RSTn) begin
      $display("[UART_TX_RAW] t=%0t UART_TX=%0b", $time, UART_TX);
    end
  end

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

  initial begin
    string exp0;
    string exp1;
    string exp2;
    string exp3;
    string exp4;
    string exp5;

    exp0 = "CASE_START,0000,0001\n";
    exp1 = "PKT_INJ,0000,0100,00,01,0,0,01,00000002\n";
    exp2 = "PKT_DONE,0000,0100,00,01,0,0,01,PASS,00000006\n";
    exp3 = "CASE_DONE,0000,0001,0001,0000,00000006,00000006,00000006\n";
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
    recv_line(exp2.len(), uart_line2);
    recv_line(exp3.len(), uart_line3);
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
    if (uart_line2 != exp2) begin
      $error("unexpected uart line2: %s", uart_line2);
      $fatal;
    end
    if (uart_line3 != exp3) begin
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

    $display("[UART0] %s", uart_line0);
    $display("[UART1] %s", uart_line1);
    $display("[UART2] %s", uart_line2);
    $display("[UART3] %s", uart_line3);
    $display("[UART4] %s", uart_line4);
    $display("[UART5] %s", uart_line5);
    uart_decode_done = 1'b1;
  end

  initial begin
    ctrl_evt_count = 0;
    gen_evt_count  = 0;
    chk_evt_count  = 0;
    mgr_evt_count  = 0;
    uart_start_count = 0;
    saw_case_done = 1'b0;
    saw_progress  = 1'b0;
    saw_all_done  = 1'b0;
    RSTn = 1'b0;
    repeat (5) @(posedge CLK);
    RSTn = 1'b1;
    wait(saw_all_done);
    wait(uart_decode_done);
    repeat (300) @(posedge CLK);

    if (ctrl_evt_count != 1) begin
      $error("expected 1 controller event, got %0d", ctrl_evt_count);
      $fatal;
    end
    if (gen_evt_count != 1) begin
      $error("expected 1 generator event, got %0d", gen_evt_count);
      $fatal;
    end
    if (chk_evt_count != 1) begin
      $error("expected 1 checker event, got %0d", chk_evt_count);
      $fatal;
    end
    if (mgr_evt_count != 3) begin
      $error("expected 3 manager events, got %0d", mgr_evt_count);
      $fatal;
    end
    if (!saw_case_done || !saw_progress || !saw_all_done) begin
      $error("manager event coverage incomplete");
      $fatal;
    end
    if (uart_start_count == 0) begin
      $error("UART_TX never toggled low");
      $fatal;
    end

    $display("tb_fpga_verify_mesh_top: PASS");
    $finish;
  end

  initial begin
    forever begin
      @(posedge CLK);
      if (dut.controller_valid && dut.controller_ready) begin
        ctrl_evt_count = ctrl_evt_count + 1;
        $display("[CTRL] evt=%0d case=%0h pkt_total=%0h t=%0t",
                 dut.controller_event.event_type, dut.controller_event.case_id,
                 dut.controller_event.pkt_total, $time);
      end
      if (dut.generator_valid && dut.generator_ready) begin
        gen_evt_count = gen_evt_count + 1;
        $display("[GEN ] evt=%0d case=%0h pkt=%0h t=%0t",
                 dut.generator_event.event_type, dut.generator_event.case_id,
                 dut.generator_event.pkt_id, $time);
      end
      if (dut.checker_valid && dut.checker_ready) begin
        chk_evt_count = chk_evt_count + 1;
        $display("[CHK ] evt=%0d case=%0h pkt=%0h err=%0d lat=%0h t=%0t",
                 dut.checker_event.event_type, dut.checker_event.case_id,
                 dut.checker_event.pkt_id, dut.checker_event.error_code,
                 dut.checker_event.latency, $time);
      end
      if (dut.manager_valid && dut.manager_ready) begin
        mgr_evt_count = mgr_evt_count + 1;
        saw_case_done = saw_case_done || (dut.manager_event.event_type == EVT_CASE_DONE);
        saw_progress  = saw_progress  || (dut.manager_event.event_type == EVT_PROGRESS);
        saw_all_done  = saw_all_done  || (dut.manager_event.event_type == EVT_ALL_DONE);
        $display("[MGR ] evt=%0d case=%0h pkt_done=%0h pass=%0h fail=%0h t=%0t",
                 dut.manager_event.event_type, dut.manager_event.case_id,
                 dut.manager_event.pkt_done, dut.manager_event.pass_count,
                 dut.manager_event.fail_count, $time);
      end
    end
  end

  initial begin
    repeat (30000) @(posedge CLK);
    $error("timeout waiting for full fpga_verify_top integration");
    $fatal;
  end
endmodule
