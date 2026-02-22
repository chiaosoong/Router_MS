/**********************************
* Parametrized synchronous FIFO:
* 1) the design uses a counter to indicate whether FIFO is full/empty
* 2) write-through/bypass policy when simultaneous w&r to same addr
**********************************/
module SYNC_FIFO #(
	parameter WIDTH  = 8,             // data width, # of bits per word
	parameter DEPTH  = 16,            // FIFO depth, # of words
	parameter PTR_W  = $clog2(DEPTH)  // pointer width
)(
	input CLK,
	input RSTn,
	input WR_EN, RD_EN,               // write and read enable
	input [WIDTH-1:0] DATA_IN,        // FIFO write data

	output FIFO_FULL, FIFO_EMPTY,     // indicates whether FIFO is full/empty
	output [WIDTH-1:0] DATA_OUT       // FIFO read data
);

// pointer to write and read address
logic [PTR_W-1:0] wr_pointer, rd_pointer;
// counter indicating # of occupied FIFO word
logic [PTR_W:0] fifo_cnt;

// RAM read and write enable
logic ram_wr_en, ram_rd_en;
always_comb begin
  ram_wr_en = 1'b0;
  if (WR_EN && ~FIFO_FULL) begin
    if (RD_EN && (wr_pointer == rd_pointer))
      ram_wr_en = 1'b0;
    else
      ram_wr_en = 1'b1;
  end
end
always_comb begin
  ram_rd_en = 1'b0;
  if (RD_EN && ~FIFO_EMPTY) begin
    if (WR_EN && (wr_pointer == rd_pointer))
      ram_rd_en = 1'b0;
    else
      ram_rd_en = 1'b1;
  end
end
logic [WIDTH-1:0] ram_data_out;
DP_RAM #(
	.WIDTH(WIDTH),
	.DEPTH(DEPTH),
	.ADDR_W(PTR_W)
) u0_dp_ram (
	.RSTn(RSTn),
	.WR_CLK(CLK),
	.RD_CLK(CLK),
	.WR_EN(ram_wr_en),
	.RD_EN(ram_rd_en),
	.WR_ADDR(wr_pointer),
	.RD_ADDR(rd_pointer),
	.WR_DATA(DATA_IN),
	.RD_DATA(ram_data_out)
);

//--------------------------------------------------
// write pointer: increments when write enable and FIFO not full
// read pointer: increments when read enable and FIFO not empty
// FIFO counter: indicates FIFO empty/full
//--------------------------------------------------
always_ff @(posedge CLK) begin
  if (!RSTn) {rd_pointer, wr_pointer, fifo_cnt} <= 0;
  else begin
    case ({WR_EN, RD_EN})
      2'b10: if (!FIFO_FULL) begin
        wr_pointer <= wr_pointer + 1;
        fifo_cnt   <= fifo_cnt + 1;
      end
      2'b01: if (!FIFO_EMPTY) begin
        rd_pointer <= rd_pointer + 1;
        fifo_cnt   <= fifo_cnt - 1;
      end
      2'b11: begin
        wr_pointer <= wr_pointer + 1;
        rd_pointer <= rd_pointer + 1;
        // count unchanged
      end
      default: begin
        {rd_pointer, wr_pointer, fifo_cnt} <= {rd_pointer, wr_pointer, fifo_cnt};
      end
    endcase
  end
end

assign FIFO_FULL  = (fifo_cnt == 2**PTR_W);
assign FIFO_EMPTY = (fifo_cnt == 'h0);

//--------------------------------------------------
// Bypass/Wirte-through logic:
// bypass the input data when simultaneous read and write
// along with two equal pointers
//--------------------------------------------------
logic bypass_en, bypass_en_reg;
assign bypass_en = (wr_pointer == rd_pointer) && RD_EN && WR_EN;

logic [WIDTH-1:0] data_in_reg;
always_ff @(posedge CLK) begin
  if (!RSTn) begin
    data_in_reg   <= 'h0;
    bypass_en_reg <= 1'b0;
  end
  else begin
    data_in_reg   <= DATA_IN;
    bypass_en_reg <= bypass_en;
  end
end

assign DATA_OUT = bypass_en_reg ? data_in_reg : ram_data_out;

endmodule
