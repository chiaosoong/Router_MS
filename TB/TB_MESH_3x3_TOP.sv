`timescale 1ns/1ps

import noc_params::*;

module TB_MESH_3x3_TOP;

  localparam int MESH_X = 3;
  localparam int MESH_Y = 3;
  localparam int ROUTER_NUM = MESH_X * MESH_Y;
  localparam int MAX_WAIT_CYC = 300;

  logic CLK;
  logic RSTn;

  router_vc_flit_if PE_IFLIT [ROUTER_NUM-1:0]();
  router_vc_flit_if PE_OFLIT [ROUTER_NUM-1:0]();

  // Use plain arrays in procedural code, then bridge to interface arrays
  // via generate-time constant indexing.
  logic [ROUTER_NUM-1:0]                    pe_if_valid_drv;
  logic [ROUTER_NUM-1:0][DATA_WIDTH-1:0]    pe_if_data_drv;
  logic [ROUTER_NUM-1:0]                    pe_if_head_drv;
  logic [ROUTER_NUM-1:0]                    pe_if_tail_drv;
  logic [ROUTER_NUM-1:0][VC_PRT_SIZE-1:0]   pe_if_vcid_drv;
  logic [ROUTER_NUM-1:0]                    pe_if_ready_mon;
  logic [ROUTER_NUM-1:0][VC_PER_PORT-1:0]   pe_if_credit_mon;

  logic [ROUTER_NUM-1:0]                    pe_of_ready_drv;
  logic [ROUTER_NUM-1:0][VC_PER_PORT-1:0]   pe_of_credit_drv;
  logic [ROUTER_NUM-1:0]                    pe_of_valid_mon;
  logic [ROUTER_NUM-1:0][DATA_WIDTH-1:0]    pe_of_data_mon;
  logic [ROUTER_NUM-1:0]                    pe_of_head_mon;
  logic [ROUTER_NUM-1:0]                    pe_of_tail_mon;
  logic [ROUTER_NUM-1:0][VC_PRT_SIZE-1:0]   pe_of_vcid_mon;

  MESH_3x3_TOP dut (
    .CLK     (CLK),
    .RSTn    (RSTn),
    .PE_IFLIT(PE_IFLIT),
    .PE_OFLIT(PE_OFLIT)
  );

  // Interface-array <-> plain-array bridge (constant indices only).
  genvar gi;
  generate
    for (gi = 0; gi < ROUTER_NUM; gi++) begin : GEN_TB_IF_BRIDGE
      // PE_IFLIT (rx at DUT side): TB drives payload/valid, monitors ready/credit
      assign PE_IFLIT[gi].valid     = pe_if_valid_drv[gi];
      assign PE_IFLIT[gi].flit_data = pe_if_data_drv[gi];
      assign PE_IFLIT[gi].is_head   = pe_if_head_drv[gi];
      assign PE_IFLIT[gi].is_tail   = pe_if_tail_drv[gi];
      assign PE_IFLIT[gi].vc_id     = pe_if_vcid_drv[gi];
      assign pe_if_ready_mon[gi]    = PE_IFLIT[gi].ready;
      assign pe_if_credit_mon[gi]   = PE_IFLIT[gi].credit_return;

      // PE_OFLIT (tx at DUT side): TB drives ready/credit, monitors payload/valid
      assign PE_OFLIT[gi].ready         = pe_of_ready_drv[gi];
      assign PE_OFLIT[gi].credit_return = pe_of_credit_drv[gi];
      assign pe_of_valid_mon[gi]        = PE_OFLIT[gi].valid;
      assign pe_of_data_mon[gi]         = PE_OFLIT[gi].flit_data;
      assign pe_of_head_mon[gi]         = PE_OFLIT[gi].is_head;
      assign pe_of_tail_mon[gi]         = PE_OFLIT[gi].is_tail;
      assign pe_of_vcid_mon[gi]         = PE_OFLIT[gi].vc_id;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Clock/reset
  // ---------------------------------------------------------------------------
  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  task automatic init_pe_drives();
    for (int i = 0; i < ROUTER_NUM; i++) begin
      // Injection side (PE -> mesh)
      pe_if_valid_drv[i] = 1'b0;
      pe_if_data_drv[i]  = '0;
      pe_if_head_drv[i]  = 1'b0;
      pe_if_tail_drv[i]  = 1'b0;
      pe_if_vcid_drv[i]  = '0;

      // Ejection side flow control (PE <- mesh)
      pe_of_ready_drv[i]  = 1'b1;
      pe_of_credit_drv[i] = '0;
    end
  endtask

  // Return one credit at LOCAL sink when one flit is consumed.
  always_comb begin
    for (int i = 0; i < ROUTER_NUM; i++) begin
      pe_of_credit_drv[i] = '0;
      if (pe_of_valid_mon[i] && pe_of_ready_drv[i]) begin
        pe_of_credit_drv[i][pe_of_vcid_mon[i]] = 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  function automatic int rid_x(input int rid);
    rid_x = rid % MESH_X;
  endfunction

  function automatic int rid_y(input int rid);
    rid_y = rid / MESH_X;
  endfunction

  function automatic int rid_xy(input int x, input int y);
    rid_xy = y * MESH_X + x;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] make_flit(
    input int src_rid,
    input int dst_rid,
    input int msg_id
  );
    logic [DATA_WIDTH-1:0] f;
    f = '0;
    // RCU_XY reads destination at [31:28] and [27:24].
    f[31:28] = rid_x(dst_rid);
    f[27:24] = rid_y(dst_rid);
    // Optional source tag for debug.
    f[23:20] = rid_x(src_rid);
    f[19:16] = rid_y(src_rid);
    // Message ID for matching at destination.
    f[15:14] = FLIT_HEADTAIL;
    f[13:10] = 4'd1;
    f[9:5]   = msg_id[4:0];
    f[4:3]   = 2'b00;
    f[2:0]   = REQ;
    make_flit = f;
  endfunction

  task automatic print_path_xy(input int src_rid, input int dst_rid);
    int x, y, dx, dy;
    x  = rid_x(src_rid);
    y  = rid_y(src_rid);
    dx = rid_x(dst_rid);
    dy = rid_y(dst_rid);

    $write("        path: R%0d(%0d,%0d)", src_rid, x, y);
    // XY: resolve X first.
    while (x < dx) begin
      x = x + 1;
      $write(" -> EAST -> R%0d(%0d,%0d)", rid_xy(x,y), x, y);
    end
    while (x > dx) begin
      x = x - 1;
      $write(" -> WEST -> R%0d(%0d,%0d)", rid_xy(x,y), x, y);
    end
    // Then Y.
    while (y < dy) begin
      y = y + 1;
      $write(" -> NORTH -> R%0d(%0d,%0d)", rid_xy(x,y), x, y);
    end
    while (y > dy) begin
      y = y - 1;
      $write(" -> SOUTH -> R%0d(%0d,%0d)", rid_xy(x,y), x, y);
    end
    $write("\n");
  endtask

  task automatic send_one_flit(
    input int src_rid,
    input logic [DATA_WIDTH-1:0] flit,
    input logic [VC_PRT_SIZE-1:0] vc
  );
    // Drive request.
    pe_if_data_drv[src_rid]  = flit;
    pe_if_head_drv[src_rid]  = 1'b1;
    pe_if_tail_drv[src_rid]  = 1'b1;
    pe_if_vcid_drv[src_rid]  = vc;
    pe_if_valid_drv[src_rid] = 1'b1;

    // Wait until a posedge where ready is high (handshake cycle).
    do begin
      @(posedge CLK);
    end while (!pe_if_ready_mon[src_rid]);
    // Deassert immediately after the accepted beat to avoid double-send.
    pe_if_valid_drv[src_rid] = 1'b0;
    pe_if_data_drv[src_rid]  = '0;
    pe_if_head_drv[src_rid]  = 1'b0;
    pe_if_tail_drv[src_rid]  = 1'b0;
    pe_if_vcid_drv[src_rid]  = '0;
  endtask

  task automatic send_one_beat(
    input int src_rid,
    input logic [DATA_WIDTH-1:0] flit,
    input logic [VC_PRT_SIZE-1:0] vc,
    input logic is_head,
    input logic is_tail
  );
    pe_if_data_drv[src_rid]  = flit;
    pe_if_head_drv[src_rid]  = is_head;
    pe_if_tail_drv[src_rid]  = is_tail;
    pe_if_vcid_drv[src_rid]  = vc;
    pe_if_valid_drv[src_rid] = 1'b1;

    do begin
      @(posedge CLK);
    end while (!pe_if_ready_mon[src_rid]);
    // Deassert immediately after the accepted beat to avoid double-send.
    pe_if_valid_drv[src_rid] = 1'b0;
    pe_if_data_drv[src_rid]  = '0;
    pe_if_head_drv[src_rid]  = 1'b0;
    pe_if_tail_drv[src_rid]  = 1'b0;
    pe_if_vcid_drv[src_rid]  = '0;
  endtask

  task automatic wait_recv_one_flit(
    input int dst_rid,
    input logic [DATA_WIDTH-1:0] exp_flit,
    input int msg_id
  );
    int cyc;
    cyc = 0;
    while (cyc < MAX_WAIT_CYC) begin
      @(posedge CLK);
      cyc++;
      if (pe_of_valid_mon[dst_rid] && pe_of_ready_drv[dst_rid] &&
          (pe_of_data_mon[dst_rid] == exp_flit)) begin
        $display("[RECV ] msg=%0d dst=R%0d vc=%0d latency<=%0dcy data=0x%08h t=%0t",
                 msg_id, dst_rid, pe_of_vcid_mon[dst_rid], cyc,
                 pe_of_data_mon[dst_rid], $time);
        return;
      end
    end
    $error("[TIMEOUT] msg=%0d dst=R%0d did not receive expected flit within %0d cycles",
           msg_id, dst_rid, MAX_WAIT_CYC);
    $fatal;
  endtask

  task automatic wait_recv_one_beat(
    input int dst_rid,
    input logic [DATA_WIDTH-1:0] exp_flit,
    input logic exp_head,
    input logic exp_tail,
    input int msg_id,
    input int beat_id
  );
    int cyc;
    cyc = 0;
    while (cyc < MAX_WAIT_CYC) begin
      @(posedge CLK);
      cyc++;
      if (pe_of_valid_mon[dst_rid] && pe_of_ready_drv[dst_rid] &&
          (pe_of_data_mon[dst_rid] == exp_flit) &&
          (pe_of_head_mon[dst_rid] == exp_head) &&
          (pe_of_tail_mon[dst_rid] == exp_tail)) begin
        $display("[RECVB] msg=%0d beat=%0d dst=R%0d vc=%0d H=%0b T=%0b latency<=%0dcy data=0x%08h t=%0t",
                 msg_id, beat_id, dst_rid, pe_of_vcid_mon[dst_rid],
                 pe_of_head_mon[dst_rid], pe_of_tail_mon[dst_rid], cyc,
                 pe_of_data_mon[dst_rid], $time);
        return;
      end
    end
    $error("[TIMEOUT] msg=%0d beat=%0d dst=R%0d did not receive expected beat within %0d cycles",
           msg_id, beat_id, dst_rid, MAX_WAIT_CYC);
    $fatal;
  endtask


  task automatic wait_recv_one_flit_strict(
    input int dst_rid,
    input int src_rid,
    input logic [1:0] exp_flit_type,
    input logic [3:0] exp_len,
    input msg_class_t exp_msg_class,
    input logic [4:0] exp_seq,
    input int msg_id,
    input int beat_id
  );
    int cyc;
    logic [DATA_WIDTH-1:0] d;
    logic [3:0] dstx, dsty, srcx, srcy;
    logic [1:0] flit_t;
    logic [3:0] len_f;
    logic [4:0] seq_f;
    logic [2:0] msg_f;

    cyc = 0;
    while (cyc < MAX_WAIT_CYC) begin
      @(posedge CLK);
      cyc++;
      if (pe_of_valid_mon[dst_rid] && pe_of_ready_drv[dst_rid]) begin
        d      = pe_of_data_mon[dst_rid];
        dstx   = d[31:28];
        dsty   = d[27:24];
        srcx   = d[23:20];
        srcy   = d[19:16];
        flit_t = d[15:14];
        len_f  = d[13:10];
        seq_f  = d[9:5];
        msg_f  = d[2:0];

        if ((dstx == rid_x(dst_rid)) &&
            (dsty == rid_y(dst_rid)) &&
            (srcx == rid_x(src_rid)) &&
            (srcy == rid_y(src_rid)) &&
            (flit_t == exp_flit_type) &&
            (len_f == exp_len) &&
            (seq_f == exp_seq) &&
            (msg_f == exp_msg_class)) begin
          $display("[RECVS] msg=%0d beat=%0d dst=R%0d src=R%0d vc=%0d type=%0d len=%0d seq=%0d class=%0d latency<=%0dcy data=0x%08h t=%0t",
                   msg_id, beat_id, dst_rid, src_rid, pe_of_vcid_mon[dst_rid],
                   flit_t, len_f, seq_f, msg_f, cyc, d, $time);
          return;
        end
      end
    end

    $error("[TIMEOUT] strict match fail: msg=%0d beat=%0d dst=R%0d src=R%0d type=%0d len=%0d seq=%0d class=%0d within %0d cycles",
           msg_id, beat_id, dst_rid, src_rid, exp_flit_type, exp_len, exp_seq, exp_msg_class, MAX_WAIT_CYC);
    $fatal;
  endtask

  task automatic wait_recv_one_beat_strict(
    input int dst_rid,
    input int src_rid,
    input int msg_id,
    input int beat_id,
    input int pkt_len,
    input msg_class_t msg_cls,
    input logic is_head,
    input logic is_tail
  );
    logic [1:0] t;

    if (is_head && is_tail) t = FLIT_HEADTAIL;
    else if (is_head) t = FLIT_HEAD;
    else if (is_tail) t = FLIT_TAIL;
    else t = FLIT_BODY;

    wait_recv_one_flit_strict(
      dst_rid,
      src_rid,
      t,
      pkt_len[3:0],
      msg_cls,
      beat_id[4:0],
      msg_id,
      beat_id
    );
  endtask
  task automatic gen_random_pair(
    output int src_rid,
    output int dst_rid
  );
    src_rid = $urandom_range(0, ROUTER_NUM-1);
    dst_rid = $urandom_range(0, ROUTER_NUM-1);
    while (dst_rid == src_rid) begin
      dst_rid = $urandom_range(0, ROUTER_NUM-1);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------
  initial begin
    int src0, dst0, src1, dst1, src2, dst2;
    int msg_id;
    int body_cnt;
    int pkt_len;
    logic [DATA_WIDTH-1:0] flit0, flit1;
    logic [DATA_WIDTH-1:0] pkt_flit [0:15];
    logic                  pkt_head [0:15];
    logic                  pkt_tail [0:15];
    logic [DATA_WIDTH-1:0] pkt0_flit [0:15];
    logic                  pkt0_head [0:15];
    logic                  pkt0_tail [0:15];
    logic [DATA_WIDTH-1:0] pkt1_flit [0:15];
    logic                  pkt1_head [0:15];
    logic                  pkt1_tail [0:15];
    logic [DATA_WIDTH-1:0] pkt2_flit [0:15];
    logic                  pkt2_head [0:15];
    logic                  pkt2_tail [0:15];
    int pkt0_len, pkt1_len, pkt2_len;
    int body0_cnt, body1_cnt, body2_cnt;
    msg_class_t cls0, cls1, cls2;
    int msg0_id, msg1_id, msg2_id;
    msg_class_t msg_cls;
    logic [VC_PRT_SIZE-1:0] vc0, vc1, vc2;

    init_pe_drives();
    RSTn = 1'b0;
    repeat (5) @(posedge CLK);
    RSTn = 1'b1;
    repeat (3) @(posedge CLK);

    $display("==========================================================");
    $display("CASE-A: Single message, random src/dst, repeat 10");
    $display("==========================================================");
    for (int k = 0; k < 10; k++) begin
      gen_random_pair(src0, dst0);
      msg_id = k;
      vc0    = $urandom_range(0, VC_PER_PORT-1);
      flit0  = make_flit(src0, dst0, msg_id);

      $display("[SEND ] msg=%0d src=R%0d(%0d,%0d) dst=R%0d(%0d,%0d) vc=%0d data=0x%08h t=%0t",
               msg_id, src0, rid_x(src0), rid_y(src0), dst0, rid_x(dst0), rid_y(dst0), vc0, flit0, $time);
      print_path_xy(src0, dst0);

      fork
        send_one_flit(src0, flit0, vc0);
        wait_recv_one_flit(dst0, flit0, msg_id);
      join
    end

    $display("==========================================================");
    $display("CASE-B: Two messages concurrently, random src/dst, repeat 5");
    $display("==========================================================");
    for (int k = 0; k < 5; k++) begin
      // pick two pairs, avoid same source to prevent drive conflict
      gen_random_pair(src0, dst0);
      gen_random_pair(src1, dst1);
      while (src1 == src0) begin
        gen_random_pair(src1, dst1);
      end

      msg_id = 100 + (2*k);
      vc0    = $urandom_range(0, VC_PER_PORT-1);
      vc1    = $urandom_range(0, VC_PER_PORT-1);
      flit0  = make_flit(src0, dst0, msg_id);
      flit1  = make_flit(src1, dst1, msg_id+1);

      $display("[SEND2] msg=%0d src=R%0d dst=R%0d vc=%0d data=0x%08h", msg_id,   src0, dst0, vc0, flit0);
      print_path_xy(src0, dst0);
      $display("[SEND2] msg=%0d src=R%0d dst=R%0d vc=%0d data=0x%08h", msg_id+1, src1, dst1, vc1, flit1);
      print_path_xy(src1, dst1);

      fork
        begin
          send_one_flit(src0, flit0, vc0);
          wait_recv_one_flit(dst0, flit0, msg_id);
        end
        begin
          send_one_flit(src1, flit1, vc1);
          wait_recv_one_flit(dst1, flit1, msg_id+1);
        end
      join
    end

        $display("==========================================================");
    $display("CASE-C: One packet with HEAD + random BODYs + TAIL, repeat 10");
    $display("==========================================================");
    for (int k = 0; k < 20; k++) begin
      gen_random_pair(src0, dst0);
      msg_id   = 1000 + k;
      body_cnt = $urandom_range(0, 5);
      pkt_len  = body_cnt + 2;
      msg_cls  = ($urandom_range(0, 1) == 0) ? REQ : RESP;
      if (msg_cls == REQ) vc0 = $urandom_range(0, VC_PER_CLASS-1);
      else                vc0 = $urandom_range(VC_PER_CLASS, VC_PER_PORT-1);

      pkt_flit[0] = '0;
      pkt_flit[0][31:28] = rid_x(dst0);
      pkt_flit[0][27:24] = rid_y(dst0);
      pkt_flit[0][23:20] = rid_x(src0);
      pkt_flit[0][19:16] = rid_y(src0);
      pkt_flit[0][15:14] = FLIT_HEAD;
      pkt_flit[0][13:10] = pkt_len[3:0];
      pkt_flit[0][9:5]   = 5'd0;
      pkt_flit[0][4:3]   = 2'b00;
      pkt_flit[0][2:0]   = msg_cls;
      pkt_head[0] = 1'b1;
      pkt_tail[0] = 1'b0;

      for (int b = 0; b < body_cnt; b++) begin
        pkt_flit[b+1] = '0;
        pkt_flit[b+1][31:28] = rid_x(dst0);
        pkt_flit[b+1][27:24] = rid_y(dst0);
        pkt_flit[b+1][23:20] = rid_x(src0);
        pkt_flit[b+1][19:16] = rid_y(src0);
        pkt_flit[b+1][15:14] = FLIT_BODY;
        pkt_flit[b+1][13:10] = pkt_len[3:0];
        pkt_flit[b+1][9:5]   = (b+1);
        pkt_flit[b+1][4:3]   = 2'b00;
        pkt_flit[b+1][2:0]   = msg_cls;
        pkt_head[b+1] = 1'b0;
        pkt_tail[b+1] = 1'b0;
      end

      pkt_flit[pkt_len-1] = '0;
      pkt_flit[pkt_len-1][31:28] = rid_x(dst0);
      pkt_flit[pkt_len-1][27:24] = rid_y(dst0);
      pkt_flit[pkt_len-1][23:20] = rid_x(src0);
      pkt_flit[pkt_len-1][19:16] = rid_y(src0);
      pkt_flit[pkt_len-1][15:14] = FLIT_TAIL;
      pkt_flit[pkt_len-1][13:10] = pkt_len[3:0];
      pkt_flit[pkt_len-1][9:5]   = (pkt_len-1);
      pkt_flit[pkt_len-1][4:3]   = 2'b00;
      pkt_flit[pkt_len-1][2:0]   = msg_cls;
      pkt_head[pkt_len-1] = 1'b0;
      pkt_tail[pkt_len-1] = 1'b1;

      $display("[SENDP] msg=%0d src=R%0d dst=R%0d vc=%0d class=%s body_cnt=%0d",
               msg_id, src0, dst0, vc0, (msg_cls==RESP)?"RESP":"REQ", body_cnt);
      print_path_xy(src0, dst0);

      fork
        begin
          for (int b = 0; b < pkt_len; b++) begin
            $display("[SENDB] msg=%0d beat=%0d H=%0b T=%0b data=0x%08h t=%0t",
                     msg_id, b, pkt_head[b], pkt_tail[b], pkt_flit[b], $time);
            send_one_beat(src0, pkt_flit[b], vc0, pkt_head[b], pkt_tail[b]);
          end
        end
        begin
          for (int b = 0; b < pkt_len; b++) begin
            wait_recv_one_beat_strict(dst0, src0, msg_id, b, pkt_len, msg_cls, pkt_head[b], pkt_tail[b]);
          end
        end
      join
    end


    $display("==========================================================");
    $display("CASE-D: Three packets concurrently, random BODY lengths, repeat 20");
    $display("==========================================================");

    for (int kd = 0; kd < 20; kd++) begin
    gen_random_pair(src0, dst0);
    gen_random_pair(src1, dst1);
    while (src1 == src0) begin
      gen_random_pair(src1, dst1);
    end
    gen_random_pair(src2, dst2);
    while ((src2 == src0) || (src2 == src1)) begin
      gen_random_pair(src2, dst2);
    end

    msg0_id = 2000 + (3*kd);
    msg1_id = 2001 + (3*kd);
    msg2_id = 2002 + (3*kd);

    body0_cnt = $urandom_range(0, 5);
    body1_cnt = $urandom_range(0, 5);
    body2_cnt = $urandom_range(0, 5);
    pkt0_len  = body0_cnt + 2;
    pkt1_len  = body1_cnt + 2;
    pkt2_len  = body2_cnt + 2;

    cls0 = ($urandom_range(0, 1) == 0) ? REQ : RESP;
    cls1 = ($urandom_range(0, 1) == 0) ? REQ : RESP;
    cls2 = ($urandom_range(0, 1) == 0) ? REQ : RESP;

    if (cls0 == REQ) vc0 = $urandom_range(0, VC_PER_CLASS-1);
    else             vc0 = $urandom_range(VC_PER_CLASS, VC_PER_PORT-1);
    if (cls1 == REQ) vc1 = $urandom_range(0, VC_PER_CLASS-1);
    else             vc1 = $urandom_range(VC_PER_CLASS, VC_PER_PORT-1);
    if (cls2 == REQ) vc2 = $urandom_range(0, VC_PER_CLASS-1);
    else             vc2 = $urandom_range(VC_PER_CLASS, VC_PER_PORT-1);

    pkt0_flit[0] = '0;
    pkt0_flit[0][31:28] = rid_x(dst0);
    pkt0_flit[0][27:24] = rid_y(dst0);
    pkt0_flit[0][23:20] = rid_x(src0);
    pkt0_flit[0][19:16] = rid_y(src0);
    pkt0_flit[0][15:14] = FLIT_HEAD;
    pkt0_flit[0][13:10] = pkt0_len[3:0];
    pkt0_flit[0][9:5]   = 5'd0;
    pkt0_flit[0][4:3]   = 2'b00;
    pkt0_flit[0][2:0]   = cls0;
    pkt0_head[0] = 1'b1;
    pkt0_tail[0] = 1'b0;
    for (int b = 0; b < body0_cnt; b++) begin
      pkt0_flit[b+1] = '0;
      pkt0_flit[b+1][31:28] = rid_x(dst0);
      pkt0_flit[b+1][27:24] = rid_y(dst0);
      pkt0_flit[b+1][23:20] = rid_x(src0);
      pkt0_flit[b+1][19:16] = rid_y(src0);
      pkt0_flit[b+1][15:14] = FLIT_BODY;
      pkt0_flit[b+1][13:10] = pkt0_len[3:0];
      pkt0_flit[b+1][9:5]   = (b+1);
      pkt0_flit[b+1][4:3]   = 2'b00;
      pkt0_flit[b+1][2:0]   = cls0;
      pkt0_head[b+1] = 1'b0;
      pkt0_tail[b+1] = 1'b0;
    end
    pkt0_flit[pkt0_len-1] = '0;
    pkt0_flit[pkt0_len-1][31:28] = rid_x(dst0);
    pkt0_flit[pkt0_len-1][27:24] = rid_y(dst0);
    pkt0_flit[pkt0_len-1][23:20] = rid_x(src0);
    pkt0_flit[pkt0_len-1][19:16] = rid_y(src0);
    pkt0_flit[pkt0_len-1][15:14] = FLIT_TAIL;
    pkt0_flit[pkt0_len-1][13:10] = pkt0_len[3:0];
    pkt0_flit[pkt0_len-1][9:5]   = (pkt0_len-1);
    pkt0_flit[pkt0_len-1][4:3]   = 2'b00;
    pkt0_flit[pkt0_len-1][2:0]   = cls0;
    pkt0_head[pkt0_len-1] = 1'b0;
    pkt0_tail[pkt0_len-1] = 1'b1;

    pkt1_flit[0] = '0;
    pkt1_flit[0][31:28] = rid_x(dst1);
    pkt1_flit[0][27:24] = rid_y(dst1);
    pkt1_flit[0][23:20] = rid_x(src1);
    pkt1_flit[0][19:16] = rid_y(src1);
    pkt1_flit[0][15:14] = FLIT_HEAD;
    pkt1_flit[0][13:10] = pkt1_len[3:0];
    pkt1_flit[0][9:5]   = 5'd0;
    pkt1_flit[0][4:3]   = 2'b00;
    pkt1_flit[0][2:0]   = cls1;
    pkt1_head[0] = 1'b1;
    pkt1_tail[0] = 1'b0;
    for (int b = 0; b < body1_cnt; b++) begin
      pkt1_flit[b+1] = '0;
      pkt1_flit[b+1][31:28] = rid_x(dst1);
      pkt1_flit[b+1][27:24] = rid_y(dst1);
      pkt1_flit[b+1][23:20] = rid_x(src1);
      pkt1_flit[b+1][19:16] = rid_y(src1);
      pkt1_flit[b+1][15:14] = FLIT_BODY;
      pkt1_flit[b+1][13:10] = pkt1_len[3:0];
      pkt1_flit[b+1][9:5]   = (b+1);
      pkt1_flit[b+1][4:3]   = 2'b00;
      pkt1_flit[b+1][2:0]   = cls1;
      pkt1_head[b+1] = 1'b0;
      pkt1_tail[b+1] = 1'b0;
    end
    pkt1_flit[pkt1_len-1] = '0;
    pkt1_flit[pkt1_len-1][31:28] = rid_x(dst1);
    pkt1_flit[pkt1_len-1][27:24] = rid_y(dst1);
    pkt1_flit[pkt1_len-1][23:20] = rid_x(src1);
    pkt1_flit[pkt1_len-1][19:16] = rid_y(src1);
    pkt1_flit[pkt1_len-1][15:14] = FLIT_TAIL;
    pkt1_flit[pkt1_len-1][13:10] = pkt1_len[3:0];
    pkt1_flit[pkt1_len-1][9:5]   = (pkt1_len-1);
    pkt1_flit[pkt1_len-1][4:3]   = 2'b00;
    pkt1_flit[pkt1_len-1][2:0]   = cls1;
    pkt1_head[pkt1_len-1] = 1'b0;
    pkt1_tail[pkt1_len-1] = 1'b1;

    pkt2_flit[0] = '0;
    pkt2_flit[0][31:28] = rid_x(dst2);
    pkt2_flit[0][27:24] = rid_y(dst2);
    pkt2_flit[0][23:20] = rid_x(src2);
    pkt2_flit[0][19:16] = rid_y(src2);
    pkt2_flit[0][15:14] = FLIT_HEAD;
    pkt2_flit[0][13:10] = pkt2_len[3:0];
    pkt2_flit[0][9:5]   = 5'd0;
    pkt2_flit[0][4:3]   = 2'b00;
    pkt2_flit[0][2:0]   = cls2;
    pkt2_head[0] = 1'b1;
    pkt2_tail[0] = 1'b0;
    for (int b = 0; b < body2_cnt; b++) begin
      pkt2_flit[b+1] = '0;
      pkt2_flit[b+1][31:28] = rid_x(dst2);
      pkt2_flit[b+1][27:24] = rid_y(dst2);
      pkt2_flit[b+1][23:20] = rid_x(src2);
      pkt2_flit[b+1][19:16] = rid_y(src2);
      pkt2_flit[b+1][15:14] = FLIT_BODY;
      pkt2_flit[b+1][13:10] = pkt2_len[3:0];
      pkt2_flit[b+1][9:5]   = (b+1);
      pkt2_flit[b+1][4:3]   = 2'b00;
      pkt2_flit[b+1][2:0]   = cls2;
      pkt2_head[b+1] = 1'b0;
      pkt2_tail[b+1] = 1'b0;
    end
    pkt2_flit[pkt2_len-1] = '0;
    pkt2_flit[pkt2_len-1][31:28] = rid_x(dst2);
    pkt2_flit[pkt2_len-1][27:24] = rid_y(dst2);
    pkt2_flit[pkt2_len-1][23:20] = rid_x(src2);
    pkt2_flit[pkt2_len-1][19:16] = rid_y(src2);
    pkt2_flit[pkt2_len-1][15:14] = FLIT_TAIL;
    pkt2_flit[pkt2_len-1][13:10] = pkt2_len[3:0];
    pkt2_flit[pkt2_len-1][9:5]   = (pkt2_len-1);
    pkt2_flit[pkt2_len-1][4:3]   = 2'b00;
    pkt2_flit[pkt2_len-1][2:0]   = cls2;
    pkt2_head[pkt2_len-1] = 1'b0;
    pkt2_tail[pkt2_len-1] = 1'b1;

    $display("[SENDP3] msg=%0d src=R%0d dst=R%0d vc=%0d class=%s body_cnt=%0d", msg0_id, src0, dst0, vc0, (cls0==RESP)?"RESP":"REQ", body0_cnt);
    print_path_xy(src0, dst0);
    $display("[SENDP3] msg=%0d src=R%0d dst=R%0d vc=%0d class=%s body_cnt=%0d", msg1_id, src1, dst1, vc1, (cls1==RESP)?"RESP":"REQ", body1_cnt);
    print_path_xy(src1, dst1);
    $display("[SENDP3] msg=%0d src=R%0d dst=R%0d vc=%0d class=%s body_cnt=%0d", msg2_id, src2, dst2, vc2, (cls2==RESP)?"RESP":"REQ", body2_cnt);
    print_path_xy(src2, dst2);

    fork
      begin
        for (int b = 0; b < pkt0_len; b++) begin
          $display("[SENDB3] msg=%0d beat=%0d H=%0b T=%0b data=0x%08h t=%0t", msg0_id, b, pkt0_head[b], pkt0_tail[b], pkt0_flit[b], $time);
          send_one_beat(src0, pkt0_flit[b], vc0, pkt0_head[b], pkt0_tail[b]);
        end
      end
      begin
        for (int b = 0; b < pkt1_len; b++) begin
          $display("[SENDB3] msg=%0d beat=%0d H=%0b T=%0b data=0x%08h t=%0t", msg1_id, b, pkt1_head[b], pkt1_tail[b], pkt1_flit[b], $time);
          send_one_beat(src1, pkt1_flit[b], vc1, pkt1_head[b], pkt1_tail[b]);
        end
      end
      begin
        for (int b = 0; b < pkt2_len; b++) begin
          $display("[SENDB3] msg=%0d beat=%0d H=%0b T=%0b data=0x%08h t=%0t", msg2_id, b, pkt2_head[b], pkt2_tail[b], pkt2_flit[b], $time);
          send_one_beat(src2, pkt2_flit[b], vc2, pkt2_head[b], pkt2_tail[b]);
        end
      end
      begin
        for (int b = 0; b < pkt0_len; b++) begin
          wait_recv_one_beat_strict(dst0, src0, msg0_id, b, pkt0_len, cls0, pkt0_head[b], pkt0_tail[b]);
        end
      end
      begin
        for (int b = 0; b < pkt1_len; b++) begin
          wait_recv_one_beat_strict(dst1, src1, msg1_id, b, pkt1_len, cls1, pkt1_head[b], pkt1_tail[b]);
        end
      end
      begin
        for (int b = 0; b < pkt2_len; b++) begin
          wait_recv_one_beat_strict(dst2, src2, msg2_id, b, pkt2_len, cls2, pkt2_head[b], pkt2_tail[b]);
        end
      end
    join
    end

    $display("TB_MESH_3x3_TOP: PASS");
    $finish;
  end

endmodule


