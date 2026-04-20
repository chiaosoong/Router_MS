/**********************************
* 3-stage VC router: RC+VA | SA | ST
* - XY routing
* - wormhole switching
* - per-input VC FIFOs
**********************************/
module ROUTER_3STAGE_VC
import noc_params::*;
#(
  parameter POS THISX = P0,
  parameter POS THISY = P0,
  parameter int DOWNSTREAM_VC_DEPTH = FIFO_DEPTH + 2
)(
  input  logic CLK,
  input  logic RSTn,
  router_vc_flit_if.rx IFLIT[PORT_NUM],
  router_vc_flit_if.tx OFLIT[PORT_NUM]
);

  localparam int FIFO_WORD_W = DATA_WIDTH + 2;
  localparam int CREDIT_W    = (DOWNSTREAM_VC_DEPTH <= 1) ? 1 : $clog2(DOWNSTREAM_VC_DEPTH + 1);

  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                  fifo_wr_en;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                  fifo_rd_en;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                  fifo_full;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                  fifo_empty;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][FIFO_WORD_W-1:0] fifo_din;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][FIFO_WORD_W-1:0] fifo_dout;

  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                 front_valid;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                 front_is_head;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                 front_is_tail;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][DATA_WIDTH-1:0] front_data;

  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                  s1_valid_q;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0]                  s1_valid_d;
  port_t s1_outport_q [PORT_NUM-1:0][VC_PER_PORT-1:0];
  port_t s1_outport_d [PORT_NUM-1:0][VC_PER_PORT-1:0];
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][VC_PRT_SIZE-1:0] s1_ovc_q;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][VC_PRT_SIZE-1:0] s1_ovc_d;

  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] ivc_lock_valid_q;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] ivc_lock_valid_d;
  port_t ivc_lock_outport_q [PORT_NUM-1:0][VC_PER_PORT-1:0];
  port_t ivc_lock_outport_d [PORT_NUM-1:0][VC_PER_PORT-1:0];
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][VC_PRT_SIZE-1:0] ivc_lock_ovc_q;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][VC_PRT_SIZE-1:0] ivc_lock_ovc_d;

  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] ovc_busy_q;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] ovc_busy_d;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][CREDIT_W-1:0] ovc_credit_q;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][CREDIT_W-1:0] ovc_credit_d;

  logic [PORT_NUM-1:0] s2_valid_q;
  logic [PORT_NUM-1:0] s2_valid_d;
  logic [PORT_NUM-1:0][DATA_WIDTH-1:0] s2_flit_data_q;
  logic [PORT_NUM-1:0][DATA_WIDTH-1:0] s2_flit_data_d;
  logic [PORT_NUM-1:0] s2_is_head_q;
  logic [PORT_NUM-1:0] s2_is_head_d;
  logic [PORT_NUM-1:0] s2_is_tail_q;
  logic [PORT_NUM-1:0] s2_is_tail_d;
  port_t s2_outport_q [PORT_NUM-1:0];
  port_t s2_outport_d [PORT_NUM-1:0];
  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] s2_ovc_q;
  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] s2_ovc_d;

  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] sa_request;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] sa_grant;
  port_t [VC_PER_PORT-1:0] sa_target_port [PORT_NUM-1:0];

  logic [PORT_NUM-1:0] s2_pop;
  logic [PORT_NUM-1:0] s2_slot_available;
  logic [PORT_NUM-1:0] output_busy_s2;

  logic [PORT_NUM-1:0]                  iflit_valid;
  logic [PORT_NUM-1:0][DATA_WIDTH-1:0]  iflit_data;
  logic [PORT_NUM-1:0]                  iflit_is_head;
  logic [PORT_NUM-1:0]                  iflit_is_tail;
  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] iflit_vc_id;
  logic [PORT_NUM-1:0]                  iflit_ready;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] iflit_credit_return;

  logic [PORT_NUM-1:0]                  oflit_valid;
  logic [PORT_NUM-1:0][DATA_WIDTH-1:0]  oflit_data;
  logic [PORT_NUM-1:0]                  oflit_is_head;
  logic [PORT_NUM-1:0]                  oflit_is_tail;
  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] oflit_vc_id;
  logic [PORT_NUM-1:0]                  oflit_ready;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] oflit_credit_return;

  function automatic POS decode_dstx(input logic [DATA_WIDTH-1:0] flit);
    decode_dstx = POS'(flit[31:28]);
  endfunction

  function automatic POS decode_dsty(input logic [DATA_WIDTH-1:0] flit);
    decode_dsty = POS'(flit[27:24]);
  endfunction

  function automatic msg_class_t decode_msg_class(input logic [DATA_WIDTH-1:0] flit);
    decode_msg_class = (flit[2:0] == RESP) ? RESP : REQ;
  endfunction

  function automatic port_t xy_route(input POS dstx, input POS dsty);
    if (THISX < dstx)      xy_route = EAST;
    else if (THISX > dstx) xy_route = WEST;
    else if (THISY > dsty) xy_route = SOUTH;
    else if (THISY < dsty) xy_route = NORTH;
    else                   xy_route = LOCAL;
  endfunction

  genvar in_port_g;
  genvar vc_g;
  genvar if_port_g;
  generate
    for (if_port_g = 0; if_port_g < PORT_NUM; if_port_g++) begin : GEN_IF_BIND
      assign iflit_valid[if_port_g]         = IFLIT[if_port_g].valid;
      assign iflit_data[if_port_g]          = IFLIT[if_port_g].flit_data;
      assign iflit_is_head[if_port_g]       = IFLIT[if_port_g].is_head;
      assign iflit_is_tail[if_port_g]       = IFLIT[if_port_g].is_tail;
      assign iflit_vc_id[if_port_g]         = IFLIT[if_port_g].vc_id;
      assign IFLIT[if_port_g].ready         = iflit_ready[if_port_g];
      assign IFLIT[if_port_g].credit_return = iflit_credit_return[if_port_g];

      assign oflit_ready[if_port_g]         = OFLIT[if_port_g].ready;
      assign oflit_credit_return[if_port_g] = OFLIT[if_port_g].credit_return;
      assign OFLIT[if_port_g].valid         = oflit_valid[if_port_g];
      assign OFLIT[if_port_g].flit_data     = oflit_data[if_port_g];
      assign OFLIT[if_port_g].is_head       = oflit_is_head[if_port_g];
      assign OFLIT[if_port_g].is_tail       = oflit_is_tail[if_port_g];
      assign OFLIT[if_port_g].vc_id         = oflit_vc_id[if_port_g];
    end

    for (in_port_g = 0; in_port_g < PORT_NUM; in_port_g++) begin : GEN_IVC_PORT
      for (vc_g = 0; vc_g < VC_PER_PORT; vc_g++) begin : GEN_IVC
        SYNC_FIFO #(
          .WIDTH (FIFO_WORD_W),
          .DEPTH (FIFO_DEPTH)
        ) u_ivc_fifo (
          .CLK       (CLK),
          .RSTn      (RSTn),
          .WR_EN     (fifo_wr_en[in_port_g][vc_g]),
          .RD_EN     (fifo_rd_en[in_port_g][vc_g]),
          .DATA_IN   (fifo_din[in_port_g][vc_g]),
          .FIFO_FULL (fifo_full[in_port_g][vc_g]),
          .FIFO_EMPTY(fifo_empty[in_port_g][vc_g]),
          .DATA_OUT  (fifo_dout[in_port_g][vc_g])
        );

        assign front_valid[in_port_g][vc_g]   = ~fifo_empty[in_port_g][vc_g];
        assign front_is_head[in_port_g][vc_g] = fifo_dout[in_port_g][vc_g][FIFO_WORD_W-1];
        assign front_is_tail[in_port_g][vc_g] = fifo_dout[in_port_g][vc_g][FIFO_WORD_W-2];
        assign front_data[in_port_g][vc_g]    = fifo_dout[in_port_g][vc_g][DATA_WIDTH-1:0];
      end
    end
  endgenerate

  SEPARABLE_INPUT_FIRST_ALLOCATOR #(
    .VC_PER_PORT(VC_PER_PORT)
  ) u_sa (
    .clk           (CLK),
    .RSTn          (RSTn),
    .vc_request    (sa_request),
    .vc_target_port(sa_target_port),
    .vc_grant_final(sa_grant)
  );

  always_comb begin
    for (int p = 0; p < PORT_NUM; p++) begin
      iflit_ready[p]         = 1'b0;
      iflit_credit_return[p] = '0;

      oflit_valid[p]     = 1'b0;
      oflit_data[p]      = '0;
      oflit_is_head[p]   = 1'b0;
      oflit_is_tail[p]   = 1'b0;
      oflit_vc_id[p]     = '0;
    end

    for (int p = 0; p < PORT_NUM; p++) begin
      int in_vc;
      in_vc = int'(iflit_vc_id[p]);
      if ((in_vc >= 0) && (in_vc < VC_PER_PORT)) begin
        iflit_ready[p] = ~fifo_full[p][in_vc];
      end

      iflit_credit_return[p] = fifo_rd_en[p];
    end

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      if (s2_valid_q[in_p]) begin
        int out_p;
        out_p = int'(s2_outport_q[in_p]);
        oflit_valid[out_p]     = 1'b1;
        oflit_data[out_p]      = s2_flit_data_q[in_p];
        oflit_is_head[out_p]   = s2_is_head_q[in_p];
        oflit_is_tail[out_p]   = s2_is_tail_q[in_p];
        oflit_vc_id[out_p]     = s2_ovc_q[in_p];
      end
    end
  end

  always_comb begin
    s1_valid_d        = s1_valid_q;
    s1_outport_d      = s1_outport_q;
    s1_ovc_d          = s1_ovc_q;
    ivc_lock_valid_d  = ivc_lock_valid_q;
    ivc_lock_outport_d = ivc_lock_outport_q;
    ivc_lock_ovc_d    = ivc_lock_ovc_q;
    ovc_busy_d        = ovc_busy_q;
    ovc_credit_d      = ovc_credit_q;
    s2_valid_d        = s2_valid_q;
    s2_flit_data_d    = s2_flit_data_q;
    s2_is_head_d      = s2_is_head_q;
    s2_is_tail_d      = s2_is_tail_q;
    s2_outport_d      = s2_outport_q;
    s2_ovc_d          = s2_ovc_q;

    fifo_wr_en        = '0;
    fifo_rd_en        = '0;
    fifo_din          = '0;
    sa_request        = '0;
    s2_pop            = '0;
    s2_slot_available = '0;
    output_busy_s2    = '0;

    for (int p = 0; p < PORT_NUM; p++) begin
      int in_vc;
      in_vc = int'(iflit_vc_id[p]);
      if (iflit_valid[p] && (in_vc >= 0) && (in_vc < VC_PER_PORT) && ~fifo_full[p][in_vc]) begin
        fifo_wr_en[p][in_vc] = 1'b1;
        fifo_din[p][in_vc]   = {iflit_is_head[p], iflit_is_tail[p], iflit_data[p]};
      end
    end

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      int out_p;
      out_p = int'(s2_outport_q[in_p]);
      s2_pop[in_p]            = s2_valid_q[in_p] && oflit_ready[out_p];
      s2_slot_available[in_p] = ~s2_valid_q[in_p] || s2_pop[in_p];
      if (s2_valid_q[in_p] && ~s2_pop[in_p]) begin
        output_busy_s2[out_p] = 1'b1;
      end
    end

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        sa_target_port[in_p][local_vc] = s1_outport_q[in_p][local_vc];
        if (s1_valid_q[in_p][local_vc] &&
            s2_slot_available[in_p] &&
            ~output_busy_s2[int'(s1_outport_q[in_p][local_vc])]) begin
          sa_request[in_p][local_vc] = 1'b1;
        end
      end
    end

    for (int out_p = 0; out_p < PORT_NUM; out_p++) begin
      for (int local_ovc = 0; local_ovc < VC_PER_PORT; local_ovc++) begin
        if (oflit_credit_return[out_p][local_ovc] && (ovc_credit_d[out_p][local_ovc] < DOWNSTREAM_VC_DEPTH)) begin
          ovc_credit_d[out_p][local_ovc] = ovc_credit_d[out_p][local_ovc] + 1'b1;
        end
      end
    end

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      if (s2_pop[in_p]) begin
        int out_p;
        int ovc;
        out_p = int'(s2_outport_q[in_p]);
        ovc   = int'(s2_ovc_q[in_p]);

        s2_valid_d[in_p] = 1'b0;
        if (s2_is_tail_q[in_p]) begin
          ovc_busy_d[out_p][ovc] = 1'b0;
        end
      end
    end

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        if (sa_grant[in_p][local_vc]) begin
          int out_p;
          int ovc;
          out_p = int'(s1_outport_q[in_p][local_vc]);
          ovc   = int'(s1_ovc_q[in_p][local_vc]);

          fifo_rd_en[in_p][local_vc]   = 1'b1;
          s1_valid_d[in_p][local_vc]   = 1'b0;
          s2_valid_d[in_p]             = 1'b1;
          s2_flit_data_d[in_p]         = front_data[in_p][local_vc];
          s2_is_head_d[in_p]           = front_is_head[in_p][local_vc];
          s2_is_tail_d[in_p]           = front_is_tail[in_p][local_vc];
          s2_outport_d[in_p]           = s1_outport_q[in_p][local_vc];
          s2_ovc_d[in_p]               = s1_ovc_q[in_p][local_vc];
          ovc_credit_d[out_p][ovc]     = ovc_credit_d[out_p][ovc] - 1'b1;

          if (front_is_tail[in_p][local_vc]) begin
            ivc_lock_valid_d[in_p][local_vc] = 1'b0;
          end
        end
      end
    end

    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      logic [VC_PER_PORT-1:0] ovc_busy_shadow;
      ovc_busy_shadow = '0;

      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        if (~s1_valid_q[in_p][local_vc] && front_valid[in_p][local_vc]) begin
          if (front_is_head[in_p][local_vc]) begin
            if (~ivc_lock_valid_q[in_p][local_vc]) begin
              port_t req_port;
              msg_class_t req_class;
              int class_base;
              int selected_ovc;

              req_port     = xy_route(decode_dstx(front_data[in_p][local_vc]), decode_dsty(front_data[in_p][local_vc]));
              req_class    = decode_msg_class(front_data[in_p][local_vc]);
              class_base   = (req_class == RESP) ? VC_PER_CLASS : 0;
              selected_ovc = -1;

              for (int offset = 0; offset < VC_PER_CLASS; offset++) begin
                int candidate_ovc;
                candidate_ovc = class_base + offset;
                if (~ovc_busy_shadow[candidate_ovc] &&
                    ~ovc_busy_q[int'(req_port)][candidate_ovc] &&
                    (ovc_credit_q[int'(req_port)][candidate_ovc] != '0)) begin
                  selected_ovc = candidate_ovc;
                  ovc_busy_shadow[candidate_ovc] = 1'b1;
                  break;
                end
              end

              if (selected_ovc >= 0) begin
                s1_valid_d[in_p][local_vc]          = 1'b1;
                s1_outport_d[in_p][local_vc]        = req_port;
                s1_ovc_d[in_p][local_vc]            = selected_ovc[VC_PRT_SIZE-1:0];
                ivc_lock_valid_d[in_p][local_vc]    = 1'b1;
                ivc_lock_outport_d[in_p][local_vc]  = req_port;
                ivc_lock_ovc_d[in_p][local_vc]      = selected_ovc[VC_PRT_SIZE-1:0];
                ovc_busy_d[int'(req_port)][selected_ovc] = 1'b1;
              end
            end
          end
          else if (ivc_lock_valid_q[in_p][local_vc] &&
                   (ovc_credit_q[int'(ivc_lock_outport_q[in_p][local_vc])][int'(ivc_lock_ovc_q[in_p][local_vc])] != '0)) begin
            s1_valid_d[in_p][local_vc]   = 1'b1;
            s1_outport_d[in_p][local_vc] = ivc_lock_outport_q[in_p][local_vc];
            s1_ovc_d[in_p][local_vc]     = ivc_lock_ovc_q[in_p][local_vc];
          end
        end
      end
    end
  end

  always_ff @(posedge CLK) begin
    if (!RSTn) begin
      s1_valid_q       <= '0;
      s1_ovc_q         <= '0;
      ivc_lock_valid_q <= '0;
      ivc_lock_ovc_q   <= '0;
      ovc_busy_q       <= '0;
      s2_valid_q       <= '0;
      s2_flit_data_q   <= '0;
      s2_is_head_q     <= '0;
      s2_is_tail_q     <= '0;
      s2_ovc_q         <= '0;

      for (int p = 0; p < PORT_NUM; p++) begin
        s2_outport_q[p] <= LOCAL;
        for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
          s1_outport_q[p][local_vc]       <= LOCAL;
          ivc_lock_outport_q[p][local_vc] <= LOCAL;
          ovc_credit_q[p][local_vc]       <= DOWNSTREAM_VC_DEPTH[CREDIT_W-1:0];
        end
      end
    end
    else begin
      s1_valid_q       <= s1_valid_d;
      s1_outport_q     <= s1_outport_d;
      s1_ovc_q         <= s1_ovc_d;
      ivc_lock_valid_q <= ivc_lock_valid_d;
      ivc_lock_outport_q <= ivc_lock_outport_d;
      ivc_lock_ovc_q   <= ivc_lock_ovc_d;
      ovc_busy_q       <= ovc_busy_d;
      ovc_credit_q     <= ovc_credit_d;
      s2_valid_q       <= s2_valid_d;
      s2_flit_data_q   <= s2_flit_data_d;
      s2_is_head_q     <= s2_is_head_d;
      s2_is_tail_q     <= s2_is_tail_d;
      s2_outport_q     <= s2_outport_d;
      s2_ovc_q         <= s2_ovc_d;
    end
  end

endmodule
