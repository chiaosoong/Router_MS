`timescale 1ns/1ps

import noc_params::*;

module TB_ROUTER_3STAGE_VC;

  logic CLK;
  logic RSTn;

  router_vc_flit_if iflit [PORT_NUM] ();
  router_vc_flit_if oflit [PORT_NUM] ();

  logic [PORT_NUM-1:0] in_valid;
  logic [PORT_NUM-1:0][DATA_WIDTH-1:0] in_flit_data;
  logic [PORT_NUM-1:0] in_is_head;
  logic [PORT_NUM-1:0] in_is_tail;
  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] in_vc_id;
  logic [PORT_NUM-1:0] in_ready;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] in_credit_return;

  logic [PORT_NUM-1:0] out_valid;
  logic [PORT_NUM-1:0][DATA_WIDTH-1:0] out_flit_data;
  logic [PORT_NUM-1:0] out_is_head;
  logic [PORT_NUM-1:0] out_is_tail;
  logic [PORT_NUM-1:0][VC_PRT_SIZE-1:0] out_vc_id;
  logic [PORT_NUM-1:0] out_ready;
  logic [PORT_NUM-1:0][VC_PER_PORT-1:0] out_credit_return;

  int east_count;
  int north_count;
  logic [VC_PRT_SIZE-1:0] east_ovc;

  TOP #(
    .THISX(P1),
    .THISY(P1),
    .DOWNSTREAM_VC_DEPTH(8)
  ) dut (
    .CLK  (CLK),
    .RSTn (RSTn),
    .OFLIT(oflit),
    .IFLIT(iflit)
  );

  initial CLK = 1'b0;
  always #5 CLK = ~CLK;

  genvar port_g;
  generate
    for (port_g = 0; port_g < PORT_NUM; port_g++) begin : GEN_TB_IF_BIND
      assign iflit[port_g].valid      = in_valid[port_g];
      assign iflit[port_g].flit_data  = in_flit_data[port_g];
      assign iflit[port_g].is_head    = in_is_head[port_g];
      assign iflit[port_g].is_tail    = in_is_tail[port_g];
      assign iflit[port_g].vc_id      = in_vc_id[port_g];
      assign in_ready[port_g]         = iflit[port_g].ready;
      assign in_credit_return[port_g] = iflit[port_g].credit_return;

      assign out_valid[port_g]        = oflit[port_g].valid;
      assign out_flit_data[port_g]    = oflit[port_g].flit_data;
      assign out_is_head[port_g]      = oflit[port_g].is_head;
      assign out_is_tail[port_g]      = oflit[port_g].is_tail;
      assign out_vc_id[port_g]        = oflit[port_g].vc_id;
      assign oflit[port_g].ready      = out_ready[port_g];
      assign oflit[port_g].credit_return = out_credit_return[port_g];
    end
  endgenerate

  function automatic logic [DATA_WIDTH-1:0] make_head(
    input POS dstx,
    input POS dsty,
    input msg_class_t msg,
    input logic [9:0] payload
  );
    logic [DATA_WIDTH-1:0] flit;
    begin
      flit = '0;
      flit[31:28] = dstx;
      flit[27:24] = dsty;
      flit[15:14] = FLIT_HEAD;
      flit[13:4]  = payload;
      flit[2:0]   = msg;
      make_head   = flit;
    end
  endfunction

  task automatic clear_inputs();
    for (int p = 0; p < PORT_NUM; p++) begin
      in_valid[p]         = 1'b0;
      in_flit_data[p]     = '0;
      in_is_head[p]       = 1'b0;
      in_is_tail[p]       = 1'b0;
      in_vc_id[p]         = '0;

      out_ready[p]        = 1'b1;
      out_credit_return[p] = '0;
    end
  endtask

  task automatic send_flit(
    input port_t in_port,
    input logic [VC_PRT_SIZE-1:0] in_vc,
    input logic [DATA_WIDTH-1:0] data,
    input logic is_head,
    input logic is_tail
  );
    begin
      @(negedge CLK);
      in_flit_data[in_port] = data;
      in_is_head[in_port]   = is_head;
      in_is_tail[in_port]   = is_tail;
      in_vc_id[in_port]     = in_vc;
      in_valid[in_port]     = 1'b1;

      while (!in_ready[in_port]) begin
        @(negedge CLK);
      end

      @(negedge CLK);
      in_valid[in_port]     = 1'b0;
      in_flit_data[in_port] = '0;
      in_is_head[in_port]   = 1'b0;
      in_is_tail[in_port]   = 1'b0;
      in_vc_id[in_port]     = '0;
    end
  endtask

  always @(posedge CLK) begin
    if (RSTn) begin
      for (int p = 0; p < PORT_NUM; p++) begin
        if (out_valid[p] && out_ready[p]) begin
          case (port_t'(p))
            EAST: begin
              case (east_count)
                0: begin
                  if (!out_is_head[p] || out_is_tail[p]) begin
                    $error("First EAST flit must be HEAD");
                    $fatal;
                  end
                  if (out_vc_id[p] > 1) begin
                    $error("REQ packet must allocate OVC0/1 on EAST, got %0d", out_vc_id[p]);
                    $fatal;
                  end
                  east_ovc = out_vc_id[p];
                end
                1: begin
                  if (out_is_head[p] || out_is_tail[p]) begin
                    $error("Second EAST flit must be BODY");
                    $fatal;
                  end
                  if (out_vc_id[p] !== east_ovc) begin
                    $error("BODY flit changed OVC. exp=%0d got=%0d", east_ovc, out_vc_id[p]);
                    $fatal;
                  end
                end
                2: begin
                  if (out_is_head[p] || !out_is_tail[p]) begin
                    $error("Third EAST flit must be TAIL");
                    $fatal;
                  end
                  if (out_vc_id[p] !== east_ovc) begin
                    $error("TAIL flit changed OVC. exp=%0d got=%0d", east_ovc, out_vc_id[p]);
                    $fatal;
                  end
                end
                default: begin
                  $error("Unexpected extra EAST flit");
                  $fatal;
                end
              endcase
              east_count++;
            end

            NORTH: begin
              if (north_count != 0) begin
                $error("Unexpected extra NORTH flit");
                $fatal;
              end
              if (!out_is_head[p] || !out_is_tail[p]) begin
                $error("Second packet must be HEADTAIL on NORTH");
                $fatal;
              end
              if (out_vc_id[p] > 1) begin
                $error("REQ packet must allocate OVC0/1 on NORTH, got %0d", out_vc_id[p]);
                $fatal;
              end
              north_count++;
            end

            default: begin
              $error("Unexpected output activity on port %0d", p);
              $fatal;
            end
          endcase
        end
      end
    end
  end

  initial begin
    clear_inputs();
    east_count = 0;
    north_count = 0;
    east_ovc = '0;
    RSTn = 1'b0;

    repeat (3) @(posedge CLK);
    RSTn = 1'b1;

    send_flit(LOCAL, VC0, make_head(P2, P1, REQ, 10'h155), 1'b1, 1'b0);
    send_flit(LOCAL, VC0, 32'hAAAA_0001, 1'b0, 1'b0);
    send_flit(LOCAL, VC0, 32'hAAAA_0002, 1'b0, 1'b1);
    send_flit(LOCAL, VC0, make_head(P1, P2, REQ, 10'h2A3), 1'b1, 1'b1);

    repeat (20) @(posedge CLK);

    if (east_count != 3) begin
      $error("Expected 3 flits on EAST, got %0d", east_count);
      $fatal;
    end
    if (north_count != 1) begin
      $error("Expected 1 flit on NORTH, got %0d", north_count);
      $fatal;
    end

    $display("TB_ROUTER_3STAGE_VC: PASS");
    $finish;
  end

endmodule
