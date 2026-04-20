/**********************************
* Parametrized synchronous FIFO:
* 1) the design uses a counter to indicate whether FIFO is full/empty
* 2) DATA_OUT always exposes the current front entry
**********************************/
module SYNC_FIFO #(
  parameter WIDTH  = 32,
  parameter DEPTH  = 4,
  parameter PTR_W  = $clog2(DEPTH)
)(
  input                     CLK,
  input                     RSTn,
  input                     WR_EN,
  input                     RD_EN,
  input [WIDTH-1:0]         DATA_IN,

  output logic              FIFO_FULL,
  output logic              FIFO_EMPTY,
  output logic [WIDTH-1:0]  DATA_OUT
);

  logic [PTR_W-1:0] wr_pointer, rd_pointer;
  logic [PTR_W:0]   fifo_cnt;
  logic [WIDTH-1:0] mem [0:DEPTH-1];

  integer i;
  always_ff @(posedge CLK) begin
    if (!RSTn) begin
      wr_pointer <= '0;
      rd_pointer <= '0;
      fifo_cnt   <= '0;
      for (i = 0; i < DEPTH; i++) begin
        mem[i] <= '0;
      end
    end
    else begin
      case ({WR_EN, RD_EN})
        //  write to FIFO
        2'b10: begin
          if (!FIFO_FULL) begin
            mem[wr_pointer] <= DATA_IN;
            wr_pointer      <= wr_pointer + 1'b1;
            fifo_cnt        <= fifo_cnt + 1'b1;
          end
        end
        //  read from FIFO
        2'b01: begin
          if (!FIFO_EMPTY) begin
            rd_pointer <= rd_pointer + 1'b1;
            fifo_cnt   <= fifo_cnt - 1'b1;
          end
        end
        //  simultaneous read and write
        2'b11: begin
          if (FIFO_EMPTY) begin         // Bypass DATA_IN
            wr_pointer <= wr_pointer;
            rd_pointer <= rd_pointer;
            fifo_cnt   <= fifo_cnt;
          end
          else begin
            mem[wr_pointer] <= DATA_IN; // Rd before write
            wr_pointer      <= wr_pointer + 1'b1;
            rd_pointer      <= rd_pointer + 1'b1;
            fifo_cnt        <= fifo_cnt;
          end
        end
        default: begin
          wr_pointer <= wr_pointer;
          rd_pointer <= rd_pointer;
          fifo_cnt   <= fifo_cnt;
        end
      endcase
    end
  end

  assign FIFO_FULL  = (fifo_cnt == DEPTH);
  assign FIFO_EMPTY = (fifo_cnt == '0);

  always_comb begin
    if (FIFO_EMPTY && WR_EN && RD_EN) begin
      DATA_OUT = DATA_IN;         // Bypass when empty and simultaneous rd ^ wr
    end
    else if (!FIFO_EMPTY) begin
      DATA_OUT = mem[rd_pointer]; // Always expose front entry
    end
    else begin
      DATA_OUT = '0;
    end
  end

endmodule
