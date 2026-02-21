`timescale 1ns/1ps
module TB_SYNC_FIFO();
    parameter WIDTH = 8;
    parameter DEPTH = 16;
    parameter PTR_W = $clog2(DEPTH);
    parameter PERIOD = 20;

    logic CLK, RSTn;
    logic WR_EN, RD_EN;
    logic [WIDTH-1:0] DATA_IN;
    logic FIFO_FULL, FIFO_EMPTY;
    logic [WIDTH-1:0] DATA_OUT;

    // 50MHz clock Generation
    initial CLK = 0;
    always #(PERIOD/2) CLK = ~CLK;

    // DUT Instantiation
    SYNC_FIFO #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .PTR_W(PTR_W)
    ) dut_sync_fifo (.*);

    integer i;

    initial begin
        // --- 1. Initialize Signals ---
        RSTn    <= 0;
        WR_EN   <= 0;
        RD_EN   <= 0;
        DATA_IN <= 0;

        // --- 2. Reset Sequence ---
        #(PERIOD * 2);
        RSTn <= 1;
        @(posedge CLK); // Wait for a clean edge

        // --- 3. Only Write (Fill half) ---
        for (i = 0; i < 8; i++) begin 
            wr_fifo(i); 
        end
        WR_EN = 0; // Turn off write after loop

        // --- 4. Simultaneous Read/Write ---
        RD_EN = 1;
        for (i = 8; i < 16; i++) begin 
            wr_fifo(i); 
        end
        RD_EN = 0;
        WR_EN = 0;

        // --- 5. Empty the FIFO ---
        repeat(16) begin
            rd_fifo();
        end
        RD_EN = 0;

        #(PERIOD * 5);
        $display("Simulation Finished");
        $finish();
    end

    // --- Updated Tasks ---
    
    task wr_fifo(input [WIDTH-1:0] w_data);
        begin
            @(posedge CLK); // Synchronize to clock
            #1;             // Small skew to mimic real-world setup time
            WR_EN = 1;
            DATA_IN = w_data;
            @(posedge CLK);
            #1;
            WR_EN = 0;
        end
    endtask

    task rd_fifo();
        begin
            @(posedge CLK);
            #1;
            RD_EN = 1;
            @(posedge CLK);
            #1;
            RD_EN = 0;
        end
    endtask

endmodule
