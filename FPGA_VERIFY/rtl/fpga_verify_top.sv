module fpga_verify_top #(
  parameter int CASE_MEM_DEPTH = 256,
  parameter string CASE_MEM_FILE = "FPGA_VERIFY/mem/case_rom.memh",
  parameter int UART_CLKS_PER_BIT = 16
) (
  input  logic CLK,
  input  logic RSTn,
  output logic UART_TX
);
  import noc_params::*;
  import fpga_verify_pkg::*;
  localparam int CASE_TRACK_DEPTH = CASE_MEM_DEPTH;
  localparam int CASE_TRACK_IDX_W = (CASE_TRACK_DEPTH <= 1) ? 1 : $clog2(CASE_TRACK_DEPTH);

  router_vc_flit_if PE_IFLIT [POS_NUM*POS_NUM-1:0]();
  router_vc_flit_if PE_OFLIT [POS_NUM*POS_NUM-1:0]();

  pkt_desc_t   issue_pkt   [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0] issue_valid;
  logic [MAX_CONCURRENT_PKT-1:0] issue_ready;
  pkt_desc_t                     inject_pkt [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0] inject_valid;
  logic [MAX_CONCURRENT_PKT-1:0][LATENCY_W-1:0] inject_cycle;
  logic [MAX_CONCURRENT_PKT-1:0] inject_ready;
  logic                          all_done;
  logic                          case_done_pulse;
  logic [15:0]                   case_done_pulse_id;
  logic                          case_meta_valid;
  logic [15:0]                   case_meta_id;
  logic [15:0]                   case_meta_pkt_total;
  logic [15:0]                   case_total;
  logic [15:0]                   pkt_total;

  report_event_t controller_event;
  logic          controller_valid;
  logic          controller_ready;
  report_event_t generator_event;
  logic          generator_valid;
  logic          generator_ready;
  report_event_t checker_event;
  logic          checker_valid;
  logic          checker_ready;
  report_event_t manager_event;
  logic          manager_valid;
  logic          manager_ready;
  report_event_t arb_event;
  logic          arb_valid;
  logic          arb_ready;
  report_event_t fifo_event;
  logic          fifo_valid;
  logic          fifo_ready;

  logic [15:0] case_expected_total [0:CASE_TRACK_DEPTH-1];
  logic [15:0] case_done_count_by_id [0:CASE_TRACK_DEPTH-1];
  logic [15:0] case_pass_count_by_id [0:CASE_TRACK_DEPTH-1];
  logic [15:0] case_fail_count_by_id [0:CASE_TRACK_DEPTH-1];
  logic [LATENCY_W-1:0] case_latency_sum_by_id [0:CASE_TRACK_DEPTH-1];
  logic [LATENCY_W-1:0] case_latency_min_by_id [0:CASE_TRACK_DEPTH-1];
  logic [LATENCY_W-1:0] case_latency_max_by_id [0:CASE_TRACK_DEPTH-1];
  logic [CASE_TRACK_DEPTH-1:0] case_done_marked;
  logic [15:0] completed_case_count;
  logic [15:0] completed_pkt_count;
  logic [15:0] global_pass_count;
  logic [15:0] global_fail_count;
  logic        all_done_sent;
  localparam int MANAGER_Q_DEPTH = (CASE_MEM_DEPTH * 2) + 4;
  report_event_t manager_queue [0:MANAGER_Q_DEPTH-1];
  logic [$clog2(MANAGER_Q_DEPTH)-1:0] manager_q_wr_ptr;
  logic [$clog2(MANAGER_Q_DEPTH)-1:0] manager_q_rd_ptr;
  logic [$clog2(MANAGER_Q_DEPTH+1)-1:0] manager_q_count;

  MESH_3x3_TOP dut (
    .CLK(CLK),
    .RSTn(RSTn),
    .PE_IFLIT(PE_IFLIT),
    .PE_OFLIT(PE_OFLIT)
  );

  fpga_test_controller #(
    .CASE_MEM_DEPTH(CASE_MEM_DEPTH),
    .CASE_MEM_FILE(CASE_MEM_FILE)
  ) u_controller (
    .CLK(CLK),
    .RSTn(RSTn),
    .issue_pkt(issue_pkt),
    .issue_valid(issue_valid),
    .issue_ready(issue_ready),
    .report_event(controller_event),
    .report_valid(controller_valid),
    .report_ready(controller_ready),
    .all_done(all_done),
    .case_done_valid(case_done_pulse),
    .case_done_id(case_done_pulse_id),
    .case_meta_valid(case_meta_valid),
    .case_meta_id(case_meta_id),
    .case_meta_pkt_total(case_meta_pkt_total),
    .case_total(case_total),
    .pkt_total(pkt_total)
  );

  fpga_mesh_traffic_generator u_generator (
    .CLK(CLK),
    .RSTn(RSTn),
    .issue_pkt(issue_pkt),
    .issue_valid(issue_valid),
    .issue_ready(issue_ready),
    .inject_pkt(inject_pkt),
    .inject_valid(inject_valid),
    .inject_cycle(inject_cycle),
    .inject_ready(inject_ready),
    .report_event(generator_event),
    .report_valid(generator_valid),
    .report_ready(generator_ready),
    .PE_IFLIT(PE_IFLIT)
  );

  fpga_mesh_packet_checker #(
    .TRACK_DEPTH(1024)
  ) u_checker (
    .CLK(CLK),
    .RSTn(RSTn),
    .inject_pkt(inject_pkt),
    .inject_valid(inject_valid),
    .inject_cycle(inject_cycle),
    .inject_ready(inject_ready),
    .PE_OFLIT(PE_OFLIT),
    .report_event(checker_event),
    .report_valid(checker_valid),
    .report_ready(checker_ready)
  );

  fpga_report_fifo #(
    .DEPTH(64)
  ) u_report_fifo (
    .CLK(CLK),
    .RSTn(RSTn),
    .in_event(arb_event),
    .in_valid(arb_valid),
    .in_ready(arb_ready),
    .out_event(fifo_event),
    .out_valid(fifo_valid),
    .out_ready(fifo_ready)
  );

  fpga_uart_reporter #(
    .CLKS_PER_BIT(UART_CLKS_PER_BIT)
  ) u_uart_reporter (
    .CLK(CLK),
    .RSTn(RSTn),
    .in_event(fifo_event),
    .in_valid(fifo_valid),
    .in_ready(fifo_ready),
    .UART_TX(UART_TX)
  );

  assign manager_valid = (manager_q_count != 0);
  assign manager_event = manager_queue[manager_q_rd_ptr];

  always_comb begin
    arb_event = '0;
    arb_valid = 1'b0;
    controller_ready = 1'b0;
    generator_ready  = 1'b0;
    checker_ready    = 1'b0;
    manager_ready    = 1'b0;

    if (checker_valid) begin
      arb_event     = checker_event;
      arb_valid     = 1'b1;
      checker_ready = arb_ready;
    end else if (manager_valid) begin
      arb_event     = manager_event;
      arb_valid     = 1'b1;
      manager_ready = arb_ready;
    end else if (generator_valid) begin
      arb_event      = generator_event;
      arb_valid      = 1'b1;
      generator_ready = arb_ready;
    end else if (controller_valid) begin
      arb_event       = controller_event;
      arb_valid       = 1'b1;
      controller_ready = arb_ready;
    end
  end

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      int i;
      completed_case_count <= '0;
      completed_pkt_count  <= '0;
      global_pass_count    <= '0;
      global_fail_count    <= '0;
      all_done_sent        <= 1'b0;
      case_done_pulse      <= 1'b0;
      case_done_pulse_id   <= '0;
      manager_q_wr_ptr     <= '0;
      manager_q_rd_ptr     <= '0;
      manager_q_count      <= '0;
      case_done_marked     <= '0;
      for (i = 0; i < CASE_TRACK_DEPTH; i++) begin
        case_expected_total[i] <= '0;
        case_done_count_by_id[i] <= '0;
        case_pass_count_by_id[i] <= '0;
        case_fail_count_by_id[i] <= '0;
        case_latency_sum_by_id[i] <= '0;
        case_latency_min_by_id[i] <= '0;
        case_latency_max_by_id[i] <= '0;
      end
      for (i = 0; i < MANAGER_Q_DEPTH; i++) begin
        manager_queue[i] <= '0;
      end
    end else begin
      logic [CASE_TRACK_IDX_W-1:0] case_idx;
      logic [CASE_TRACK_IDX_W-1:0] meta_case_idx;
      logic [15:0] effective_expected_total;
      logic [15:0] next_case_done_cnt;
      logic [15:0] next_case_pass_cnt;
      logic [15:0] next_case_fail_cnt;
      logic [15:0] next_completed_pkt_count;
      logic [15:0] next_completed_case_count;
      logic [15:0] next_global_pass_count;
      logic [15:0] next_global_fail_count;
      logic [LATENCY_W-1:0] next_case_latency_sum;
      logic [LATENCY_W-1:0] next_case_latency_min;
      logic [LATENCY_W-1:0] next_case_latency_max;
      logic        case_completed_now;
      logic [CASE_TRACK_DEPTH-1:0] case_done_marked_eff;
      int          q_wr_tmp;
      int          q_count_tmp;

      q_wr_tmp    = manager_q_wr_ptr;
      q_count_tmp = manager_q_count;
      next_completed_pkt_count  = completed_pkt_count;
      next_completed_case_count = completed_case_count;
      next_global_pass_count    = global_pass_count;
      next_global_fail_count    = global_fail_count;
      case_done_marked_eff      = case_done_marked;
      case_done_pulse           <= 1'b0;
      case_done_pulse_id        <= '0;

      if (manager_ready && manager_valid) begin
        manager_q_rd_ptr <= (manager_q_rd_ptr == MANAGER_Q_DEPTH-1) ? '0 : (manager_q_rd_ptr + 1'b1);
        q_count_tmp = q_count_tmp - 1;
      end

      if (case_meta_valid) begin
        case_expected_total[case_meta_id] <= case_meta_pkt_total;
        meta_case_idx = case_meta_id[CASE_TRACK_IDX_W-1:0];
        if ((case_meta_pkt_total != 16'd0) &&
            !case_done_marked_eff[meta_case_idx] &&
            (case_done_count_by_id[meta_case_idx] == case_meta_pkt_total)) begin
          report_event_t case_done_evt;

          case_done_marked_eff[meta_case_idx] = 1'b1;
          next_completed_case_count           = next_completed_case_count + 16'd1;
          case_done_pulse                     <= 1'b1;
          case_done_pulse_id                  <= case_meta_id;
          case_done_evt            = '0;
          case_done_evt.event_type = EVT_CASE_DONE;
          case_done_evt.case_id    = case_meta_id;
          case_done_evt.pkt_done   = case_done_count_by_id[meta_case_idx];
          case_done_evt.pass_count = case_pass_count_by_id[meta_case_idx];
          case_done_evt.fail_count = case_fail_count_by_id[meta_case_idx];
          case_done_evt.latency_sum = case_latency_sum_by_id[meta_case_idx];
          case_done_evt.latency_min = case_latency_min_by_id[meta_case_idx];
          case_done_evt.latency_max = case_latency_max_by_id[meta_case_idx];
          if (q_count_tmp < MANAGER_Q_DEPTH) begin
            manager_queue[q_wr_tmp] <= case_done_evt;
            q_wr_tmp = (q_wr_tmp == MANAGER_Q_DEPTH-1) ? 0 : (q_wr_tmp + 1);
            q_count_tmp = q_count_tmp + 1;
          end
        end
      end

      if (checker_valid && checker_ready &&
          ((checker_event.event_type == EVT_PKT_DONE) || (checker_event.event_type == EVT_PKT_FAIL))) begin
        case_idx = checker_event.case_id[CASE_TRACK_IDX_W-1:0];
        next_completed_pkt_count = completed_pkt_count + 16'd1;
        next_case_done_cnt       = case_done_count_by_id[case_idx] + 16'd1;
        next_case_pass_cnt       = case_pass_count_by_id[case_idx];
        next_case_fail_cnt       = case_fail_count_by_id[case_idx];
        next_case_latency_sum    = case_latency_sum_by_id[case_idx];
        next_case_latency_min    = case_latency_min_by_id[case_idx];
        next_case_latency_max    = case_latency_max_by_id[case_idx];

        if (checker_event.event_type == EVT_PKT_DONE) begin
          next_global_pass_count = global_pass_count + 16'd1;
          next_case_pass_cnt     = case_pass_count_by_id[case_idx] + 16'd1;
          next_case_latency_sum  = case_latency_sum_by_id[case_idx] + checker_event.latency;
          if (case_pass_count_by_id[case_idx] == 16'd0) begin
            next_case_latency_min = checker_event.latency;
            next_case_latency_max = checker_event.latency;
          end else begin
            if (checker_event.latency < case_latency_min_by_id[case_idx]) begin
              next_case_latency_min = checker_event.latency;
            end
            if (checker_event.latency > case_latency_max_by_id[case_idx]) begin
              next_case_latency_max = checker_event.latency;
            end
          end
        end else begin
          next_global_fail_count = global_fail_count + 16'd1;
          next_case_fail_cnt     = case_fail_count_by_id[case_idx] + 16'd1;
        end

        effective_expected_total = case_expected_total[case_idx];
        if (case_meta_valid && (case_meta_id[CASE_TRACK_IDX_W-1:0] == case_idx)) begin
          effective_expected_total = case_meta_pkt_total;
        end

        case_completed_now = (effective_expected_total != 16'd0) &&
                             !case_done_marked_eff[case_idx] &&
                             (next_case_done_cnt == effective_expected_total);

        completed_pkt_count             <= next_completed_pkt_count;
        global_pass_count               <= next_global_pass_count;
        global_fail_count               <= next_global_fail_count;
        case_done_count_by_id[case_idx] <= next_case_done_cnt;
        case_pass_count_by_id[case_idx] <= next_case_pass_cnt;
        case_fail_count_by_id[case_idx] <= next_case_fail_cnt;
        case_latency_sum_by_id[case_idx] <= next_case_latency_sum;
        case_latency_min_by_id[case_idx] <= next_case_latency_min;
        case_latency_max_by_id[case_idx] <= next_case_latency_max;

        if (case_completed_now) begin
          report_event_t case_done_evt;

          next_completed_case_count       = next_completed_case_count + 16'd1;
          case_done_marked_eff[case_idx]  = 1'b1;
          case_done_pulse                 <= 1'b1;
          case_done_pulse_id              <= checker_event.case_id;
          case_done_evt            = '0;
          case_done_evt.event_type = EVT_CASE_DONE;
          case_done_evt.case_id    = checker_event.case_id;
          case_done_evt.pkt_done   = next_case_done_cnt;
          case_done_evt.pass_count = next_case_pass_cnt;
          case_done_evt.fail_count = next_case_fail_cnt;
          case_done_evt.latency_sum = next_case_latency_sum;
          case_done_evt.latency_min = next_case_latency_min;
          case_done_evt.latency_max = next_case_latency_max;
          if (q_count_tmp < MANAGER_Q_DEPTH) begin
            manager_queue[q_wr_tmp] <= case_done_evt;
            q_wr_tmp = (q_wr_tmp == MANAGER_Q_DEPTH-1) ? 0 : (q_wr_tmp + 1);
            q_count_tmp = q_count_tmp + 1;
          end
        end

        if (case_completed_now ||
            (next_completed_pkt_count == pkt_total) ||
            (next_completed_pkt_count[5:0] == 6'd0)) begin
          report_event_t progress_evt;
          progress_evt            = '0;
          progress_evt.event_type = EVT_PROGRESS;
          progress_evt.case_done  = next_completed_case_count;
          progress_evt.case_total = case_total;
          progress_evt.pkt_done   = next_completed_pkt_count;
          progress_evt.pkt_total  = pkt_total;
          progress_evt.pass_count = next_global_pass_count;
          progress_evt.fail_count = next_global_fail_count;
          if (q_count_tmp < MANAGER_Q_DEPTH) begin
            manager_queue[q_wr_tmp] <= progress_evt;
            q_wr_tmp = (q_wr_tmp == MANAGER_Q_DEPTH-1) ? 0 : (q_wr_tmp + 1);
            q_count_tmp = q_count_tmp + 1;
          end
        end
      end

      if (all_done && (next_completed_pkt_count == pkt_total) && !all_done_sent) begin
        report_event_t all_done_evt;
        all_done_evt            = '0;
        all_done_evt.event_type = EVT_ALL_DONE;
        all_done_evt.case_total = case_total;
        all_done_evt.pkt_total  = pkt_total;
        all_done_evt.pass_count = next_global_pass_count;
        all_done_evt.fail_count = next_global_fail_count;
        if (q_count_tmp < MANAGER_Q_DEPTH) begin
          manager_queue[q_wr_tmp] <= all_done_evt;
          q_wr_tmp = (q_wr_tmp == MANAGER_Q_DEPTH-1) ? 0 : (q_wr_tmp + 1);
          q_count_tmp = q_count_tmp + 1;
        end
        all_done_sent <= 1'b1;
      end

      manager_q_wr_ptr      <= q_wr_tmp[$clog2(MANAGER_Q_DEPTH)-1:0];
      manager_q_count       <= q_count_tmp[$clog2(MANAGER_Q_DEPTH+1)-1:0];
      completed_case_count  <= next_completed_case_count;
      case_done_marked      <= case_done_marked_eff;
    end
  end
endmodule
