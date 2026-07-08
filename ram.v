// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii

// This creates 8192 bytes of RAM on the FPGA itself which begins at 0x00100000.

module ram(
  input  [11:0] address,
  input  [31:0] data_in,
  output reg [31:0] data_out,
  input write_enable,
  input clk
);

reg [31:0] memory [4095:0];

initial begin
//dump_memory(0,2047);
end

always @(posedge clk) begin
  if (write_enable) begin
    memory[address[11:2]] <= data_in;
  end else
    data_out <= memory[address[11:2]];
end

// Dump di un range di memoria
task dump_memory;
    input [31:0] start;
    input [31:0] end_addr;
    integer i;
    begin
        $display("--- Memory dump [%0d : %0d] ---", start, end_addr);
        for (i = start; i <= end_addr; i = i + 1) begin
//				memory[i]=32'h12345678;			// questo si ciuccia 8000 celle!! hmmmmm ;)
            $display("mem[%0d] = %h", i, memory[i]);
        end
        $display("--- End dump ---");
    end
endtask

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
    memory[address[10:2]] <= data_in;
  end else
    data_out <= memory[address];
end

endmodule

