// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii

// This creates 8192 bytes of RAM on the FPGA itself which begins at 0x00100000.

module ram(
  input  [10:0] address,
  input  [31:0] data_in,
  output reg [31:0] data_out,
  input write_enable,
  input clk
);

reg [31:0] memory [2047:0];

always @(posedge clk) begin
  if (write_enable) begin
    memory[address] <= data_in;
  end else
    data_out <= memory[address];
end

endmodule

module cgaram(
  input  [11:0] address,
  input  [7:0] data_in,
  output reg [7:0] data_out,
  input write_enable,
  input clk
);

reg [7:0] memory [4095:0];

always @(posedge clk) begin
  if (write_enable) begin
    memory[address] <= data_in;
  end else
    data_out <= memory[address];
end

endmodule

