`timescale 1ns/1ps

module tb_fpga_report_fifo;
  import noc_params::*;
  import fpga_verify_pkg::*;

  logic CLK;
  logic RSTn;
  report_event_t in_event;
  logic          in_valid;
  logic          in_ready;
  report_event_t out_event;
  logic          out_valid;
  logic          out_ready;

  fpga_report_fifo #(
    .DEPTH(4)
  ) dut (
    .CLK(CLK),
    .RSTn(RSTn),
    .in_event(in_event),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .out_event(out_event),
    .out_valid(out_valid),
    .out_ready(out_ready)
  );

  function automatic report_event_t make_event(input int idx);
    report_event_t ev;
    ev = '0;
    ev.event_type = EVT_PKT_DONE;
    ev.case_id = 16'h0010 + idx;
    ev.pkt_id = 16'h0100 + idx;
    ev.latency = 32'h20 + idx;
    return ev;
  endfunction

  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  initial begin
    in_event  = '0;
    in_valid  = 1'b0;
    out_ready = 1'b0;
    RSTn      = 1'b0;
    repeat (3) @(posedge CLK);
    RSTn = 1'b1;
    @(negedge CLK);

    in_event = make_event(0);
    in_valid = 1'b1;
    @(posedge CLK);
    @(negedge CLK);
    in_event = make_event(1);
    @(posedge CLK);
    @(negedge CLK);
    in_event = make_event(2);
    @(posedge CLK);
    @(negedge CLK);
    in_valid = 1'b0;

    if (!out_valid) begin
      $error("fifo should hold data after enqueue");
      $fatal;
    end

    #1;
    if (out_event.pkt_id != 16'h0100) begin
      $error("unexpected first pkt id: 0x%0h", out_event.pkt_id);
      $fatal;
    end
    out_ready = 1'b1;
    @(posedge CLK);
    out_ready = 1'b0;
    #1;
    if (out_event.pkt_id != 16'h0101) begin
      $error("unexpected second pkt id: 0x%0h", out_event.pkt_id);
      $fatal;
    end
    out_ready = 1'b1;
    @(posedge CLK);
    out_ready = 1'b0;
    #1;
    if (out_event.pkt_id != 16'h0102) begin
      $error("unexpected third pkt id: 0x%0h", out_event.pkt_id);
      $fatal;
    end
    out_ready = 1'b1;
    @(posedge CLK);
    out_ready = 1'b0;
    #1;
    if (out_valid) begin
      $error("fifo should be empty after three pops");
      $fatal;
    end

    $display("tb_fpga_report_fifo: PASS");
    $finish;
  end

  initial begin
    repeat (40) @(posedge CLK);
    $error("timeout waiting for report fifo test");
    $fatal;
  end
endmodule
