// W65C832 FPGA Soft Processor
//  Author: Michael Kohn
//   Email: mike@mikekohn.net
//     Web: https://www.mikekohn.net/
//   Board: iceFUN iCE40 HX8K
// License: MIT
//
// Copyright 2024 by Michael Kohn
// GD 06/2026  superguerra daiiiiiii


module reg_mode(
  input m,
  input x,
  output reg [2:0] size_m,
  output reg [2:0] size_x
);

`include "reg_mode.vinc"
  
// E16  E8   M   X    A    X,Y    Mode
//  1    1   1  BRK   8     8     W65C02  Emulation

always @ * begin
      size_m <= SIZE_8;
      size_x <= SIZE_8;
end

endmodule

