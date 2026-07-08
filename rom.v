// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii

// This creates 8192*4 bytes of ROM on the FPGA itself which begins at 0x00000000.

module rom(
  input [12:0] address,
  output reg [31:0] data_out,
  input clk
);

reg [31:0] memory [8191:0];
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
  data_out <= memory[address[12:2]];		// cfr https://github.com/Varunkumar0610/RISC-V-Single-Cycle-Core/blob/main/src/Instruction_Memory.v
end 

endmodule

