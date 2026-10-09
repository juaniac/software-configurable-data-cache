`timescale 1ps/1ps

module data_cache_tb;
  reg clk; 
  reg rst;
  reg we;

  reg [31:0] i_input;
  wire [31:0] o_output [31:0];

  data_cache dut (
  .i_clk(clk),
  .i_rst_n(rst),

  // ahb5 interface
  .i_ahb5_addr(i_input),    
  .i_ahb5_we(we),
  .i_ahb5_trans(i_input[1:0]),    
  .i_ahb5_size(i_input[2:0]),
  .i_ahb5_wdata(i_input),
  .o_ahb5_rdata(o_output[0]),
  .o_ahb5_ready(o_output[1][0]),
  .o_ahb5_resp(o_output[2][0]),

  // wishbone interface
  .o_wb_cyc(o_output[3][0]),
  .o_wb_stb(o_output[4][0]),
  .o_wb_we(o_output[5][0]),
  .o_wb_bte(o_output[6][1:0]),
  .o_wb_cti(o_output[7][2:0]),
  .o_wb_sel(o_output[8][3:0]),
  .o_wb_addr(o_output[9]),
  .o_wb_wdata(o_output[10]),
  .i_wb_rdata(i_input),
  .i_wb_ack(i_input[0]),
  .i_wb_err(i_input[0])
);

  initial 
    begin
      rst = 1'b1;
      clk = 1'b0;                  /* set the initial values */

      repeat (4) #10 clk = ~clk; /* generate 2 clock periods */
      rst = 1'b0;                  /* de-activate the reset */
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
      $dumpvars(1, data_cache_tb); /* dump all signals inside the DUT-component in the .vcd file */
    end

  initial begin

    $display("\033[1;32m*** ALL TESTS PASSED ***\033[0m");
    $finish;
  end

endmodule