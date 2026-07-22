// 32bit ALU (based upon 8-bit ALU implementation in Basys3 Board

module ALU (
  input  [1:0] size,
  input  [31:0] A,
  input  [31:0] B,
  input  C,
  input  [5:0] sel,		// b5:b0 di Opcode, da 0h (20h) = ADD a Ch (58h) = NOR, poi fare ROTATE (70h)...
  output reg [31:0] result,
  output reg zero,
  output reg sign,
  output reg carry,
  output reg halfcarry,
  output reg overflow
);

`include "reg_mode.vinc"

always @(*) begin
    carry = 0;
    halfcarry = 0;
    overflow = 0;
    result = 32'h0;

    case (size)
			SIZE_8:
				case (sel)
					6'b010000: {carry, result} = A[7:0] + B[7:0];               // ADD
					6'b010001: {carry, result} = A[7:0] + B[7:0] + C;           // ADC
					6'b010010: {carry, result} = A[7:0] - B[7:0];               // SUB
					6'b010011: {carry, result} = A[7:0] - B[7:0] - C;           // SBC
					6'b011000: result = A[7:0] & B[7:0];                        // AND
					6'b011001: result = A[7:0] | B[7:0];                        // OR
					6'b011010: result = A[7:0] ^ B[7:0];                        // XOR
					6'b011100: result = A[7:0] * B[7:0];                        // Multiplication
					6'b011101: result = A[7:0] * B[7:0];                        // Multiplication signed
					6'b011110: result = (B[7:0] != 0) ? A[7:0] / B[7:0] : 32'b0; // Division
					6'b011111: result = (B[7:0] != 0) ? A[7:0] / B[7:0] : 32'b0; // Division signed
	//        6'b1100: result = (B != 0) ? A % B : 32'h0; // Modulo
	//        6'b1101: result = (A == B) ? 8'b00000001 : 8'b00000000; // A == B
	//        6'b1110: result = (A > B)  ? 8'b00000001 : 8'b00000000; // A > B
					6'b101110: result = ~A[7:0];                           // NOT A
	//        6'b1111: result = (A < B)  ? 8'b00000001 : 8'b00000000; // A < B
					6'b111000: result = A << 1;                       // Shift Left
					6'b111001: result = A >> 1;                       // Shift Right
					default: result = 32'h0;
				endcase
			SIZE_16:
				case (sel)
					6'b010000: {carry, result} = A[15:0] + B[15:0];               // ADD
					6'b010001: {carry, result} = A[15:0] + B[15:0] + C;           // ADC
					6'b010010: {carry, result} = A[15:0] - B[15:0];               // SUB
					6'b010011: {carry, result} = A[15:0] - B[15:0] - C;           // SBC
					6'b011000: result = A[15:0] & B[15:0];                        // AND
					6'b011001: result = A[15:0] | B[15:0];                        // OR
					6'b011010: result = A[15:0] ^ B[15:0];                        // XOR
					6'b011100: result = A[15:0] * B[15:0];                        // Multiplication
					6'b011101: result = A[15:0] * B[15:0];                        // Multiplication signed
					6'b011110: result = (B[15:0] != 0) ? A[15:0] / B[15:0] : 32'b0; // Division
					6'b011111: result = (B[15:0] != 0) ? A[15:0] / B[15:0] : 32'b0; // Division signed
	//        6'b1100: result = (B != 0) ? A % B : 32'h0; // Modulo
	//        6'b1101: result = (A == B) ? 8'b00000001 : 8'b00000000; // A == B
	//        6'b1110: result = (A > B)  ? 8'b00000001 : 8'b00000000; // A > B
					6'b101110: result = ~A[15:0];                           // NOT A
	//        6'b1111: result = (A < B)  ? 8'b00000001 : 8'b00000000; // A < B
					6'b111000: result = A << 1;                       // Shift Left
					6'b111001: result = A >> 1;                       // Shift Right
					default: result = 32'h0;
				endcase
			SIZE_32:
				case (sel)
					6'b010000: {carry, result} = A[31:0] + B[31:0];               // ADD
					6'b010001: {carry, result} = A[31:0] + B[31:0] + C;           // ADC
					6'b010010: {carry, result} = A[31:0] - B[31:0];               // SUB
					6'b010011: {carry, result} = A[31:0] - B[31:0] - C;           // SBC
					6'b011000: result = A[31:0] & B[31:0];                        // AND
					6'b011001: result = A[31:0] | B[31:0];                        // OR
					6'b011010: result = A[31:0] ^ B[31:0];                        // XOR
					6'b011100: result = A[31:0] * B[31:0];                        // Multiplication
					6'b011101: result = A[31:0] * B[31:0];                        // Multiplication signed
					6'b011110: result = (B[31:0] != 0) ? A[31:0] / B[31:0] : 32'b0; // Division
					6'b011111: result = (B[31:0] != 0) ? A[31:0] / B[31:0] : 32'b0; // Division signed
	//        6'b1100: result = (B != 0) ? A % B : 32'h0; // Modulo
	//        6'b1101: result = (A == B) ? 8'b00000001 : 8'b00000000; // A == B
	//        6'b1110: result = (A > B)  ? 8'b00000001 : 8'b00000000; // A > B
					6'b101110: result = ~A[31:0];                           // NOT A
	//        6'b1111: result = (A < B)  ? 8'b00000001 : 8'b00000000; // A < B
					6'b111000: result = A << 1;                       // Shift Left
					6'b111001: result = A >> 1;                       // Shift Right
					default: result = 32'h0;
				endcase
			SIZE_64:
				;
		endcase

    zero = (result == 32'h0) ? 1'b1 : 1'b0;
    sign = (result[31]) ? 1'b1 : 1'b0;
end

endmodule

