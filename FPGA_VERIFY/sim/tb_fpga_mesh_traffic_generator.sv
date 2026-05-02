`timescale 1ns/1ps

module tb_fpga_mesh_traffic_generator;
  import noc_params::*;
  import fpga_verify_pkg::*;

  localparam int ROUTER_NUM = POS_NUM * POS_NUM;

  logic CLK;
  logic RSTn;
  pkt_desc_t issue_pkt [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0] issue_valid;
  logic [MAX_CONCURRENT_PKT-1:0] issue_ready;
  pkt_desc_t inject_pkt [MAX_CONCURRENT_PKT];
  logic [MAX_CONCURRENT_PKT-1:0] inject_valid;
  logic [MAX_CONCURRENT_PKT-1:0][LATENCY_W-1:0] inject_cycle;
  logic [MAX_CONCURRENT_PKT-1:0] inject_ready;
  report_event_t report_event;
  logic report_valid;
  logic report_ready;
  router_vc_flit_if pe_if [ROUTER_NUM-1:0]();

  int src0_seen;
  int src1_seen;

  fpga_mesh_traffic_generator dut (
    .CLK(CLK),
    .RSTn(RSTn),
    .issue_pkt(issue_pkt),
    .issue_valid(issue_valid),
    .issue_ready(issue_ready),
    .inject_pkt(inject_pkt),
    .inject_valid(inject_valid),
    .inject_cycle(inject_cycle),
    .inject_ready(inject_ready),
    .report_event(report_event),
    .report_valid(report_valid),
    .report_ready(report_ready),
    .PE_IFLIT(pe_if)
  );

  function automatic pkt_desc_t make_pkt(
    input int case_id,
    input int pkt_id,
    input int src_rid,
    input int dst_rid,
    input int msg_class,
    input int vc_id,
    input int pkt_len,
    input logic [31:0] f0,
    input logic [31:0] f1,
    input logic [31:0] f2
  );
    pkt_desc_t pkt;
    pkt = '0;
    pkt.case_id = case_id;
    pkt.pkt_id = pkt_id;
    pkt.src_rid = src_rid;
    pkt.dst_rid = dst_rid;
    pkt.msg_class = msg_class;
    pkt.vc_id = vc_id[VC_PRT_SIZE-1:0];
    pkt.pkt_len = pkt_len;
    pkt.timeout_cycles = 16'd32;
    pkt.flits_flat = {128'd0, f2, f1, f0};
    return pkt;
  endfunction

  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  genvar gi;
  generate
    for (gi = 0; gi < ROUTER_NUM; gi++) begin : GEN_READY
      initial begin
        pe_if[gi].ready = 1'b0;
        pe_if[gi].credit_return = '0;
      end
    end
  endgenerate

  task automatic pulse_ready_0();
    begin
      pe_if[0].ready = 1'b1;
      @(posedge CLK);
      pe_if[0].ready = 1'b0;
      @(negedge CLK);
    end
  endtask

  task automatic pulse_ready_1();
    begin
      pe_if[1].ready = 1'b1;
      @(posedge CLK);
      pe_if[1].ready = 1'b0;
      @(negedge CLK);
    end
  endtask

  initial begin
    issue_valid = '0;
    issue_pkt   = '{default:'0};
    inject_ready = '1;
    report_ready = 1'b1;
    src0_seen   = 0;
    src1_seen   = 0;
    RSTn        = 1'b0;
    repeat (4) @(posedge CLK);
    RSTn = 1'b1;
    @(negedge CLK);

    issue_pkt[0] = make_pkt(0, 'h0100, 0, 1, REQ, 0, 3, 32'hAAA0_0000, 32'hAAA0_0001, 32'hAAA0_0002);
    issue_pkt[1] = make_pkt(0, 'h0101, 1, 2, RESP, 2, 1, 32'hBBB0_0000, 32'h0, 32'h0);
    issue_pkt[2] = make_pkt(0, 'h0102, 0, 2, REQ, 1, 1, 32'hCCC0_0000, 32'h0, 32'h0);
    issue_valid[0] = 1'b1;
    issue_valid[1] = 1'b1;
    issue_valid[2] = 1'b1;

    @(posedge CLK);
    #1;
    $display(
      "[ENG] v=%b pkt0=0x%0h pkt1=0x%0h pkt2=0x%0h pkt3=0x%0h",
      dut.active_valid,
      dut.active_desc[0].pkt_id,
      dut.active_desc[1].pkt_id,
      dut.active_desc[2].pkt_id,
      dut.active_desc[3].pkt_id
    );
    if (dut.active_valid !== 4'b0011) begin
      $error("first two packets were not captured into active slots");
      $fatal;
    end
    if ((dut.active_desc[0].pkt_id != 'h0100) || (dut.active_desc[1].pkt_id != 'h0101)) begin
      $error("active slot assignment mismatch after first accept");
      $fatal;
    end
    issue_valid[0] = 1'b0;
    issue_valid[1] = 1'b0;

    @(negedge CLK);
    if (!pe_if[0].valid || !pe_if[1].valid) begin
      $error("both first packets should be presented before handshake");
      $fatal;
    end
    if ((pe_if[0].flit_data !== 32'hAAA0_0000) || !pe_if[0].is_head || pe_if[0].is_tail) begin
      $error("src0 first beat presentation mismatch");
      $fatal;
    end
    if ((pe_if[1].flit_data !== 32'hBBB0_0000) || !pe_if[1].is_head || !pe_if[1].is_tail) begin
      $error("src1 first beat presentation mismatch");
      $fatal;
    end

    fork
      pulse_ready_0();
      pulse_ready_1();
    join

    if (src0_seen != 1 || src1_seen != 1) begin
      $error("first handshake count mismatch");
      $fatal;
    end

    if ((pe_if[0].flit_data !== 32'hAAA0_0001) || pe_if[0].is_head || pe_if[0].is_tail) begin
      $error("src0 body beat presentation mismatch");
      $fatal;
    end

    // Keep ready low for one full cycle and confirm the body beat does not advance.
    @(posedge CLK);
    @(negedge CLK);
    if (pe_if[0].flit_data !== 32'hAAA0_0001) begin
      $error("generator advanced during backpressure");
      $fatal;
    end

    pulse_ready_0();
    if (src0_seen != 2) begin
      $error("src0 body beat handshake mismatch");
      $fatal;
    end

    if ((pe_if[0].flit_data !== 32'hAAA0_0002) || pe_if[0].is_head || !pe_if[0].is_tail) begin
      $error("src0 tail beat presentation mismatch");
      $fatal;
    end

    pulse_ready_0();
    if (src0_seen != 3) begin
      $error("src0 tail beat handshake mismatch");
      $fatal;
    end

    wait(issue_ready[2] == 1'b1);
    @(posedge CLK);
    #1;
    issue_valid[2] = 1'b0;

    wait(pe_if[0].valid == 1'b1);
    @(negedge CLK);
    if ((pe_if[0].flit_data !== 32'hCCC0_0000) || !pe_if[0].is_head || !pe_if[0].is_tail) begin
      $error("src0 second packet presentation mismatch");
      $fatal;
    end
    pulse_ready_0();
    wait(src0_seen == 4);
    repeat (2) @(posedge CLK);
    $display("tb_fpga_mesh_traffic_generator: PASS");
    $finish;
  end

  always @(negedge CLK) begin
    if (RSTn) begin
      if (pe_if[0].valid && pe_if[0].ready) begin
        $display(
          "[SRC0] t=%0t seen=%0d data=0x%08h H=%0b T=%0b",
          $time,
          src0_seen,
          pe_if[0].flit_data,
          pe_if[0].is_head,
          pe_if[0].is_tail
        );
        case (src0_seen)
          0: begin
            if (!pe_if[0].is_head || pe_if[0].is_tail || (pe_if[0].flit_data !== 32'hAAA0_0000)) begin
              $error("src0 beat0 mismatch");
              $fatal;
            end
          end
          1: begin
            if (pe_if[0].is_head || pe_if[0].is_tail || (pe_if[0].flit_data !== 32'hAAA0_0001)) begin
              $error("src0 beat1 mismatch");
              $fatal;
            end
          end
          2: begin
            if (pe_if[0].is_head || !pe_if[0].is_tail || (pe_if[0].flit_data !== 32'hAAA0_0002)) begin
              $error("src0 beat2 mismatch");
              $fatal;
            end
          end
          3: begin
            if (!pe_if[0].is_head || !pe_if[0].is_tail || (pe_if[0].flit_data !== 32'hCCC0_0000)) begin
              $error("src0 second packet mismatch");
              $fatal;
            end
          end
          default: begin
            $error("unexpected extra src0 beat");
            $fatal;
          end
        endcase
        src0_seen <= src0_seen + 1;
      end

      if (pe_if[1].valid && pe_if[1].ready) begin
        $display(
          "[SRC1] t=%0t seen=%0d data=0x%08h H=%0b T=%0b",
          $time,
          src1_seen,
          pe_if[1].flit_data,
          pe_if[1].is_head,
          pe_if[1].is_tail
        );
        if ((src1_seen != 0) || !pe_if[1].is_head || !pe_if[1].is_tail || (pe_if[1].flit_data !== 32'hBBB0_0000)) begin
          $error("src1 packet mismatch");
          $fatal;
        end
        src1_seen <= src1_seen + 1;
      end
    end
  end

  initial begin
    repeat (200) @(posedge CLK);
    $error("timeout waiting for generator test completion");
    $fatal;
  end
endmodule
