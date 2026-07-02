// W65C832 FPGA Soft Processor
//  Author: Michael Kohn
//   Email: mike@mikekohn.net
//     Web: https://www.mikekohn.net/
//   Board: iceFUN iCE40 HX8K
// License: MIT
//
// Copyright 2024 by Michael Kohn
// Adapted by GD on 30/6/96 for Cyclone EPC4CE6E22

// This creates 4096 bytes of RAM on the FPGA itself which begins at 0x0000.

module ram(
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

