`timescale 1ns/1ps

module tb_fpga_uart_reporter;
  import noc_params::*;
  import fpga_verify_pkg::*;

  localparam int CLKS_PER_BIT_TB = 4;

  logic CLK;
  logic RSTn;
  report_event_t in_event;
  logic          in_valid;
  logic          in_ready;
  logic          UART_TX;

  fpga_uart_reporter #(
    .CLKS_PER_BIT(CLKS_PER_BIT_TB)
  ) dut (
    .CLK(CLK),
    .RSTn(RSTn),
    .in_event(in_event),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .UART_TX(UART_TX)
  );

  task automatic send_event(input report_event_t ev);
    begin
      @(negedge CLK);
      in_event = ev;
      in_valid = 1'b1;
      wait(in_ready);
      @(posedge CLK);
      @(negedge CLK);
      in_valid = 1'b0;
    end
  endtask

  task automatic recv_line(
    input  int    exp_len,
    output string got
  );
    int char_idx;
    int bit_idx;
    byte ch;
    begin
      @(negedge UART_TX);
      repeat (CLKS_PER_BIT_TB + (CLKS_PER_BIT_TB/2)) @(posedge CLK);
      got = "";

      for (char_idx = 0; char_idx < exp_len; char_idx++) begin
        ch = 8'h00;
        for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
          ch[bit_idx] = UART_TX;
          if (bit_idx != 7) begin
            repeat (CLKS_PER_BIT_TB) @(posedge CLK);
          end
        end
        got = {got, ch};
        if (char_idx != exp_len-1) begin
          repeat (CLKS_PER_BIT_TB * 3) @(posedge CLK);
        end
      end
    end
  endtask

  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  initial begin
    string got;
    string expected;
    report_event_t ev;

    got      = "";
    expected = "PKT_DONE,0007,0200,00,01,0,0,03,PASS,00000012\n";
    in_event = '0;
    in_valid = 1'b0;
    RSTn     = 1'b0;
    repeat (3) @(posedge CLK);
    RSTn = 1'b1;

    ev = '0;
    ev.event_type = EVT_PKT_DONE;
    ev.case_id    = 16'h0007;
    ev.pkt_id     = 16'h0200;
    ev.src_rid    = 8'h00;
    ev.dst_rid    = 8'h01;
    ev.msg_class  = REQ;
    ev.vc_id      = '0;
    ev.pkt_len    = 8'h03;
    ev.latency    = 32'h00000012;

    fork
      begin
        send_event(ev);
      end
      begin
        recv_line(expected.len(), got);
      end
    join

    if (got != expected) begin
      $error("unexpected uart line: %s", got);
      $fatal;
    end

    wait(in_ready);

    $display("tb_fpga_uart_reporter: PASS");
    $finish;
  end

  initial begin
    repeat (3000) @(posedge CLK);
    $error("timeout waiting for uart reporter test");
    $fatal;
  end
endmodule
