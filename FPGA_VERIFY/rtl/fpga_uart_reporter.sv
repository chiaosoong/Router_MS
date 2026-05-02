module fpga_uart_reporter #(
  parameter int CLKS_PER_BIT = 16
) (
  input  logic                           CLK,
  input  logic                           RSTn,
  input  fpga_verify_pkg::report_event_t in_event,
  input  logic                           in_valid,
  output logic                           in_ready,
  output logic                           UART_TX
);
  import fpga_verify_pkg::*;

  typedef enum logic [1:0] {
    TX_IDLE,
    TX_SEND
  } tx_state_t;

  localparam int LINE_BUF_W  = REPORT_TEXT_BYTES * 8;
  localparam int BYTE_IDX_W  = (REPORT_TEXT_BYTES <= 2) ? 1 : $clog2(REPORT_TEXT_BYTES);
  localparam int BIT_IDX_W   = 3;
  localparam int CLKS_W      = (CLKS_PER_BIT <= 2) ? 1 : $clog2(CLKS_PER_BIT);

  tx_state_t              tx_state;
  logic [CLKS_W-1:0]      clk_ctr;
  logic [3:0]             bit_idx;
  logic [BYTE_IDX_W-1:0]  char_idx;
  logic [BYTE_IDX_W:0]    line_len;
  logic [LINE_BUF_W-1:0]  line_buf;
  logic [7:0]             shifter;
  logic                   line_active;

  logic [LINE_BUF_W-1:0]  fmt_buf;
  logic [BYTE_IDX_W:0]    fmt_len;

  task automatic putc(
    inout logic [LINE_BUF_W-1:0] line_bits,
    inout int                    idx,
    input logic [7:0]            ch
  );
    begin
      if (idx < REPORT_TEXT_BYTES) begin
        line_bits[idx*8 +: 8] = ch;
      end
      idx = idx + 1;
    end
  endtask

  function automatic logic [7:0] hex_char(input logic [3:0] nibble);
    case (nibble)
      4'h0: hex_char = "0";
      4'h1: hex_char = "1";
      4'h2: hex_char = "2";
      4'h3: hex_char = "3";
      4'h4: hex_char = "4";
      4'h5: hex_char = "5";
      4'h6: hex_char = "6";
      4'h7: hex_char = "7";
      4'h8: hex_char = "8";
      4'h9: hex_char = "9";
      4'hA: hex_char = "A";
      4'hB: hex_char = "B";
      4'hC: hex_char = "C";
      4'hD: hex_char = "D";
      4'hE: hex_char = "E";
      default: hex_char = "F";
    endcase
  endfunction

  task automatic put_hex1(
    inout logic [LINE_BUF_W-1:0] line_bits,
    inout int                    idx,
    input logic [3:0]            value
  );
    begin
      putc(line_bits, idx, hex_char(value));
    end
  endtask

  task automatic put_hex2(
    inout logic [LINE_BUF_W-1:0] line_bits,
    inout int                    idx,
    input logic [7:0]            value
  );
    begin
      putc(line_bits, idx, hex_char(value[7:4]));
      putc(line_bits, idx, hex_char(value[3:0]));
    end
  endtask

  task automatic put_hex4(
    inout logic [LINE_BUF_W-1:0] line_bits,
    inout int                    idx,
    input logic [15:0]           value
  );
    begin
      putc(line_bits, idx, hex_char(value[15:12]));
      putc(line_bits, idx, hex_char(value[11:8]));
      putc(line_bits, idx, hex_char(value[7:4]));
      putc(line_bits, idx, hex_char(value[3:0]));
    end
  endtask

  task automatic put_hex8(
    inout logic [LINE_BUF_W-1:0] line_bits,
    inout int                    idx,
    input logic [31:0]           value
  );
    begin
      put_hex4(line_bits, idx, value[31:16]);
      put_hex4(line_bits, idx, value[15:0]);
    end
  endtask

  always_comb begin
    int idx;

    fmt_buf = '0;
    idx     = 0;

    unique case (in_event.event_type)
      EVT_CASE_START: begin
        putc(fmt_buf, idx, "C");
        putc(fmt_buf, idx, "A");
        putc(fmt_buf, idx, "S");
        putc(fmt_buf, idx, "E");
        putc(fmt_buf, idx, "_");
        putc(fmt_buf, idx, "S");
        putc(fmt_buf, idx, "T");
        putc(fmt_buf, idx, "A");
        putc(fmt_buf, idx, "R");
        putc(fmt_buf, idx, "T");
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.case_id);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pkt_total);
      end

      EVT_PKT_INJ: begin
        putc(fmt_buf, idx, "P");
        putc(fmt_buf, idx, "K");
        putc(fmt_buf, idx, "T");
        putc(fmt_buf, idx, "_");
        putc(fmt_buf, idx, "I");
        putc(fmt_buf, idx, "N");
        putc(fmt_buf, idx, "J");
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.case_id);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pkt_id);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.src_rid);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.dst_rid);
        putc(fmt_buf, idx, ",");
        put_hex1(fmt_buf, idx, {1'b0, in_event.msg_class});
        putc(fmt_buf, idx, ",");
        put_hex1(fmt_buf, idx, in_event.vc_id);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.pkt_len);
        putc(fmt_buf, idx, ",");
        put_hex8(fmt_buf, idx, in_event.latency);
      end

      EVT_PKT_DONE: begin
        putc(fmt_buf, idx, "P");
        putc(fmt_buf, idx, "K");
        putc(fmt_buf, idx, "T");
        putc(fmt_buf, idx, "_");
        putc(fmt_buf, idx, "D");
        putc(fmt_buf, idx, "O");
        putc(fmt_buf, idx, "N");
        putc(fmt_buf, idx, "E");
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.case_id);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pkt_id);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.src_rid);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.dst_rid);
        putc(fmt_buf, idx, ",");
        put_hex1(fmt_buf, idx, {1'b0, in_event.msg_class});
        putc(fmt_buf, idx, ",");
        put_hex1(fmt_buf, idx, in_event.vc_id);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.pkt_len);
        putc(fmt_buf, idx, ",");
        putc(fmt_buf, idx, "P");
        putc(fmt_buf, idx, "A");
        putc(fmt_buf, idx, "S");
        putc(fmt_buf, idx, "S");
        putc(fmt_buf, idx, ",");
        put_hex8(fmt_buf, idx, in_event.latency);
      end

      EVT_PKT_FAIL: begin
        putc(fmt_buf, idx, "P");
        putc(fmt_buf, idx, "K");
        putc(fmt_buf, idx, "T");
        putc(fmt_buf, idx, "_");
        putc(fmt_buf, idx, "F");
        putc(fmt_buf, idx, "A");
        putc(fmt_buf, idx, "I");
        putc(fmt_buf, idx, "L");
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.case_id);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pkt_id);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.src_rid);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.dst_rid);
        putc(fmt_buf, idx, ",");
        put_hex1(fmt_buf, idx, {1'b0, in_event.msg_class});
        putc(fmt_buf, idx, ",");
        put_hex1(fmt_buf, idx, in_event.vc_id);
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.pkt_len);
        putc(fmt_buf, idx, ",");
        putc(fmt_buf, idx, "F");
        putc(fmt_buf, idx, "A");
        putc(fmt_buf, idx, "I");
        putc(fmt_buf, idx, "L");
        putc(fmt_buf, idx, ",");
        put_hex2(fmt_buf, idx, in_event.error_code);
        putc(fmt_buf, idx, ",");
        put_hex8(fmt_buf, idx, in_event.latency);
      end

      EVT_CASE_DONE: begin
        putc(fmt_buf, idx, "C");
        putc(fmt_buf, idx, "A");
        putc(fmt_buf, idx, "S");
        putc(fmt_buf, idx, "E");
        putc(fmt_buf, idx, "_");
        putc(fmt_buf, idx, "D");
        putc(fmt_buf, idx, "O");
        putc(fmt_buf, idx, "N");
        putc(fmt_buf, idx, "E");
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.case_id);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pkt_done);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pass_count);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.fail_count);
        putc(fmt_buf, idx, ",");
        put_hex8(fmt_buf, idx, in_event.latency_sum);
        putc(fmt_buf, idx, ",");
        put_hex8(fmt_buf, idx, in_event.latency_min);
        putc(fmt_buf, idx, ",");
        put_hex8(fmt_buf, idx, in_event.latency_max);
      end

      EVT_PROGRESS: begin
        putc(fmt_buf, idx, "P");
        putc(fmt_buf, idx, "R");
        putc(fmt_buf, idx, "O");
        putc(fmt_buf, idx, "G");
        putc(fmt_buf, idx, "R");
        putc(fmt_buf, idx, "E");
        putc(fmt_buf, idx, "S");
        putc(fmt_buf, idx, "S");
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.case_done);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.case_total);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pkt_done);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pkt_total);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pass_count);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.fail_count);
      end

      EVT_ALL_DONE: begin
        putc(fmt_buf, idx, "A");
        putc(fmt_buf, idx, "L");
        putc(fmt_buf, idx, "L");
        putc(fmt_buf, idx, "_");
        putc(fmt_buf, idx, "D");
        putc(fmt_buf, idx, "O");
        putc(fmt_buf, idx, "N");
        putc(fmt_buf, idx, "E");
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.case_total);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pkt_total);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.pass_count);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.fail_count);
        putc(fmt_buf, idx, ",");
        put_hex4(fmt_buf, idx, in_event.error_code);
      end

      default: begin
        putc(fmt_buf, idx, "U");
        putc(fmt_buf, idx, "N");
        putc(fmt_buf, idx, "K");
        putc(fmt_buf, idx, "N");
        putc(fmt_buf, idx, "O");
        putc(fmt_buf, idx, "W");
        putc(fmt_buf, idx, "N");
      end
    endcase

    putc(fmt_buf, idx, 8'h0A);
    fmt_len = idx[BYTE_IDX_W:0];
  end

  assign in_ready = !line_active;

  always_comb begin
    if (tx_state == TX_IDLE) begin
      UART_TX = 1'b1;
    end else if (bit_idx == 4'd0) begin
      UART_TX = 1'b0;
    end else if (bit_idx == 4'd9) begin
      UART_TX = 1'b1;
    end else begin
      UART_TX = shifter[bit_idx-1];
    end
  end

  always_ff @(posedge CLK or negedge RSTn) begin
    if (!RSTn) begin
      tx_state    <= TX_IDLE;
      clk_ctr     <= '0;
      bit_idx     <= '0;
      char_idx    <= '0;
      line_len    <= '0;
      line_buf    <= '0;
      shifter     <= 8'h00;
      line_active <= 1'b0;
    end else begin
      if (!line_active && in_valid && in_ready) begin
        line_buf    <= fmt_buf;
        line_len    <= fmt_len;
        char_idx    <= '0;
        shifter     <= fmt_buf[7:0];
        line_active <= 1'b1;
        tx_state    <= TX_SEND;
        clk_ctr     <= '0;
        bit_idx     <= '0;
      end else begin
        case (tx_state)
          TX_IDLE: begin
            tx_state <= TX_IDLE;
          end

          TX_SEND: begin
            if (clk_ctr == CLKS_PER_BIT-1) begin
              clk_ctr <= '0;
              if (bit_idx == 4'd9) begin
                if (char_idx + BYTE_IDX_W'(1) >= line_len[BYTE_IDX_W-1:0]) begin
                  tx_state    <= TX_IDLE;
                  line_active <= 1'b0;
                end else begin
                  char_idx <= char_idx + BYTE_IDX_W'(1);
                  shifter  <= line_buf[(char_idx + BYTE_IDX_W'(1))*8 +: 8];
                  bit_idx  <= '0;
                  tx_state <= TX_SEND;
                end
              end else begin
                bit_idx <= bit_idx + 4'd1;
              end
            end else begin
              clk_ctr <= clk_ctr + CLKS_W'(1);
            end
          end

          default: begin
            tx_state <= TX_IDLE;
          end
        endcase
      end
    end
  end
endmodule
