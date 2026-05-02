module fpga_mesh_traffic_generator (
  input  logic                                        CLK,
  input  logic                                        RSTn,
  input  fpga_verify_pkg::pkt_desc_t                  issue_pkt [fpga_verify_pkg::MAX_CONCURRENT_PKT],
  input  logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0] issue_valid,
  output logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0] issue_ready,
  output fpga_verify_pkg::pkt_desc_t                  inject_pkt [fpga_verify_pkg::MAX_CONCURRENT_PKT],
  output logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0] inject_valid,
  output logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0][fpga_verify_pkg::LATENCY_W-1:0] inject_cycle,
  input  logic [fpga_verify_pkg::MAX_CONCURRENT_PKT-1:0] inject_ready,
  output fpga_verify_pkg::report_event_t              report_event,
  output logic                                        report_valid,
  input  logic                                        report_ready,
  router_vc_flit_if.tx                                PE_IFLIT [noc_params::POS_NUM*noc_params::POS_NUM-1:0]
);
  import noc_params::*;
  import fpga_verify_pkg::*;

  localparam int ROUTER_NUM = POS_NUM * POS_NUM;

  pkt_desc_t active_desc [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0] active_valid;
  logic [7:0] active_beat [MAX_CONCURRENT_PKT];

  logic [MAX_CONCURRENT_PKT-1:0] issue_ready_c;
  logic [MAX_CONCURRENT_PKT-1:0][$clog2(MAX_CONCURRENT_PKT)-1:0] issue_engine_sel;

  logic [ROUTER_NUM-1:0]                 pe_valid_c;
  logic [ROUTER_NUM-1:0][DATA_WIDTH-1:0] pe_flit_c;
  logic [ROUTER_NUM-1:0]                 pe_head_c;
  logic [ROUTER_NUM-1:0]                 pe_tail_c;
  logic [ROUTER_NUM-1:0][VC_PRT_SIZE-1:0] pe_vc_c;
  logic [ROUTER_NUM-1:0]                 pe_ready_mon;
  logic [LATENCY_W-1:0]                  cycle_ctr;

  report_event_t                    pending_event [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0]    pending_valid;
  logic [$clog2(MAX_CONCURRENT_PKT)-1:0] pending_sel;
  logic                             pending_any;

  task automatic build_inj_event(
    output report_event_t event_o,
    input pkt_desc_t      pkt_i,
    input logic [LATENCY_W-1:0] cycle_i
  );
    begin
      event_o = '0;
      event_o.event_type = EVT_PKT_INJ;
      event_o.case_id    = pkt_i.case_id;
      event_o.pkt_id     = pkt_i.pkt_id;
      event_o.src_rid    = pkt_i.src_rid;
      event_o.dst_rid    = pkt_i.dst_rid;
      event_o.msg_class  = pkt_i.msg_class;
      event_o.vc_id      = pkt_i.vc_id;
      event_o.pkt_len    = pkt_i.pkt_len;
      event_o.latency    = cycle_i;
    end
  endtask

  always_comb begin
    logic [MAX_CONCURRENT_PKT-1:0] engine_taken;
    logic [ROUTER_NUM-1:0]         src_busy;
    int                            chosen_engine;
    int                            eng_alloc;
    int                            slot_alloc;

    issue_ready_c   = '0;
    issue_engine_sel = '0;

    engine_taken = active_valid | inject_valid;
    src_busy     = '0;
    for (eng_alloc = 0; eng_alloc < MAX_CONCURRENT_PKT; eng_alloc++) begin
      if (active_valid[eng_alloc]) begin
        src_busy[active_desc[eng_alloc].src_rid] = 1'b1;
      end
    end

    for (slot_alloc = 0; slot_alloc < MAX_CONCURRENT_PKT; slot_alloc++) begin
      chosen_engine = -1;
      if (issue_valid[slot_alloc] && !src_busy[issue_pkt[slot_alloc].src_rid]) begin
        for (eng_alloc = 0; eng_alloc < MAX_CONCURRENT_PKT; eng_alloc++) begin
          if ((chosen_engine < 0) && !engine_taken[eng_alloc]) begin
            chosen_engine = eng_alloc;
          end
        end
      end

      if (chosen_engine >= 0) begin
        issue_ready_c[slot_alloc]                = 1'b1;
        issue_engine_sel[slot_alloc]             = chosen_engine[$clog2(MAX_CONCURRENT_PKT)-1:0];
        engine_taken[chosen_engine]              = 1'b1;
        src_busy[issue_pkt[slot_alloc].src_rid]  = 1'b1;
      end
    end
  end

  always_comb begin
    int eng_drive;
    int src_drive;

    pe_valid_c = '0;
    pe_flit_c  = '0;
    pe_head_c  = '0;
    pe_tail_c  = '0;
    pe_vc_c    = '0;

    for (eng_drive = 0; eng_drive < MAX_CONCURRENT_PKT; eng_drive++) begin
      if (active_valid[eng_drive]) begin
        src_drive = active_desc[eng_drive].src_rid;
        pe_valid_c[src_drive] = 1'b1;
        pe_flit_c[src_drive]  = get_flit(active_desc[eng_drive], active_beat[eng_drive]);
        pe_head_c[src_drive]  = (active_beat[eng_drive] == 0);
        pe_tail_c[src_drive]  = (active_beat[eng_drive] == (active_desc[eng_drive].pkt_len - 1));
        pe_vc_c[src_drive]    = active_desc[eng_drive].vc_id;
      end
    end
  end

  always_comb begin
    int pend_idx;

    pending_any = 1'b0;
    pending_sel = '0;
    for (pend_idx = 0; pend_idx < MAX_CONCURRENT_PKT; pend_idx++) begin
      if (!pending_any && pending_valid[pend_idx]) begin
        pending_any = 1'b1;
        pending_sel = pend_idx[$clog2(MAX_CONCURRENT_PKT)-1:0];
      end
    end
  end

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      int eng_rst;
      active_valid <= '0;
      inject_valid <= '0;
      cycle_ctr    <= '0;
      for (eng_rst = 0; eng_rst < MAX_CONCURRENT_PKT; eng_rst++) begin
        active_desc[eng_rst]  <= '0;
        active_beat[eng_rst]  <= '0;
        inject_pkt[eng_rst]   <= '0;
        inject_cycle[eng_rst] <= '0;
        pending_event[eng_rst] <= '0;
        pending_valid[eng_rst] <= 1'b0;
      end
    end else begin
      int eng_seq;
      int src_seq;
      int slot_seq;

      cycle_ctr    <= cycle_ctr + LATENCY_W'(1);

      if (report_valid && report_ready) begin
        pending_valid[pending_sel] <= 1'b0;
      end

      for (eng_seq = 0; eng_seq < MAX_CONCURRENT_PKT; eng_seq++) begin
        if (inject_valid[eng_seq] && inject_ready[eng_seq]) begin
          inject_valid[eng_seq] <= 1'b0;
        end
      end

      for (eng_seq = 0; eng_seq < MAX_CONCURRENT_PKT; eng_seq++) begin
        if (active_valid[eng_seq]) begin
          src_seq = active_desc[eng_seq].src_rid;
          if (pe_valid_c[src_seq] && pe_ready_mon[src_seq]) begin
            if (active_beat[eng_seq] == 0) begin
              if (!inject_valid[eng_seq]) begin
                inject_pkt[eng_seq]   <= active_desc[eng_seq];
                inject_valid[eng_seq] <= 1'b1;
                inject_cycle[eng_seq] <= cycle_ctr;
              end
              if (!pending_valid[eng_seq]) begin
                build_inj_event(pending_event[eng_seq], active_desc[eng_seq], cycle_ctr);
                pending_valid[eng_seq] <= 1'b1;
              end
            end

            if (active_beat[eng_seq] == (active_desc[eng_seq].pkt_len - 1)) begin
              active_valid[eng_seq] <= 1'b0;
              active_beat[eng_seq]  <= '0;
            end else begin
              active_beat[eng_seq] <= active_beat[eng_seq] + 8'd1;
            end
          end
        end
      end

      for (slot_seq = 0; slot_seq < MAX_CONCURRENT_PKT; slot_seq++) begin
        if (issue_valid[slot_seq] && issue_ready_c[slot_seq]) begin
          active_desc[issue_engine_sel[slot_seq]]  <= issue_pkt[slot_seq];
          active_valid[issue_engine_sel[slot_seq]] <= 1'b1;
          active_beat[issue_engine_sel[slot_seq]]  <= '0;
        end
      end
    end
  end

  assign issue_ready  = issue_ready_c;
  assign report_event = pending_event[pending_sel];
  assign report_valid = pending_any;

  genvar gi;
  generate
    for (gi = 0; gi < ROUTER_NUM; gi++) begin : GEN_PE_DRIVE
      assign PE_IFLIT[gi].valid     = pe_valid_c[gi];
      assign PE_IFLIT[gi].flit_data = pe_flit_c[gi];
      assign PE_IFLIT[gi].is_head   = pe_head_c[gi];
      assign PE_IFLIT[gi].is_tail   = pe_tail_c[gi];
      assign PE_IFLIT[gi].vc_id     = pe_vc_c[gi];
      assign pe_ready_mon[gi]       = PE_IFLIT[gi].ready;
    end
  endgenerate
endmodule
