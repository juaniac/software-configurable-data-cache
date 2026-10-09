`timescale 1ps/1ps

module semiDualPortSSRAMTestBench;
  reg clk; 
  reg reset;
  reg we;
  reg [8:0] addrA, addrB;
  reg [31:0] dataIn;
  wire [31:0] dataOutA, dataOutB;
  
  semiDualPortSSRAM DUT (
    .clkA(clk), 
    .clkB(clk), 
    .we(we),
    .addrA(addrA), 
    .addrB(addrB),
    .dataIn(dataIn),
    .dataOutA(dataOutA), 
    .dataOutB(dataOutB)
  );

  initial 
    begin
      reset = 1'b1;
      clk = 1'b0;                  /* set the initial values */

      repeat (4) #10 clk = ~clk; /* generate 2 clock periods */
      reset = 1'b0;                  /* de-activate the reset */
      forever #10 clk = ~clk;    /* generate a clock with a period of 10 time-units */
    end

  task assert(input reg [26*8:1] name, input [31:0] res, input [31:0] exp); 
    if (exp !== res) begin
      $display("ASSERTION FAILED [%s], EXPECTED: %x, BUT GOT: %x", name, exp, res);
      #10
      $finish;
    end 
  endtask

  initial
    begin
      $dumpfile("mem.vcd");    /* define the name of the .vcd file that can be viewed by GTKWAVE */
      $dumpvars(0, semiDualPortSSRAMTestBench); /* dump all signals inside the DUT-component in the .vcd file */
    end

  initial begin
    we = 0;
    addrA = 1;
    addrB = 1;
    dataIn = 3;
    @(negedge reset);
    @(negedge clk);
    we = 1;
    addrA = 1;
    addrB = 1;
    dataIn = 3;
    @(negedge clk);
    dataIn = 4;
    @(negedge clk);
    we = 0;
    @(negedge clk);
    @(negedge clk);
    we = 1;
    dataIn = 5;
    @(negedge clk);
    @(negedge clk);

    $display("\033[1;32m*** ALL TESTS PASSED ***\033[0m");
    $finish;
  end

endmodule