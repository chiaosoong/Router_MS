module fpga_report_fifo #(
  parameter int DEPTH = 8
) (
  input  logic                           CLK,
  input  logic                           RSTn,
  input  fpga_verify_pkg::report_event_t in_event,
  input  logic                           in_valid,
  output logic                           in_ready,
  output fpga_verify_pkg::report_event_t out_event,
  output logic                           out_valid,
  input  logic                           out_ready
);
  import fpga_verify_pkg::*;

  localparam int PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);

  report_event_t mem [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr;
  logic [PTR_W-1:0] rd_ptr;
  logic [PTR_W:0]   used_count;

  logic push_fire;
  logic pop_fire;

  assign push_fire = in_valid && in_ready;
  assign pop_fire  = out_valid && out_ready;

  assign in_ready  = (used_count < DEPTH);
  assign out_valid = (used_count != 0);
  assign out_event = mem[rd_ptr];

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      int idx;
      wr_ptr     <= '0;
      rd_ptr     <= '0;
      used_count <= '0;
      for (idx = 0; idx < DEPTH; idx++) begin
        mem[idx] <= '0;
      end
    end else begin
      if (push_fire) begin
        mem[wr_ptr] <= in_event;
        if (wr_ptr == DEPTH-1) begin
          wr_ptr <= '0;
        end else begin
          wr_ptr <= wr_ptr + PTR_W'(1);
        end
      end

      if (pop_fire) begin
        if (rd_ptr == DEPTH-1) begin
          rd_ptr <= '0;
        end else begin
          rd_ptr <= rd_ptr + PTR_W'(1);
        end
      end

      case ({push_fire, pop_fire})
        2'b10: used_count <= used_count + (PTR_W+1)'(1);
        2'b01: used_count <= used_count - (PTR_W+1)'(1);
        default: used_count <= used_count;
      endcase
    end
  end
endmodule
