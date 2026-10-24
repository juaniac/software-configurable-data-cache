module sdp_ram (
  input wire clkA, clkB, 
  input wire we,
  input wire [8:0] addrA, addrB,
  input wire [31:0] dataIn,
  output reg [31:0] dataOutA, dataOutB
);

reg [31:0] mem[511:0];

integer i;
initial begin
  dataOutA = 32'b0;
  dataOutB = 32'b0;

  for (i = 0; i < 512; i=i+1)
    mem[i] = 32'b0;
end

always @(posedge clkA) begin
  dataOutA <= mem[addrA];
  if(we == 1) mem[addrA] <= dataIn;
end

always @(posedge clkB) begin
  dataOutB <= mem[addrB];
end

endmodule