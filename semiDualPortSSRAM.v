module semiDualPortSSRAM # (
  parameter bitwidth = 32,
  parameter nrOfEntries = 512
)(
  input wire clkA, clkB, 
  input wire we,
  input wire [$clog2(nrOfEntries)-1 : 0] addrA, addrB,
  input wire [bitwidth-1 : 0] dataIn,
  output reg [bitwidth-1 : 0] dataOutA, dataOutB
);

reg [bitwidth-1 : 0] mem[$clog2(nrOfEntries)-1 : 0];

always @(posedge clkA) begin
  dataOutA <= mem[addrA];
  if(we == 1) mem[addrA] <= dataIn;
end

always @(posedge clkB) begin
  dataOutB <= mem[addrB];
end

endmodule