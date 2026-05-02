module fpga_test_controller #(
  parameter int CASE_MEM_DEPTH = 256,
  parameter string CASE_MEM_FILE = "FPGA_VERIFY/mem/case_rom.memh"
) (
  input  logic                                        CLK,
  input  logic                                        RSTn,
  output fpga_verify_pkg::pkt_desc_t                  issue_pkt [fpga_verify_pkg::MAX_CONCURRENT_PKT],
  output logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0] issue_valid,
  input  logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0] issue_ready,
  output fpga_verify_pkg::report_event_t              report_event,
  output logic                                        report_valid,
  input  logic                                        report_ready,
  output logic                                        all_done,
  input  logic                                        case_done_valid,
  input  logic [15:0]                                 case_done_id,
  output logic                                        case_meta_valid,
  output logic [15:0]                                 case_meta_id,
  output logic [15:0]                                 case_meta_pkt_total,
  output logic [15:0]                                 case_total,
  output logic [15:0]                                 pkt_total
);
  import fpga_verify_pkg::*;
  localparam int CASE_TRACK_DEPTH = CASE_MEM_DEPTH;
  localparam int REPORT_Q_PTR_W = (CASE_MEM_DEPTH <= 1) ? 1 : $clog2(CASE_MEM_DEPTH);
  localparam int REPORT_Q_CNT_W = $clog2(CASE_MEM_DEPTH + 1);

  logic [CASE_MEM_LINE_W-1:0] case_mem [0:CASE_MEM_DEPTH-1];
  logic [15:0]                case_pkt_count_mem [0:CASE_MEM_DEPTH-1];
  logic [15:0]                case_pkt_count_by_id [0:CASE_TRACK_DEPTH-1];
  report_event_t              report_queue [0:CASE_MEM_DEPTH-1];

  pkt_desc_t                     issue_pkt_r [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0] issue_valid_r;
  logic [REPORT_Q_PTR_W-1:0]     report_q_wr_ptr;
  logic [REPORT_Q_PTR_W-1:0]     report_q_rd_ptr;
  logic [REPORT_Q_CNT_W-1:0]     report_q_count;

  logic [15:0] read_ptr;
  logic [15:0] slot_ctr;
  logic [15:0] case_total_r;
  logic [15:0] pkt_total_r;
  logic [15:0] current_case_id;
  logic [15:0] current_case_index;
  logic        current_case_valid;
  logic        end_seen;

  integer idx;
  integer scan_idx;

  initial begin
    int case_entry_idx;
    logic [15:0] scan_case_id;

    for (scan_idx = 0; scan_idx < CASE_MEM_DEPTH; scan_idx++) begin
      case_mem[scan_idx] = '1;
      case_pkt_count_mem[scan_idx] = '0;
    end
    for (scan_idx = 0; scan_idx < CASE_TRACK_DEPTH; scan_idx++) begin
      case_pkt_count_by_id[scan_idx] = '0;
    end
    $readmemh(CASE_MEM_FILE, case_mem);

    case_total_r = '0;
    pkt_total_r  = '0;
    case_entry_idx = -1;
    for (scan_idx = 0; scan_idx < CASE_MEM_DEPTH; scan_idx++) begin
      if (raw_is_end_marker(case_mem[scan_idx])) begin
        break;
      end

      pkt_total_r = pkt_total_r + 16'd1;
      scan_case_id = raw_case_id(case_mem[scan_idx]);
      case_pkt_count_by_id[scan_case_id] = case_pkt_count_by_id[scan_case_id] + 16'd1;
      if ((scan_idx == 0) || (raw_case_id(case_mem[scan_idx]) != raw_case_id(case_mem[scan_idx-1]))) begin
        case_total_r = case_total_r + 16'd1;
        case_entry_idx = case_entry_idx + 1;
        case_pkt_count_mem[case_entry_idx] = 16'd1;
      end else if (case_entry_idx >= 0) begin
        case_pkt_count_mem[case_entry_idx] = case_pkt_count_mem[case_entry_idx] + 16'd1;
      end
    end
  end

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      read_ptr           <= '0;
      slot_ctr           <= '0;
      current_case_id    <= '0;
      current_case_index <= '0;
      current_case_valid <= 1'b0;
      end_seen           <= 1'b0;
      issue_valid_r      <= '0;
      report_q_wr_ptr    <= '0;
      report_q_rd_ptr    <= '0;
      report_q_count     <= '0;
      case_meta_valid    <= 1'b0;
      case_meta_id       <= '0;
      case_meta_pkt_total<= '0;
      for (idx = 0; idx < MAX_CONCURRENT_PKT; idx++) begin
        issue_pkt_r[idx] <= '0;
      end
      for (idx = 0; idx < CASE_MEM_DEPTH; idx++) begin
        report_queue[idx] <= '0;
      end
    end else begin
      logic [MAX_CONCURRENT_PKT-1:0] slot_free;
      logic [15:0]                   read_ptr_next;
      logic [15:0]                   case_id_eff;
      logic [15:0]                   case_index_eff;
      logic [15:0]                   slot_ctr_eff;
      logic                          case_valid_eff;
      logic                          end_seen_next;
      logic                          current_case_done_now;
      logic                          same_case_busy;
      logic [CASE_MEM_LINE_W-1:0]    raw_next;
      pkt_desc_t                     desc_next;
      report_event_t                 case_start_evt;
      int                            free_slot;
      int                            q_wr_tmp;
      int                            q_count_tmp;

      case_meta_valid <= 1'b0;
      q_wr_tmp    = report_q_wr_ptr;
      q_count_tmp = report_q_count;

      if ((report_q_count != 0) && report_ready) begin
        report_q_rd_ptr <= (report_q_rd_ptr == CASE_MEM_DEPTH-1) ? '0 : (report_q_rd_ptr + 1'b1);
        q_count_tmp = q_count_tmp - 1;
      end

      for (idx = 0; idx < MAX_CONCURRENT_PKT; idx++) begin
        if (issue_valid_r[idx] && issue_ready[idx]) begin
          issue_valid_r[idx] <= 1'b0;
        end
        slot_free[idx] = !issue_valid_r[idx] || issue_ready[idx];
      end

      read_ptr_next  = read_ptr;
      case_id_eff    = current_case_id;
      case_index_eff = current_case_index;
      slot_ctr_eff   = slot_ctr;
      case_valid_eff = current_case_valid;
      end_seen_next  = end_seen;
      current_case_done_now = case_done_valid && current_case_valid && (case_done_id == current_case_id);

      if (!end_seen_next) begin
        raw_next = case_mem[read_ptr_next];
        if (raw_is_end_marker(raw_next)) begin
        end_seen_next = 1'b1;
        end else begin
          desc_next = unpack_pkt_desc(raw_next);

          if (!case_valid_eff) begin
            case_id_eff    = desc_next.case_id;
            case_index_eff = '0;
            case_valid_eff = 1'b1;
            slot_ctr_eff   = '0;
            case_meta_valid     <= 1'b1;
            case_meta_id        <= desc_next.case_id;
            case_meta_pkt_total <= case_pkt_count_by_id[desc_next.case_id];
            case_start_evt            = '0;
            case_start_evt.event_type = EVT_CASE_START;
            case_start_evt.case_id    = desc_next.case_id;
            case_start_evt.pkt_total  = case_pkt_count_by_id[desc_next.case_id];
            if (q_count_tmp < CASE_MEM_DEPTH) begin
              report_queue[q_wr_tmp] <= case_start_evt;
              q_wr_tmp = (q_wr_tmp == CASE_MEM_DEPTH-1) ? 0 : (q_wr_tmp + 1);
              q_count_tmp = q_count_tmp + 1;
            end
          end

          same_case_busy = 1'b0;
          for (idx = 0; idx < MAX_CONCURRENT_PKT; idx++) begin
            if (!slot_free[idx] && (issue_pkt_r[idx].case_id == case_id_eff)) begin
              same_case_busy = 1'b1;
            end
          end

          if (case_valid_eff && (desc_next.case_id != case_id_eff) && !same_case_busy && current_case_done_now) begin
            case_id_eff    = desc_next.case_id;
            case_index_eff = case_index_eff + 16'd1;
            slot_ctr_eff   = '0;
            case_meta_valid     <= 1'b1;
            case_meta_id        <= desc_next.case_id;
            case_meta_pkt_total <= case_pkt_count_by_id[desc_next.case_id];
            case_start_evt            = '0;
            case_start_evt.event_type = EVT_CASE_START;
            case_start_evt.case_id    = desc_next.case_id;
            case_start_evt.pkt_total  = case_pkt_count_by_id[desc_next.case_id];
            if (q_count_tmp < CASE_MEM_DEPTH) begin
              report_queue[q_wr_tmp] <= case_start_evt;
              q_wr_tmp = (q_wr_tmp == CASE_MEM_DEPTH-1) ? 0 : (q_wr_tmp + 1);
              q_count_tmp = q_count_tmp + 1;
            end
          end

          while (!end_seen_next) begin
            raw_next = case_mem[read_ptr_next];
            if (raw_is_end_marker(raw_next)) begin
              end_seen_next = 1'b1;
            end else begin
              desc_next = unpack_pkt_desc(raw_next);
              if ((desc_next.case_id != case_id_eff) || (desc_next.start_slot > slot_ctr_eff)) begin
                break;
              end

              free_slot = -1;
              for (idx = 0; idx < MAX_CONCURRENT_PKT; idx++) begin
                if ((free_slot < 0) && slot_free[idx]) begin
                  free_slot = idx;
                end
              end
              if (free_slot < 0) begin
                break;
              end

              issue_pkt_r[free_slot]   <= desc_next;
              issue_valid_r[free_slot] <= 1'b1;
              slot_free[free_slot]     = 1'b0;
              read_ptr_next            = read_ptr_next + 16'd1;
            end
          end
        end
      end

      read_ptr           <= read_ptr_next;
      end_seen           <= end_seen_next;
      report_q_wr_ptr    <= q_wr_tmp[REPORT_Q_PTR_W-1:0];
      report_q_count     <= q_count_tmp[REPORT_Q_CNT_W-1:0];
      current_case_id    <= case_id_eff;
      current_case_index <= case_index_eff;
      current_case_valid <= case_valid_eff;

      if (case_valid_eff && !end_seen_next) begin
        slot_ctr <= slot_ctr_eff + 16'd1;
      end else begin
        slot_ctr <= slot_ctr_eff;
      end
    end
  end

  assign issue_pkt    = issue_pkt_r;
  assign issue_valid  = issue_valid_r;
  assign report_event = report_queue[report_q_rd_ptr];
  assign report_valid = (report_q_count != 0);
  assign case_total   = case_total_r;
  assign pkt_total    = pkt_total_r;
  assign all_done     = end_seen && (issue_valid_r == '0);
endmodule
