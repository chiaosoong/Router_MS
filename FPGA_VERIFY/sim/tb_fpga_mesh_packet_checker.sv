`timescale 1ns/1ps

module tb_fpga_mesh_packet_checker;
  import noc_params::*;
  import fpga_verify_pkg::*;

  localparam int ROUTER_NUM = POS_NUM * POS_NUM;

  logic CLK;
  logic RSTn;
  pkt_desc_t inject_pkt [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0] inject_valid;
  logic [MAX_CONCURRENT_PKT-1:0][LATENCY_W-1:0] inject_cycle;
  logic [MAX_CONCURRENT_PKT-1:0] inject_ready;
  router_vc_flit_if pe_of [ROUTER_NUM-1:0]();
  report_event_t report_event;
  logic report_valid;
  logic report_ready;

  fpga_mesh_packet_checker dut (
    .CLK(CLK),
    .RSTn(RSTn),
    .inject_pkt(inject_pkt),
    .inject_valid(inject_valid),
    .inject_cycle(inject_cycle),
    .inject_ready(inject_ready),
    .PE_OFLIT(pe_of),
    .report_event(report_event),
    .report_valid(report_valid),
    .report_ready(report_ready)
  );

  function automatic pkt_desc_t make_pkt();
    pkt_desc_t pkt;
    pkt = '0;
    pkt.case_id = 16'd7;
    pkt.pkt_id = 16'h0200;
    pkt.src_rid = 8'd0;
    pkt.dst_rid = 8'd1;
    pkt.msg_class = REQ;
    pkt.vc_id = '0;
    pkt.pkt_len = 3;
    pkt.timeout_cycles = 16'd20;
    return pkt;
  endfunction

  function automatic logic [31:0] make_flit(
    input int dst_rid,
    input int src_rid,
    input int flit_type,
    input int pkt_len,
    input int seq,
    input int msg_class
  );
    logic [31:0] f;
    f = '0;
    f[31:28] = dst_rid % POS_NUM;
    f[27:24] = dst_rid / POS_NUM;
    f[23:20] = src_rid % POS_NUM;
    f[19:16] = src_rid / POS_NUM;
    f[15:14] = flit_type[1:0];
    f[13:10] = pkt_len[3:0];
    f[9:5]   = seq[4:0];
    f[2:0]   = msg_class[2:0];
    return f;
  endfunction

  task automatic drive_flit_r1(
    input logic [31:0] data,
    input logic is_head,
    input logic is_tail,
    input logic [VC_PRT_SIZE-1:0] vc
  );
    begin
      pe_of[1].flit_data = data;
      pe_of[1].is_head   = is_head;
      pe_of[1].is_tail   = is_tail;
      pe_of[1].vc_id     = vc;
      pe_of[1].valid     = 1'b1;
      @(posedge CLK);
      #1;
      pe_of[1].valid     = 1'b0;
      pe_of[1].flit_data = '0;
      pe_of[1].is_head   = 1'b0;
      pe_of[1].is_tail   = 1'b0;
      pe_of[1].vc_id     = '0;
    end
  endtask

  task automatic reset_dut();
    begin
      inject_pkt   = '{default:'0};
      inject_valid = '0;
      inject_cycle = '{default:'0};
      pe_of[1].valid     = 1'b0;
      pe_of[1].flit_data = '0;
      pe_of[1].is_head   = 1'b0;
      pe_of[1].is_tail   = 1'b0;
      pe_of[1].vc_id     = '0;
      RSTn = 1'b0;
      repeat (4) @(posedge CLK);
      RSTn = 1'b1;
      @(negedge CLK);
    end
  endtask

  task automatic inject_one_pkt(
    input int slot,
    input pkt_desc_t pkt,
    input logic [LATENCY_W-1:0] inj_cycle
  );
    begin
      inject_pkt[slot] = pkt;
      inject_valid[slot] = 1'b1;
      inject_cycle[slot] = inj_cycle;
      @(posedge CLK);
      @(negedge CLK);
      inject_valid[slot] = 1'b0;
      @(posedge CLK);
      #1;
    end
  endtask

  task automatic expect_report(
    input fpga_event_t exp_evt,
    input logic [15:0] exp_pkt_id,
    input fpga_error_t exp_err
  );
    begin
      wait(report_valid);
      #1;
      if (report_event.event_type != exp_evt) begin
        $error("unexpected event type: exp=%0d got=%0d", exp_evt, report_event.event_type);
        $fatal;
      end
      if (report_event.pkt_id != exp_pkt_id) begin
        $error("unexpected pkt_id: exp=0x%0h got=0x%0h", exp_pkt_id, report_event.pkt_id);
        $fatal;
      end
      if (report_event.error_code != exp_err) begin
        $error("unexpected error code: exp=%0d got=%0d", exp_err, report_event.error_code);
        $fatal;
      end
      @(posedge CLK);
      #1;
    end
  endtask

  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  genvar gi;
  generate
    for (gi = 0; gi < ROUTER_NUM; gi++) begin : GEN_PE_DRV
      initial begin
        pe_of[gi].valid = 1'b0;
        pe_of[gi].flit_data = '0;
        pe_of[gi].is_head = 1'b0;
        pe_of[gi].is_tail = 1'b0;
        pe_of[gi].vc_id = '0;
      end
    end
  endgenerate

  initial begin
    report_ready = 1'b1;
    reset_dut();
    inject_one_pkt(0, make_pkt(), 32'd0);
    drive_flit_r1(make_flit(1, 0, FLIT_HEAD, 3, 0, REQ), 1'b1, 1'b0, '0);
    drive_flit_r1(make_flit(1, 0, FLIT_BODY, 3, 1, REQ), 1'b0, 1'b0, '0);
    drive_flit_r1(make_flit(1, 0, FLIT_TAIL, 3, 2, REQ), 1'b0, 1'b1, '0);
    expect_report(EVT_PKT_DONE, 16'h0200, ERR_PASS);
    if (report_event.latency == 32'd0) begin
      $error("latency should be non-zero");
      $fatal;
    end
    if (!dut.active_pkt[0].pass) begin
      $error("checker did not mark packet as pass");
      $fatal;
    end

    reset_dut();
    inject_one_pkt(0, make_pkt(), 32'd0);
    expect_report(EVT_PKT_FAIL, 16'h0200, ERR_TIMEOUT);

    reset_dut();
    inject_one_pkt(0, make_pkt(), 32'd0);
    drive_flit_r1(make_flit(1, 0, FLIT_HEAD, 3, 0, REQ), 1'b1, 1'b0, '0);
    drive_flit_r1(make_flit(1, 0, FLIT_BODY, 3, 2, REQ), 1'b0, 1'b0, '0);
    expect_report(EVT_PKT_FAIL, 16'h0200, ERR_SEQ_MISMATCH);

    reset_dut();
    inject_one_pkt(0, make_pkt(), 32'd0);
    drive_flit_r1(make_flit(2, 0, FLIT_HEAD, 3, 0, REQ), 1'b1, 1'b0, '0);
    expect_report(EVT_PKT_FAIL, 16'h0200, ERR_DST_MISMATCH);

    $display("tb_fpga_mesh_packet_checker: PASS");
    $finish;
  end

  initial begin
    repeat (200) @(posedge CLK);
    $error("timeout waiting for checker test completion");
    $fatal;
  end
endmodule
