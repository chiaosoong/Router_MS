`timescale 1ns/1ps

module tb_fpga_verify_mesh_top_generated;
  import noc_params::*;
  import fpga_verify_pkg::*;

  localparam int UART_CLKS_PER_BIT_TB = 1;

  logic CLK;
  logic RSTn;
  logic UART_TX;
  int exp_cases;
  int exp_packets;
  int ctrl_evt_count;
  int gen_evt_count;
  int chk_done_count;
  int chk_fail_count;
  int mgr_case_done_count;
  int mgr_progress_count;
  int mgr_all_done_count;
  int uart_start_count;
  int proto_line_count;
  int proto_log_fd;
  int dbg_case_idx;
  bit saw_all_done;
  bit uart_decode_done;
  string proto_last_line;

  fpga_verify_top #(
    .CASE_MEM_DEPTH(16384),
    .CASE_MEM_FILE("FPGA_VERIFY/mem/case_rom.memh"),
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

  initial begin
    proto_line_count = 0;
    uart_decode_done = 1'b1;
    proto_last_line = "";
    proto_log_fd = $fopen("E:/Master_thesis/Router_MS/FPGA_VERIFY/output/generated_uart_full.log", "w");
    if (proto_log_fd == 0) begin
      $error("failed to open generated UART log file");
      $fatal;
    end
  end

  initial begin
    ctrl_evt_count      = 0;
    gen_evt_count       = 0;
    chk_done_count      = 0;
    chk_fail_count      = 0;
    mgr_case_done_count = 0;
    mgr_progress_count  = 0;
    mgr_all_done_count  = 0;
    uart_start_count    = 0;
    saw_all_done        = 1'b0;
    RSTn = 1'b0;
    repeat (5) @(posedge CLK);
    RSTn = 1'b1;

    wait((dut.case_total != 0) && (dut.pkt_total != 0));
    exp_cases = dut.case_total;
    exp_packets = dut.pkt_total;

    wait((dut.completed_pkt_count == exp_packets) && dut.all_done);
    wait(dut.global_pass_count == exp_packets);
    wait((mgr_case_done_count == exp_cases) && (mgr_all_done_count == 1));
    wait((!dut.fifo_valid) && (!dut.manager_valid) && (!dut.controller_valid) && (!dut.generator_valid) && (!dut.checker_valid));
    repeat (200) @(posedge CLK);
    if (dut.case_total != exp_cases) begin
      $error("unexpected case_total: exp=%0d got=%0d", exp_cases, dut.case_total);
      $fatal;
    end
    if (dut.pkt_total != exp_packets) begin
      $error("unexpected pkt_total: exp=%0d got=%0d", exp_packets, dut.pkt_total);
      $fatal;
    end
    if (chk_done_count != exp_packets) begin
      $error("unexpected checker done count: exp=%0d got=%0d", exp_packets, chk_done_count);
      $fatal;
    end
    if (chk_fail_count != 0) begin
      $error("checker reported failures: %0d", chk_fail_count);
      $fatal;
    end
    if (dut.completed_case_count != exp_cases) begin
      $display(
        "[CASE_MISMATCH] ctrl_evt=%0d mgr_case_done=%0d completed_case=%0d completed_pkt=%0d case_total=%0d pkt_total=%0d",
        ctrl_evt_count,
        mgr_case_done_count,
        dut.completed_case_count,
        dut.completed_pkt_count,
        dut.case_total,
        dut.pkt_total
      );
      for (dbg_case_idx = 0; dbg_case_idx < exp_cases; dbg_case_idx++) begin
        if (!dut.case_done_marked[dbg_case_idx]) begin
          $display(
            "[MISSING_CASE] case=%0d expected=%0d done=%0d pass=%0d fail=%0d",
            dbg_case_idx,
            dut.case_expected_total[dbg_case_idx],
            dut.case_done_count_by_id[dbg_case_idx],
            dut.case_pass_count_by_id[dbg_case_idx],
            dut.case_fail_count_by_id[dbg_case_idx]
          );
        end
      end
      $error("unexpected completed_case_count: exp=%0d got=%0d", exp_cases, dut.completed_case_count);
      $fatal;
    end
    if (dut.completed_pkt_count != exp_packets) begin
      $error("unexpected completed_pkt_count: exp=%0d got=%0d", exp_packets, dut.completed_pkt_count);
      $fatal;
    end
    if (dut.global_pass_count != exp_packets) begin
      $error("unexpected global_pass_count: exp=%0d got=%0d", exp_packets, dut.global_pass_count);
      $fatal;
    end
    if (dut.global_fail_count != 0) begin
      $error("unexpected global_fail_count: exp=0 got=%0d", dut.global_fail_count);
      $fatal;
    end
    if (uart_start_count == 0) begin
      $error("UART_TX never toggled low");
      $fatal;
    end
    if (mgr_case_done_count != exp_cases) begin
      $error("unexpected manager CASE_DONE count: exp=%0d got=%0d", exp_cases, mgr_case_done_count);
      $fatal;
    end
    if (mgr_all_done_count != 1) begin
      $error("unexpected manager ALL_DONE count: exp=1 got=%0d", mgr_all_done_count);
      $fatal;
    end
    if (mgr_progress_count == 0) begin
      $error("expected at least one PROGRESS event");
      $fatal;
    end

    $fclose(proto_log_fd);
    $display(
      "tb_fpga_verify_mesh_top_generated: PASS generated_mem cases=%0d packets=%0d uart_starts=%0d proto_lines=%0d mgr_case_done=%0d mgr_all_done=%0d",
      exp_cases,
      exp_packets,
      uart_start_count,
      proto_line_count,
      mgr_case_done_count,
      mgr_all_done_count
    );
    $finish;
  end

  always @(posedge CLK) begin
    string line_buf;
    if (RSTn) begin
      if (dut.fifo_valid && dut.fifo_ready) begin
        unique case (dut.fifo_event.event_type)
          EVT_CASE_START: line_buf = $sformatf("CASE_START,%04h,%04h\n", dut.fifo_event.case_id, dut.fifo_event.pkt_total);
          EVT_PKT_INJ:    line_buf = $sformatf("PKT_INJ,%04h,%04h,%02h,%02h,%1h,%1h,%02h,%08h\n",
                                               dut.fifo_event.case_id, dut.fifo_event.pkt_id, dut.fifo_event.src_rid,
                                               dut.fifo_event.dst_rid, dut.fifo_event.msg_class, dut.fifo_event.vc_id,
                                               dut.fifo_event.pkt_len, dut.fifo_event.latency);
          EVT_PKT_DONE:   line_buf = $sformatf("PKT_DONE,%04h,%04h,%02h,%02h,%1h,%1h,%02h,PASS,%08h\n",
                                               dut.fifo_event.case_id, dut.fifo_event.pkt_id, dut.fifo_event.src_rid,
                                               dut.fifo_event.dst_rid, dut.fifo_event.msg_class, dut.fifo_event.vc_id,
                                               dut.fifo_event.pkt_len, dut.fifo_event.latency);
          EVT_PKT_FAIL:   line_buf = $sformatf("PKT_FAIL,%04h,%04h,%02h,%02h,%1h,%1h,%02h,FAIL,%02h,%08h\n",
                                               dut.fifo_event.case_id, dut.fifo_event.pkt_id, dut.fifo_event.src_rid,
                                               dut.fifo_event.dst_rid, dut.fifo_event.msg_class, dut.fifo_event.vc_id,
                                               dut.fifo_event.pkt_len, dut.fifo_event.error_code, dut.fifo_event.latency);
          EVT_CASE_DONE:  line_buf = $sformatf("CASE_DONE,%04h,%04h,%04h,%04h,%08h,%08h,%08h\n",
                                               dut.fifo_event.case_id, dut.fifo_event.pkt_done,
                                               dut.fifo_event.pass_count, dut.fifo_event.fail_count,
                                               dut.fifo_event.latency_sum, dut.fifo_event.latency_min,
                                               dut.fifo_event.latency_max);
          EVT_PROGRESS:   line_buf = $sformatf("PROGRESS,%04h,%04h,%04h,%04h,%04h,%04h\n",
                                               dut.fifo_event.case_done, dut.fifo_event.case_total,
                                               dut.fifo_event.pkt_done, dut.fifo_event.pkt_total,
                                               dut.fifo_event.pass_count, dut.fifo_event.fail_count);
          EVT_ALL_DONE:   line_buf = $sformatf("ALL_DONE,%04h,%04h,%04h,%04h,%04h\n",
                                               dut.fifo_event.case_total, dut.fifo_event.pkt_total,
                                               dut.fifo_event.pass_count, dut.fifo_event.fail_count,
                                               dut.fifo_event.error_code);
          default:        line_buf = "UNKNOWN\n";
        endcase
        proto_line_count = proto_line_count + 1;
        proto_last_line = line_buf;
        $fwrite(proto_log_fd, "%s", line_buf);
      end
      if (dut.controller_valid && dut.controller_ready) begin
        ctrl_evt_count++;
      end
      if (dut.generator_valid && dut.generator_ready) begin
        gen_evt_count++;
      end
      if (dut.checker_valid && dut.checker_ready) begin
        if (dut.checker_event.event_type == EVT_PKT_DONE) begin
          chk_done_count++;
        end else if (dut.checker_event.event_type == EVT_PKT_FAIL) begin
          chk_fail_count++;
          $display(
            "[GENMEM_FAIL] case=%0h pkt=%0h err=%0d lat=%0h t=%0t",
            dut.checker_event.case_id,
            dut.checker_event.pkt_id,
            dut.checker_event.error_code,
            dut.checker_event.latency,
            $time
          );
        end
      end
      if (dut.manager_valid && dut.manager_ready) begin
        unique case (dut.manager_event.event_type)
          EVT_CASE_DONE: mgr_case_done_count++;
          EVT_PROGRESS:  mgr_progress_count++;
          EVT_ALL_DONE: begin
            mgr_all_done_count++;
            saw_all_done <= 1'b1;
          end
          default: begin
          end
        endcase
      end
    end
  end

  initial begin
    repeat (200000000) @(posedge CLK);
    $display(
      "tb_fpga_verify_mesh_top_generated timeout: ctrl=%0d gen=%0d chk_done=%0d chk_fail=%0d mgr_case_done=%0d mgr_progress=%0d mgr_all_done=%0d saw_all_done=%0b case_total=%0d pkt_total=%0d completed_case=%0d completed_pkt=%0d pass=%0d fail=%0d controller_all_done=%0b read_ptr=%0d current_case=%0h issue_valid=%b issue_ready=%b gen_active=%b gen_inject=%b",
      ctrl_evt_count,
      gen_evt_count,
      chk_done_count,
      chk_fail_count,
      mgr_case_done_count,
      mgr_progress_count,
      mgr_all_done_count,
      saw_all_done,
      dut.case_total,
      dut.pkt_total,
      dut.completed_case_count,
      dut.completed_pkt_count,
      dut.global_pass_count,
      dut.global_fail_count,
      dut.all_done,
      dut.u_controller.read_ptr,
      dut.u_controller.current_case_id,
      dut.u_controller.issue_valid,
      dut.u_controller.issue_ready,
      dut.u_generator.active_valid,
      dut.u_generator.inject_valid
    );
    $display(
      "slot0 case=%0h src=%0d dst=%0d | slot1 case=%0h src=%0d dst=%0d | slot2 case=%0h src=%0d dst=%0d | slot3 case=%0h src=%0d dst=%0d",
      dut.u_controller.issue_pkt[0].case_id, dut.u_controller.issue_pkt[0].src_rid, dut.u_controller.issue_pkt[0].dst_rid,
      dut.u_controller.issue_pkt[1].case_id, dut.u_controller.issue_pkt[1].src_rid, dut.u_controller.issue_pkt[1].dst_rid,
      dut.u_controller.issue_pkt[2].case_id, dut.u_controller.issue_pkt[2].src_rid, dut.u_controller.issue_pkt[2].dst_rid,
      dut.u_controller.issue_pkt[3].case_id, dut.u_controller.issue_pkt[3].src_rid, dut.u_controller.issue_pkt[3].dst_rid
    );
    $display(
      "manager counters: exp_case10=%0d done_case10=%0d exp_case11=%0d done_case11=%0d exp_case51=%0d done_case51=%0d q_count=%0d manager_valid=%0b",
      dut.case_expected_total[8'h0A],
      dut.case_done_count_by_id[8'h0A],
      dut.case_expected_total[8'h0B],
      dut.case_done_count_by_id[8'h0B],
      dut.case_expected_total[8'h33],
      dut.case_done_count_by_id[8'h33],
      dut.manager_q_count,
      dut.manager_valid
    );
    $display("proto_line_count=%0d last_line=%s", proto_line_count, proto_last_line);
    $error("timeout waiting for generated mem top integration");
    $fatal;
  end
endmodule
