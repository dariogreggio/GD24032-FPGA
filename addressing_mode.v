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
	output reg [2:0] extra_bytes
);


`include "addressing_mode.vinc"

always @ * begin
  case (Ts)
    2'b00:
      begin
        case (Rs)
          3'b000:
            begin
              mode <= MODE_IMMEDIATE;
              extra_bytes <= 1;
            end
          3'b001:
            begin
              mode <= MODE_ZP;
              extra_bytes <= 1;
            end
          3'b010:
            begin
              mode <= MODE_NONE;
              extra_bytes <= 0;
            end
          3'b011:
            begin
              mode <= MODE_ABSOLUTE;
              extra_bytes <= 2;
            end
          3'b100:
            begin
              mode <= MODE_NONE;
              extra_bytes <= 1;
            end
          3'b101:
            begin
              if (Rd == 3'b000)
                mode <= MODE_ZP;
              else
                mode <= MODE_INDEXED_X;
              extra_bytes <= 1;
            end
          3'b110:
            begin
              mode <= MODE_NONE;
              extra_bytes <= 1;
            end
          3'b111:
            begin
              if (Rd == 3'b000 || Rd == 3'b100)
                mode <= MODE_ABSOLUTE;
              else
                mode <= MODE_ABSOLUTE_X;
              extra_bytes <= 2;
            end
        endcase
      end
    2'b01:
      begin
        case (Rs)
          3'b000:
            begin
              mode <= MODE_INDIRECT_X;
              extra_bytes <= 1;
            end
          3'b001:
            begin
              mode <= MODE_ZP;
              extra_bytes <= 1;
            end
          3'b010:
            begin
              mode <= MODE_IMMEDIATE;
              extra_bytes <= 0;
            end
          3'b011:
            begin
              mode <= MODE_ABSOLUTE;
              extra_bytes <= 2;
            end
          3'b100:
            begin
              mode <= MODE_INDIRECT_Y;
              extra_bytes <= 1;
            end
          3'b101:
            begin
              mode <= MODE_INDEXED_X;
              extra_bytes <= 1;
            end
          3'b110:
            begin
              mode <= MODE_ABSOLUTE_Y;
              extra_bytes <= 2;
            end
          3'b111:
            begin
              mode <= MODE_ABSOLUTE_X;
              extra_bytes <= 2;
            end
        endcase
      end
    2'b10:
      begin
        case (Rs)
          3'b000:
            begin
              mode <= MODE_IMMEDIATE;
              extra_bytes <= 0;
            end
          3'b001:
            begin
              mode <= MODE_ZP;
              extra_bytes <= 1;
            end
          3'b010:
            begin
              mode <= MODE_A;
              extra_bytes <= 0;
            end
          3'b011:
            begin
              mode <= MODE_ABSOLUTE;
              extra_bytes <= 2;
            end
          3'b100:
            begin
              mode <= MODE_INDIRECT;
              extra_bytes <= 1;
            end
          3'b101:
            begin
              mode <= MODE_INDEXED_X;
              extra_bytes <= 1;
            end
          3'b111:
            begin
              mode <= MODE_ABSOLUTE_Y;
              extra_bytes <= 2;
            end
          default:
            begin
              mode <= MODE_NONE;
              extra_bytes <= 0;
            end
        endcase
      end
    2'b11:
      begin
        case (Rs)
          3'b000:
            begin
              mode <= MODE_STACK_RELATIVE;
              extra_bytes <= 1;
            end
          3'b011:
            begin
              mode <= MODE_ABSOLUTE;
              extra_bytes <= 3;
            end
          3'b100:
            begin
            end
          3'b111:
            begin
              mode <= MODE_ABSOLUTE_X;
              extra_bytes <= 3;
            end
          default:
            begin
              mode <= MODE_NONE;
              extra_bytes <= 0;
            end
        endcase
      end
  endcase
end

endmodule

