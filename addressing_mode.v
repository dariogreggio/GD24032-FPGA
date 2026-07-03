// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii

module addressing_mode(
	input [2:0] Mm,
	input [4:0] Rs,
	input [3:0] Ts,
	input [4:0] Rd,
	input [3:0] Td,
	input [1:0] Sz,
	output reg [3:0] mode,
	output reg [2:0] extra_words
);


`include "addressing_mode.vinc"

always @ * begin
  case (Ts)
    4'h0:
      begin
      end
    4'h1:
      begin
      end
    4'h2:
      begin
      end
    4'h3:
      begin
      end
    4'h4:
      begin
      end
    4'h5:
      begin
      end
    4'h6:
      begin
      end
    4'h8:
      begin
      end
    4'h9:
      begin
      end
    4'ha:
      begin
      end
    4'hb:
      begin
      end
    4'hc:
      begin
      end
    4'hd:
      begin
      end
    4'he:
      begin
      end
  endcase
end

endmodule

