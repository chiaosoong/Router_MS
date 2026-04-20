/**********************************
* NoC Router Top Module
* - Instantiates the split pipeline-stage modules
* - Owns the pipeline registers and the persistent reservation state
**********************************/
module TOP
import noc_params::*;
#(
  parameter POS THISX = P0,
  parameter POS THISY = P0,
  parameter int DOWNSTREAM_VC_DEPTH = FIFO_DEPTH + 2
)(
  input  logic CLK,
  input  logic RSTn,
  router_vc_flit_if.tx OFLIT[PORT_NUM],
  router_vc_flit_if.rx IFLIT[PORT_NUM]
);

  localparam int CREDIT_W = (DOWNSTREAM_VC_DEPTH <= 1) ? 1 : $clog2(DOWNSTREAM_VC_DEPTH + 1);

  // Flattened copies of interface signals.
  // Vivado handles these normal arrays more reliably than variable indexing
  // directly on interface arrays inside procedural blocks.
  logic [PORT_NUM-1:0] iflit_valid;
  logic [PORT_NUM-1:0][DATA_WIDTH-1:0] iflit_data;
  logic [PORT_NUM-1:0] iflit_is_head;
  logic [PORT_NUM-1:0] iflit_is_tail;
  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] iflit_vc_id;
  logic [PORT_NUM-1:0] iflit_ready;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] iflit_credit_return;

  logic [PORT_NUM-1:0] oflit_valid;
  logic [PORT_NUM-1:0][DATA_WIDTH-1:0] oflit_data;
  logic [PORT_NUM-1:0] oflit_is_head;
  logic [PORT_NUM-1:0] oflit_is_tail;
  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] oflit_vc_id;
  logic [PORT_NUM-1:0] oflit_ready;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] oflit_credit_return;

  // IVC outputs.
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] ivc_pop;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] front_valid;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] front_is_head;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] front_is_tail;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][DATA_WIDTH-1:0] front_data;

  // RCU outputs.
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] rc_valid;
  port_t rc_port [PORT_NUM-1:0][VC_PER_PORT-1:0];
  msg_class_t rc_msg_class [PORT_NUM-1:0][VC_PER_PORT-1:0];
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] va_req_valid;

  // VAU outputs.
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] va_grant;
  port_t va_outport [PORT_NUM-1:0][VC_PER_PORT-1:0];
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0][VC_PRT_SIZE-1:0] va_ovc;

  // Persistent state: Stage-1 pipeline, input-VC packet lock, output VC state.
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] s1_valid_q;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] s1_valid_d;
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

  // Stage-2 pipeline registers.
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

  // SAU/STU outputs.
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] sa_request;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] sa_grant;
  logic [PORT_NUM-1:0] s2_pop;
  logic [PORT_NUM-1:0] s2_slot_available;
  logic [PORT_NUM-1:0] output_busy_s2;

  genvar if_port_g;
  genvar in_port_g;
  genvar local_vc_g;
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

    for (in_port_g = 0; in_port_g < PORT_NUM; in_port_g++) begin : GEN_INPUT_PORT
      IVC u_ivc (
        .CLK          (CLK),
        .RSTn         (RSTn),
        .in_valid     (iflit_valid[in_port_g]),
        .in_flit_data (iflit_data[in_port_g]),
        .in_is_head   (iflit_is_head[in_port_g]),
        .in_is_tail   (iflit_is_tail[in_port_g]),
        .in_vc_id     (iflit_vc_id[in_port_g]),
        .in_ready     (iflit_ready[in_port_g]),
        .consume_vc   (ivc_pop[in_port_g]),
        .credit_return(iflit_credit_return[in_port_g]),
        .front_valid  (front_valid[in_port_g]),
        .front_is_head(front_is_head[in_port_g]),
        .front_is_tail(front_is_tail[in_port_g]),
        .front_data   (front_data[in_port_g])
      );

      for (local_vc_g = 0; local_vc_g < VC_PER_PORT; local_vc_g++) begin : GEN_RCU
        RCU_XY #(
          .THISX(THISX),
          .THISY(THISY)
        ) u_rcu_xy (
          .front_valid  (front_valid[in_port_g][local_vc_g]),
          .front_is_head(front_is_head[in_port_g][local_vc_g]),
          .front_data   (front_data[in_port_g][local_vc_g]),
          .rc_valid     (rc_valid[in_port_g][local_vc_g]),
          .rc_port      (rc_port[in_port_g][local_vc_g]),
          .rc_msg_class (rc_msg_class[in_port_g][local_vc_g])
        );
      end
    end
  endgenerate

  always_comb begin
    va_req_valid = '0;
    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        // Only an unlocked head flit with an empty Stage-1 slot may request VA.
        va_req_valid[in_p][local_vc] =
          rc_valid[in_p][local_vc] &&
          ~ivc_lock_valid_q[in_p][local_vc] &&
          ~s1_valid_q[in_p][local_vc];
      end
    end
  end

  VAU #(
    .CREDIT_W(CREDIT_W)
  ) u_vau (
    .rc_valid      (va_req_valid),
    .rc_port       (rc_port),
    .rc_msg_class  (rc_msg_class),
    .ovc_busy_state(ovc_busy_q),
    .ovc_credit    (ovc_credit_q),
    .va_grant      (va_grant),
    .va_outport    (va_outport),
    .va_ovc        (va_ovc)
  );

  STU u_stu (
    .s2_valid        (s2_valid_q),
    .s2_flit_data    (s2_flit_data_q),
    .s2_is_head      (s2_is_head_q),
    .s2_is_tail      (s2_is_tail_q),
    .s2_outport      (s2_outport_q),
    .s2_ovc          (s2_ovc_q),
    .oflit_ready     (oflit_ready),
    .oflit_valid     (oflit_valid),
    .oflit_data      (oflit_data),
    .oflit_is_head   (oflit_is_head),
    .oflit_is_tail   (oflit_is_tail),
    .oflit_vc_id     (oflit_vc_id),
    .s2_pop          (s2_pop),
    .s2_slot_available(s2_slot_available),
    .output_busy     (output_busy_s2)
  );

  SAU u_sau (
    .CLK             (CLK),
    .RSTn            (RSTn),
    .s1_valid        (s1_valid_q),
    .s1_outport      (s1_outport_q),
    .s2_slot_available(s2_slot_available),
    .output_busy     (output_busy_s2),
    .sa_request      (sa_request),
    .sa_grant        (sa_grant)
  );

  always_comb begin
    s1_valid_d         = s1_valid_q;
    s1_outport_d       = s1_outport_q;
    s1_ovc_d           = s1_ovc_q;
    ivc_lock_valid_d   = ivc_lock_valid_q;
    ivc_lock_outport_d = ivc_lock_outport_q;
    ivc_lock_ovc_d     = ivc_lock_ovc_q;
    ovc_busy_d         = ovc_busy_q;
    ovc_credit_d       = ovc_credit_q;
    s2_valid_d         = s2_valid_q;
    s2_flit_data_d     = s2_flit_data_q;
    s2_is_head_d       = s2_is_head_q;
    s2_is_tail_d       = s2_is_tail_q;
    s2_outport_d       = s2_outport_q;
    s2_ovc_d           = s2_ovc_q;
    ivc_pop            = '0;

    // Credit returns come from the downstream router input VC consumption.
    for (int out_p = 0; out_p < PORT_NUM; out_p++) begin
      for (int local_ovc = 0; local_ovc < VC_PER_PORT; local_ovc++) begin
        if (oflit_credit_return[out_p][local_ovc] &&
            (ovc_credit_d[out_p][local_ovc] < DOWNSTREAM_VC_DEPTH)) begin
          ovc_credit_d[out_p][local_ovc] = ovc_credit_d[out_p][local_ovc] + 1'b1;
        end
      end
    end

    // Stage-3 completion clears the occupied output VC on tail flits.
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

    // A switch-allocation winner dequeues one flit and loads the Stage-2 register.
    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        if (sa_grant[in_p][local_vc]) begin
          int out_p;
          int ovc;

          out_p = int'(s1_outport_q[in_p][local_vc]);
          ovc   = int'(s1_ovc_q[in_p][local_vc]);

          ivc_pop[in_p][local_vc]     = 1'b1;
          s1_valid_d[in_p][local_vc]  = 1'b0;
          s2_valid_d[in_p]            = 1'b1;
          s2_flit_data_d[in_p]        = front_data[in_p][local_vc];
          s2_is_head_d[in_p]          = front_is_head[in_p][local_vc];
          s2_is_tail_d[in_p]          = front_is_tail[in_p][local_vc];
          s2_outport_d[in_p]          = s1_outport_q[in_p][local_vc];
          s2_ovc_d[in_p]              = s1_ovc_q[in_p][local_vc];
          ovc_credit_d[out_p][ovc]    = ovc_credit_d[out_p][ovc] - 1'b1;

          if (front_is_tail[in_p][local_vc]) begin
            ivc_lock_valid_d[in_p][local_vc] = 1'b0;
          end
        end
      end
    end

    // Stage-1 loads either a freshly allocated head flit or a body/tail flit
    // that follows an already established packet lock.
    for (int in_p = 0; in_p < PORT_NUM; in_p++) begin
      for (int local_vc = 0; local_vc < VC_PER_PORT; local_vc++) begin
        if (~s1_valid_q[in_p][local_vc] && front_valid[in_p][local_vc]) begin
          if (front_is_head[in_p][local_vc]) begin
            if (va_grant[in_p][local_vc]) begin
              s1_valid_d[in_p][local_vc]        = 1'b1;
              s1_outport_d[in_p][local_vc]      = va_outport[in_p][local_vc];
              s1_ovc_d[in_p][local_vc]          = va_ovc[in_p][local_vc];
              ivc_lock_valid_d[in_p][local_vc]  = 1'b1;
              ivc_lock_outport_d[in_p][local_vc] = va_outport[in_p][local_vc];
              ivc_lock_ovc_d[in_p][local_vc]    = va_ovc[in_p][local_vc];
              ovc_busy_d[int'(va_outport[in_p][local_vc])][int'(va_ovc[in_p][local_vc])] = 1'b1;
            end
          end
          else if (ivc_lock_valid_q[in_p][local_vc] &&
                   (ovc_credit_q[int'(ivc_lock_outport_q[in_p][local_vc])]
                                 [int'(ivc_lock_ovc_q[in_p][local_vc])] != '0)) begin
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
      s1_valid_q         <= s1_valid_d;
      s1_outport_q       <= s1_outport_d;
      s1_ovc_q           <= s1_ovc_d;
      ivc_lock_valid_q   <= ivc_lock_valid_d;
      ivc_lock_outport_q <= ivc_lock_outport_d;
      ivc_lock_ovc_q     <= ivc_lock_ovc_d;
      ovc_busy_q         <= ovc_busy_d;
      ovc_credit_q       <= ovc_credit_d;
      s2_valid_q         <= s2_valid_d;
      s2_flit_data_q     <= s2_flit_data_d;
      s2_is_head_q       <= s2_is_head_d;
      s2_is_tail_q       <= s2_is_tail_d;
      s2_outport_q       <= s2_outport_d;
      s2_ovc_q           <= s2_ovc_d;
    end
  end

endmodule
