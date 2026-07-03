// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii

// This creates 8192 bytes of ROM on the FPGA itself which begins at 0x00000000.

module rom(
  input [10:0] address,
  output reg [31:0] data_out,
  input clk
);

reg [31:0] memory [2047:0];

initial begin
  $readmemh("rom.txt", memory);
end

always @(posedge clk) begin
  data_out <= memory[address[10:0]];
end

endmodule

