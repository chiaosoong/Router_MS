`timescale 1ns/1ps

module tb_fpga_test_controller;
  import fpga_verify_pkg::*;

  localparam string MEM_FILE = "FPGA_VERIFY/sim/controller_test_case.memh";

  logic CLK;
  logic RSTn;
  pkt_desc_t issue_pkt [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0] issue_valid;
  logic [MAX_CONCURRENT_PKT-1:0] issue_ready;
  report_event_t report_event;
  logic report_valid;
  logic report_ready;
  logic all_done;
  logic case_done_valid;
  logic [15:0] case_done_id;
  logic case_meta_valid;
  logic [15:0] case_meta_id;
  logic [15:0] case_meta_pkt_total;
  logic [15:0] case_total;
  logic [15:0] pkt_total;

  int seen_count;
  int seen_case [0:3];
  int seen_pkt  [0:3];
  int seen_cycle[0:3];

  fpga_test_controller #(
    .CASE_MEM_DEPTH(8),
    .CASE_MEM_FILE(MEM_FILE)
  ) dut (
    .CLK(CLK),
    .RSTn(RSTn),
    .issue_pkt(issue_pkt),
    .issue_valid(issue_valid),
    .issue_ready(issue_ready),
    .report_event(report_event),
    .report_valid(report_valid),
    .report_ready(report_ready),
    .all_done(all_done),
    .case_done_valid(case_done_valid),
    .case_done_id(case_done_id),
    .case_meta_valid(case_meta_valid),
    .case_meta_id(case_meta_id),
    .case_meta_pkt_total(case_meta_pkt_total),
    .case_total(case_total),
    .pkt_total(pkt_total)
  );

  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  initial begin
    issue_ready = '1;
    report_ready = 1'b1;
    case_done_valid = 1'b0;
    case_done_id    = '0;
    seen_count  = 0;
    RSTn        = 1'b0;
    repeat (4) @(posedge CLK);
    RSTn = 1'b1;
  end

  always @(posedge CLK) begin
    int slot;
    if (!RSTn) begin
      seen_count <= 0;
      case_done_valid <= 1'b0;
      case_done_id    <= '0;
    end else begin
      case_done_valid <= 1'b0;
      for (slot = 0; slot < MAX_CONCURRENT_PKT; slot++) begin
        if (issue_valid[slot] && issue_ready[slot]) begin
          $display(
            "[ISSUE] t=%0t slot=%0d case=%0d pkt=0x%0h start=%0d",
            $time,
            slot,
            issue_pkt[slot].case_id,
            issue_pkt[slot].pkt_id,
            issue_pkt[slot].start_slot
          );
          if (seen_count < 4) begin
            seen_case[seen_count]  = issue_pkt[slot].case_id;
            seen_pkt[seen_count]   = issue_pkt[slot].pkt_id;
            seen_cycle[seen_count] = $time / 10;
            seen_count             = seen_count + 1;
          end
        end
      end
      if (seen_count == 3) begin
        case_done_valid <= 1'b1;
        case_done_id    <= 16'd0;
      end
    end
  end

  initial begin
    wait(RSTn);
    wait(all_done);
    repeat (2) @(posedge CLK);

    if (case_total !== 16'd2) begin
      $error("case_total mismatch: exp=2 got=%0d", case_total);
      $fatal;
    end
    if (pkt_total !== 16'd4) begin
      $error("pkt_total mismatch: exp=4 got=%0d", pkt_total);
      $fatal;
    end
    if (seen_count != 4) begin
      $error("issued packet count mismatch: exp=4 got=%0d", seen_count);
      $fatal;
    end

    if ((seen_case[0] != 0) || (seen_pkt[0] != 'h0100)) begin
      $error("first issued packet mismatch");
      $fatal;
    end
    if ((seen_case[1] != 0) || (seen_pkt[1] != 'h0101)) begin
      $error("second issued packet mismatch");
      $fatal;
    end
    if ((seen_case[2] != 0) || (seen_pkt[2] != 'h0102)) begin
      $error("third issued packet mismatch");
      $fatal;
    end
    if ((seen_case[3] != 1) || (seen_pkt[3] != 'h0103)) begin
      $error("fourth issued packet mismatch");
      $fatal;
    end

    if (seen_cycle[1] != seen_cycle[0]) begin
      $error("same-slot concurrency failed: packets 0 and 1 were not issued together");
      $fatal;
    end
    if (!(seen_cycle[2] > seen_cycle[0])) begin
      $error("start_slot scheduling failed: packet 2 was not delayed");
      $fatal;
    end
    if (!(seen_cycle[3] >= seen_cycle[2])) begin
      $error("case transition scheduling failed");
      $fatal;
    end

    $display("tb_fpga_test_controller: PASS");
    $finish;
  end

  initial begin
    repeat (200) @(posedge CLK);
    $error(
      "timeout waiting for all_done: all_done=%0b case_total=%0d pkt_total=%0d seen_count=%0d",
      all_done,
      case_total,
      pkt_total,
      seen_count
    );
    $fatal;
  end
endmodule
