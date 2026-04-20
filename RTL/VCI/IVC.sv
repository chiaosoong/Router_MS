/**********************************
* Input VC Unit
* - One instance serves one physical input port
* - Internally contains VC_PER_PORT input FIFOs
* - Exposes the front flit of every VC without dequeuing it
**********************************/
module IVC
import noc_params::*;
(
  input  logic CLK,
  input  logic RSTn,

  input  logic                  in_valid,
  input  logic [DATA_WIDTH-1:0] in_flit_data,
  input  logic                  in_is_head,
  input  logic                  in_is_tail,
  input  logic [VC_PRT_SIZE-1:0] in_vc_id,
  output logic                  in_ready,

  // A pop on one local VC returns one credit to the upstream router.
  input  logic [VC_PER_PORT-1:0] consume_vc,
  output logic [VC_PER_PORT-1:0] credit_return,

  output logic [VC_PER_PORT-1:0] front_valid,
  output logic [VC_PER_PORT-1:0] front_is_head,
  output logic [VC_PER_PORT-1:0] front_is_tail,
  output logic [VC_PER_PORT-1:0][DATA_WIDTH-1:0] front_data
);

  localparam int FIFO_WORD_W = DATA_WIDTH + 2;

  logic [VC_PER_PORT-1:0] fifo_wr_en;
  logic [VC_PER_PORT-1:0] fifo_full;
  logic [VC_PER_PORT-1:0] fifo_empty;
  logic [VC_PER_PORT-1:0][FIFO_WORD_W-1:0] fifo_din;
  logic [VC_PER_PORT-1:0][FIFO_WORD_W-1:0] fifo_dout;

  genvar local_vc_g;
  generate
    for (local_vc_g = 0; local_vc_g < VC_PER_PORT; local_vc_g++) begin : GEN_LOCAL_VC
      SYNC_FIFO #(
        .WIDTH(FIFO_WORD_W),
        .DEPTH(FIFO_DEPTH)
      ) u_input_fifo (
        .CLK       (CLK),
        .RSTn      (RSTn),
        .WR_EN     (fifo_wr_en[local_vc_g]),
        .RD_EN     (consume_vc[local_vc_g]),
        .DATA_IN   (fifo_din[local_vc_g]),
        .FIFO_FULL (fifo_full[local_vc_g]),
        .FIFO_EMPTY(fifo_empty[local_vc_g]),
        .DATA_OUT  (fifo_dout[local_vc_g])
      );

      assign front_valid[local_vc_g]   = ~fifo_empty[local_vc_g];
      assign front_is_head[local_vc_g] = fifo_dout[local_vc_g][FIFO_WORD_W-1];
      assign front_is_tail[local_vc_g] = fifo_dout[local_vc_g][FIFO_WORD_W-2];
      assign front_data[local_vc_g]    = fifo_dout[local_vc_g][DATA_WIDTH-1:0];
    end
  endgenerate

  always_comb begin
    fifo_wr_en     = '0;
    fifo_din       = '0;
    in_ready       = 1'b0;
    credit_return  = consume_vc;

    if (in_vc_id < VC_PER_PORT) begin
      in_ready = ~fifo_full[in_vc_id];
      if (in_valid && ~fifo_full[in_vc_id]) begin
        fifo_wr_en[in_vc_id] = 1'b1;
        fifo_din[in_vc_id]   = {in_is_head, in_is_tail, in_flit_data};
      end
    end
  end

endmodule
