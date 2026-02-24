`timescale 1ns/1ps
module TB_ASYNC_FIFO();
    parameter WIDTH  = 8;
    parameter DEPTH  = 16;
    parameter ADDR_W = $clog2(DEPTH);
    parameter PTR_W  = ADDR_W + 1;
    parameter RPERIOD = 50; // read frrequency = 20 MHz
    parameter WPERIOD = 20; // write requency = 50 MHz

    logic RCLK, RRSTn, RINC;
    logic WCLK, WRSTn, WINC;
    logic [WIDTH-1:0] WDATA, RDATA;
    logic WFULL, REMPTY;

    // Read and write clock Generation
    initial begin RCLK = 0; WCLK = 0; end
    always #(RPERIOD/2) RCLK = ~RCLK;
    always #(WPERIOD/2) WCLK = ~WCLK;

    // DUT Instantiation
    ASYNC_FIFO #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .PTR_W(PTR_W)
    ) dut_sync_fifo (.*);

    integer i;


    initial begin
        // --- 1. Initialize Signals ---
        RRSTn <= 0;
        WRSTn <= 0;
        WINC  <= 0;
        RINC  <= 0;
        WDATA <= 0;

        // --- 2. Reset Sequence ---
        #(RPERIOD * 2);
        RRSTn <= 1;
        WRSTn <= 1;
        @(posedge WCLK); // Wait for a clean edge

        // --- 3. Only Write (Fill half) ---
        for (i = 0; i < 8; i++) begin
            wr_fifo(i);
        end
        WINC = 0; // Turn off write after loop

        // --- 4. Simultaneous Read/Write ---
        RINC = 1;
        for (i = 8; i < 16; i++) begin 
            wr_fifo(i);
        end
        RINC = 0;
        WINC = 0;

        // --- 5. Empty the FIFO ---
        repeat(16) begin
            rd_fifo();
        end
        RINC = 0;

        #(RPERIOD * 5);
        // --- 6. Only Write (make FIFO full) ---
        for (i = 0; i < 32; i++) begin
            wr_fifo(i);
        end
        $display("Simulation Finished");
        $finish();
    end

    task wr_fifo(input [WIDTH-1:0] w_data);
        begin
            @(posedge WCLK); // Synchronize to write clock
            #1;              // Small skew to mimic real-world setup time
            WINC = 1;
            WDATA = w_data;
            @(posedge WCLK);
            #1;
            WINC = 0;
        end
    endtask

    task rd_fifo();
        begin
            @(posedge RCLK);
            #1;
            RINC = 1;
            @(posedge RCLK);
            #1;
            RINC = 0;
        end
    endtask

endmodule
