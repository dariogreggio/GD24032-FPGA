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
  input  [31:0] data_in,
  output reg [31:0] data_out,
  input  bus_enable,
  input  write_enable,
  output bus_halt,
  input  clk,
  input  raw_clk,
  //output [15:0] debug,
  input  reset
);

wire [31:0] rom_data_out;
wire [31:0] ram_data_out;
wire [7:0] videoram_data_out;
wire [7:0] peripherals_data_out;

wire [7:0] load_count;

//reg [7:0] ram_data_in;
//reg [7:0] peripherals_data_in;

wire [11:0] bank;

assign bank = address[31:20];


wire ram_write_enable;
wire videoram_write_enable;

assign ram_write_enable         = (bank == 12'h001) && write_enable;
assign videoram_write_enable = (bank == 12'h00b) && write_enable;


// FIXME: The RAM probably need an enable also.




always @ * begin
  if (bank == 12'h100) begin
    data_out <= ram_data_out;
  end else if (bank == 12'h000) begin
    data_out <= rom_data_out;
  end else if (bank == 12'h00b) begin		// CGA/video
    data_out <= videoram_data_out;
  end else begin
    data_out <= 0;
  end
end

ram ram_0(
  .address      (address[10:0]),
  .data_in      (data_in),
  .data_out     (ram_data_out),
  .write_enable (ram_write_enable),
  .clk          (raw_clk)
);

rom rom_0(
  .address   (address[10:0]),
  .data_out  (rom_data_out),
  .clk   (raw_clk)
);

cgaram videoram(
  .address      (address[11:0]),
  .data_in      (data_in),
  .data_out     (videoram_data_out),
  .write_enable (videoram_write_enable),
  .clk          (raw_clk)
);


endmodule

