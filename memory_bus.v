// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii

// The purpose of this module is to route reads and writes to the 4
// different memory banks. Originally the idea was to have ROM and RAM
// be SPI EEPROM (this may be changed in the future) so there would also
// need a "ready" signal that would pause the CPU until the data can be
// clocked in and out of of the SPI chips.

module memory_bus(
  input [31:0] address,
	input [1:0] size,
  input  wire  force_32bit,   // nuovo: forza lettura a 32 bit (per fetch)
  input  [31:0] data_in,
  output reg [31:0] data_out,
  input  bus_enable,
  input  write_enable,
  output wire bus_error,        // nuovo: errore di allineamento
  output wire address_error,
	output bus_halt,
  input  clk,
  input  raw_clk,
  //output [15:0] debug,
  input  reset
);

`include "reg_mode.vinc"

wire [31:0] rom_data_out;
wire [31:0] ram_data_out;
wire [7:0] videoram_data_out;
wire [7:0] peripherals_data_out;

wire [7:0] load_count;

//reg [7:0] ram_data_in;
//reg [7:0] peripherals_data_in;

wire [15:0] bank;

assign bank = address[31:16];


wire ram_write_enable;
wire videoram_write_enable;

assign ram_write_enable         = (bank == 16'h0010) && write_enable;
assign videoram_write_enable = (bank == 16'h000b) && write_enable;

// ====================== Byte Enable ======================
wire [3:0] byte_en;

assign byte_en = force_32bit ? 4'b1111 :
                 (size == SIZE_32) ? 4'b1111 :
                 (size == SIZE_16) ? (address[1] ? 4'b1100 : 4'b0011) :
                 // SIZE_8
                 (address[1:0] == 2'b00) ? 4'b0001 :
                 (address[1:0] == 2'b01) ? 4'b0010 :
                 (address[1:0] == 2'b10) ? 4'b0100 : 4'b1000;

								 
`ifdef ALIGNMENT_CHECK
wire alignment_error = 
    (size == SIZE_16 && address[0] == 1'b1) ||                    // half-word
    (size == SIZE_32 && address[1:0] != 2'b00) ||                 // word
    (force_32bit && address[1:0] != 2'b00);                       // fetch istruzioni
`else
wire alignment_error = 1'b0;
`endif

assign bus_error = alignment_error && bus_enable;
								 
// FIXME: The RAM probably need an enable also.
wire ram_address_error;     // accesso fuori range RAM
wire rom_address_error;     // accesso fuori range ROM




always @ * begin
  if (bank == 16'h0010) begin
    data_out <= ram_data_out;
  end else if (bank == 16'h0000) begin
    data_out <= rom_data_out;
  end else if (bank == 16'h000b) begin		// CGA/video
    data_out <= videoram_data_out;
  end else begin
    data_out <= 0;
  end
end

ram ram_0(
  .address      (address[15:0]),
	.size 				(size),
	.force_32bit	(force_32bit),
	.address_error (ram_address_error),
  .byte_en  		(byte_en),
	.data_in      (data_in),
  .data_out     (ram_data_out),
  .write_enable (ram_write_enable),
  .clk          (raw_clk)
);

rom rom_0(
  .address  		(address[15:0]),
	.size 				(size),
	.force_32bit	(force_32bit),
	.address_error (rom_address_error),
  .data_out 		(rom_data_out),
  .clk   				(raw_clk)
);

cgaram videoram(
  .address      (address[11:0]),
  .data_in      (data_in),
  .data_out     (videoram_data_out),
  .write_enable (videoram_write_enable),
  .clk          (raw_clk)
);


endmodule

