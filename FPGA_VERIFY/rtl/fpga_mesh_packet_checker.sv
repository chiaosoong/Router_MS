module fpga_mesh_packet_checker #(
  parameter int TRACK_DEPTH = 32
) (
  input  logic                                        CLK,
  input  logic                                        RSTn,
  input  fpga_verify_pkg::pkt_desc_t                  inject_pkt [fpga_verify_pkg::MAX_CONCURRENT_PKT],
  input  logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0] inject_valid,
  input  logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0][fpga_verify_pkg::LATENCY_W-1:0] inject_cycle,
  output logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0] inject_ready,
  router_vc_flit_if.rx                                PE_OFLIT [noc_params::POS_NUM*noc_params::POS_NUM-1:0],
  output fpga_verify_pkg::report_event_t              report_event,
  output logic                                        report_valid,
  input  logic                                        report_ready
);
  import noc_params::*;
  import fpga_verify_pkg::*;

  localparam int ROUTER_NUM = POS_NUM * POS_NUM;

  pkt_state_t active_pkt [TRACK_DEPTH];
  logic [LATENCY_W-1:0] cycle_ctr;
  logic [ROUTER_NUM-1:0]                  pe_valid_mon;
  logic [ROUTER_NUM-1:0][DATA_WIDTH-1:0]  pe_data_mon;
  logic [ROUTER_NUM-1:0]                  pe_head_mon;
  logic [ROUTER_NUM-1:0]                  pe_tail_mon;
  logic [ROUTER_NUM-1:0][VC_PRT_SIZE-1:0] pe_vc_mon;

  report_event_t pending_event [TRACK_DEPTH];
  logic [TRACK_DEPTH-1:0] pending_valid;
  logic [MAX_CONCURRENT_PKT-1:0] inject_consumed;
  logic [$clog2(TRACK_DEPTH)-1:0] pending_sel;
  logic pending_any;

  function automatic int rid_from_xy(input logic [3:0] x, input logic [3:0] y);
    rid_from_xy = (y * POS_NUM) + x;
  endfunction

  task automatic build_report(
    output report_event_t event_o,
    input fpga_event_t    event_type_i,
    input pkt_state_t     state_i,
    input fpga_error_t    error_i,
    input logic [LATENCY_W-1:0] latency_i
  );
    begin
      event_o = '0;
      event_o.event_type = event_type_i;
      event_o.case_id    = state_i.desc.case_id;
      event_o.pkt_id     = state_i.desc.pkt_id;
      event_o.src_rid    = state_i.desc.src_rid;
      event_o.dst_rid    = state_i.desc.dst_rid;
      event_o.msg_class  = state_i.desc.msg_class;
      event_o.vc_id      = state_i.desc.vc_id;
      event_o.pkt_len    = state_i.desc.pkt_len;
      event_o.latency    = latency_i;
      event_o.error_code = error_i;
    end
  endtask

  always_comb begin
    int pend_idx;
    pending_any = 1'b0;
    pending_sel = '0;
    for (pend_idx = 0; pend_idx < TRACK_DEPTH; pend_idx++) begin
      if (!pending_any && pending_valid[pend_idx]) begin
        pending_any = 1'b1;
        pending_sel = pend_idx[$clog2(TRACK_DEPTH)-1:0];
      end
    end
  end

  genvar gi;
  generate
    for (gi = 0; gi < ROUTER_NUM; gi++) begin : GEN_SINK_FLOW_CTRL
      assign PE_OFLIT[gi].ready = 1'b1;
      assign PE_OFLIT[gi].credit_return =
        (PE_OFLIT[gi].valid && PE_OFLIT[gi].ready) ? (logic'(1'b1) << PE_OFLIT[gi].vc_id) : '0;
      assign pe_valid_mon[gi] = PE_OFLIT[gi].valid;
      assign pe_data_mon[gi]  = PE_OFLIT[gi].flit_data;
      assign pe_head_mon[gi]  = PE_OFLIT[gi].is_head;
      assign pe_tail_mon[gi]  = PE_OFLIT[gi].is_tail;
      assign pe_vc_mon[gi]    = PE_OFLIT[gi].vc_id;
    end
  endgenerate

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      int idx;
      cycle_ctr <= '0;
      pending_valid <= '0;
      inject_ready  <= '0;
      inject_consumed <= '0;
      for (idx = 0; idx < TRACK_DEPTH; idx++) begin
        active_pkt[idx] <= '0;
        pending_event[idx] <= '0;
      end
    end else begin
      int inj_idx;
      int free_idx;
      int rid;
      int match_idx;
      int pend_free_idx;
      logic [TRACK_DEPTH-1:0] active_taken_mask;
      logic [TRACK_DEPTH-1:0] pending_taken_mask;
      logic [3:0] dstx;
      logic [3:0] dsty;
      logic [3:0] srcx;
      logic [3:0] srcy;
      logic [7:0] got_seq;
      logic [7:0] got_len;
      logic [2:0] got_class;
      logic       got_head;
      logic       got_tail;
      logic [LATENCY_W-1:0] latency_now;

      cycle_ctr <= cycle_ctr + LATENCY_W'(1);
      inject_ready <= '0;
      active_taken_mask  = '0;
      pending_taken_mask = pending_valid;
      for (rid = 0; rid < TRACK_DEPTH; rid++) begin
        active_taken_mask[rid] = active_pkt[rid].valid;
      end

      if (report_valid && report_ready) begin
        pending_valid[pending_sel] <= 1'b0;
        pending_taken_mask[pending_sel] = 1'b0;
      end

      for (inj_idx = 0; inj_idx < MAX_CONCURRENT_PKT; inj_idx++) begin
        if (!inject_valid[inj_idx]) begin
          inject_consumed[inj_idx] <= 1'b0;
        end else if (!inject_consumed[inj_idx]) begin
          free_idx = -1;
          for (rid = 0; rid < TRACK_DEPTH; rid++) begin
            if ((free_idx < 0) && !active_taken_mask[rid]) begin
              free_idx = rid;
            end
          end

          if (free_idx >= 0) begin
            active_pkt[free_idx].valid        <= 1'b1;
            active_pkt[free_idx].desc         <= inject_pkt[inj_idx];
            active_pkt[free_idx].inject_cycle <= inject_cycle[inj_idx];
            active_pkt[free_idx].expected_seq <= 8'd0;
            active_pkt[free_idx].seen_head    <= 1'b0;
            active_pkt[free_idx].pass         <= 1'b0;
            active_pkt[free_idx].fail         <= 1'b0;
            active_pkt[free_idx].error_code   <= ERR_PASS;
            active_pkt[free_idx].latency      <= '0;
            active_pkt[free_idx].finish_cycle <= '0;
            active_taken_mask[free_idx]       = 1'b1;
            inject_ready[inj_idx]             <= 1'b1;
            inject_consumed[inj_idx]          <= 1'b1;
          end else begin
            pend_free_idx = -1;
            for (rid = 0; rid < TRACK_DEPTH; rid++) begin
              if ((pend_free_idx < 0) && !pending_taken_mask[rid]) begin
                pend_free_idx = rid;
              end
            end
            if (pend_free_idx >= 0) begin
              pkt_state_t tmp_state;
              tmp_state = '0;
              tmp_state.desc = inject_pkt[inj_idx];
              build_report(pending_event[pend_free_idx], EVT_PKT_FAIL, tmp_state, ERR_INTERNAL_OVF, '0);
              pending_valid[pend_free_idx] <= 1'b1;
              pending_taken_mask[pend_free_idx] = 1'b1;
              inject_ready[inj_idx]         <= 1'b1;
              inject_consumed[inj_idx]      <= 1'b1;
            end
          end
        end
      end

      for (rid = 0; rid < ROUTER_NUM; rid++) begin
        if (pe_valid_mon[rid]) begin
          dstx      = pe_data_mon[rid][31:28];
          dsty      = pe_data_mon[rid][27:24];
          srcx      = pe_data_mon[rid][23:20];
          srcy      = pe_data_mon[rid][19:16];
          got_seq   = pe_data_mon[rid][9:5];
          got_len   = pe_data_mon[rid][13:10];
          got_class = (pe_data_mon[rid][2:0] == RESP) ? RESP : REQ;
          got_head  = pe_head_mon[rid];
          got_tail  = pe_tail_mon[rid];

          match_idx = -1;
          for (inj_idx = 0; inj_idx < TRACK_DEPTH; inj_idx++) begin
            if (active_pkt[inj_idx].valid &&
                (active_pkt[inj_idx].desc.dst_rid == rid) &&
                (active_pkt[inj_idx].desc.src_rid == rid_from_xy(srcx, srcy)) &&
                (active_pkt[inj_idx].desc.msg_class == got_class) &&
                (active_pkt[inj_idx].desc.pkt_len == got_len)) begin
              match_idx = inj_idx;
            end
          end

          if (match_idx >= 0) begin
            fpga_error_t err_code;

            err_code = ERR_PASS;

            if (rid_from_xy(dstx, dsty) != rid) begin
              err_code = ERR_DST_MISMATCH;
            end else if (got_seq != active_pkt[match_idx].expected_seq) begin
              err_code = ERR_SEQ_MISMATCH;
            end else if ((active_pkt[match_idx].expected_seq == 0) && !got_head) begin
              err_code = ERR_TYPE_MISMATCH;
            end else if ((active_pkt[match_idx].expected_seq != 0) &&
                         (active_pkt[match_idx].expected_seq != (active_pkt[match_idx].desc.pkt_len - 1)) &&
                         (got_head || got_tail)) begin
              err_code = ERR_TYPE_MISMATCH;
            end else if ((active_pkt[match_idx].expected_seq == (active_pkt[match_idx].desc.pkt_len - 1)) && !got_tail) begin
              err_code = ERR_TYPE_MISMATCH;
            end

            if (err_code != ERR_PASS) begin
              if (!pending_valid[match_idx]) begin
                build_report(pending_event[match_idx], EVT_PKT_FAIL, active_pkt[match_idx], err_code, '0);
                pending_valid[match_idx] <= 1'b1;
              end
              active_pkt[match_idx].valid      <= 1'b0;
              active_pkt[match_idx].fail       <= 1'b1;
              active_pkt[match_idx].error_code <= err_code;
            end else if (got_tail) begin
              latency_now = cycle_ctr - active_pkt[match_idx].inject_cycle;
              if (!pending_valid[match_idx]) begin
                build_report(pending_event[match_idx], EVT_PKT_DONE, active_pkt[match_idx], ERR_PASS, latency_now);
                pending_valid[match_idx] <= 1'b1;
              end
              active_pkt[match_idx].valid        <= 1'b0;
              active_pkt[match_idx].pass         <= 1'b1;
              active_pkt[match_idx].latency      <= latency_now;
              active_pkt[match_idx].finish_cycle <= cycle_ctr;
            end else begin
              active_pkt[match_idx].expected_seq <= active_pkt[match_idx].expected_seq + 8'd1;
              if (got_head) begin
                active_pkt[match_idx].seen_head <= 1'b1;
              end
            end
          end
        end
      end

      for (inj_idx = 0; inj_idx < TRACK_DEPTH; inj_idx++) begin
        if (active_pkt[inj_idx].valid &&
            ((cycle_ctr - active_pkt[inj_idx].inject_cycle) > active_pkt[inj_idx].desc.timeout_cycles)) begin
          if (!pending_valid[inj_idx]) begin
            build_report(pending_event[inj_idx], EVT_PKT_FAIL, active_pkt[inj_idx], ERR_TIMEOUT, '0);
            pending_valid[inj_idx] <= 1'b1;
          end
          active_pkt[inj_idx].valid      <= 1'b0;
          active_pkt[inj_idx].fail       <= 1'b1;
          active_pkt[inj_idx].error_code <= ERR_TIMEOUT;
        end
      end
    end
  end

  assign report_event = pending_event[pending_sel];
  assign report_valid = pending_any;
endmodule
