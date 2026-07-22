// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii

// This creates 8192*4 bytes of ROM on the FPGA itself which begins at 0x00000000.

module rom(
  input [15:0] address,
  input  [1:0] size,
  input  wire  force_32bit,   // nuovo: forza lettura a 32 bit (per fetch)
  output wire address_error,
	output reg [31:0] data_out,
  input clk
);

`include "reg_mode.vinc"

(* preserve *) reg [31:0] memory[8191:0];
//reg [31:0] i;

initial begin
  $readmemh("rom.txt", memory);
//	$display("memory rom[0] %x,%x,%x,%x", memory[0],memory[1],memory[2],memory[3]);
//	for (i=0; i<2048; i=i+4)
//		$display("memory rom[%x] %x,%x,%x,%x", i*4,memory[i],memory[i+1],memory[i+2],memory[i+3]);
//		$display("memory rom[500] %x,%x,%x,%x", memory[12'h100],memory[12'h201],memory[12'h302],memory[12'h403]);

//	$writememh("froci.txt", memory, 0, 8192);		// non lo supporta PD
end

always @(posedge clk) begin
	if (force_32bit) begin
		data_out <= memory[address[12:2]];                    // sempre 32 bit
	end else begin
		case (size)
			SIZE_8:  data_out <= {24'b0, memory[address[12:2]][address[1:0]*8 +:8]};
			SIZE_16: data_out <= {16'b0, memory[address[12:2]][address[1]*16 +:16]};
			default: data_out <= memory[address[12:2]];       // SIZE_32
		endcase
  end
	
	if (address[15:13]) begin
	//	address_error <= 1;
	end
	
end 
	
endmodule

