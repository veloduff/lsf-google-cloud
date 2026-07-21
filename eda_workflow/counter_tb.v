// =====================================================================
// Testbench for 4-Bit Counter - counter_tb.v
// =====================================================================
`timescale 1ns/1ps

module counter_tb;

reg clk;
reg rst_n;
reg enable;
wire [3:0] count;

// Instantiate the Unit Under Test (UUT)
counter uut (
    .clk(clk),
    .rst_n(rst_n),
    .enable(enable),
    .count(count)
);

// Clock generation (100MHz)
always #5 clk = ~clk;

initial begin
    // Initialize signals
    clk = 0;
    rst_n = 0;
    enable = 0;

    // Open dump file for waveform viewing
    $dumpfile("counter.vcd");
    $dumpvars(0, counter_tb);

    // Reset sequence
    #20;
    rst_n = 1;
    #10;
    
    // Enable counting
    enable = 1;
    #150; // Count for 15 clock cycles
    
    // Disable counting
    enable = 0;
    #20;

    // Verify counter did not increment while disabled
    if (count != 4'd15) begin
        $display("ERROR: Counter failed! Expected 15, got %d", count);
        $finish_and_return(1);
    end else begin
        $display("SUCCESS: Counter testbench passed! Final count is %d", count);
        $finish_and_return(0);
    end
end

initial begin
    $monitor("At time %t: rst_n=%b, enable=%b, count=%d", $time, rst_n, enable, count);
end

endmodule
