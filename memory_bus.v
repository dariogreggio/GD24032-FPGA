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
  input [15:0] address,
  input  [7:0] data_in,
  output reg [7:0] data_out,
  input  bus_enable,
  input  write_enable,
  output bus_halt,
  input  clk,
  input  raw_clk,
  output speaker_p,
  output speaker_m,
  output ioport_0,
  output ioport_1,
  output ioport_2,
  output ioport_3,
  output ioport_4,
  input  button_0,
  output uart_tx_0,
  input  uart_rx_0,
  //output [15:0] debug,
  input  reset
);

wire [31:0] rom_data_out;
wire [31:0] ram_data_out;
wire [7:0] peripherals_data_out;

wire [7:0] load_count;

//reg [7:0] ram_data_in;
//reg [7:0] peripherals_data_in;

wire [11:0] bank;

assign bank = address[31:20];


wire ram_write_enable;
wire peripherals_write_enable;

assign ram_write_enable         = (bank <= 3) && write_enable;
assign peripherals_write_enable = (bank == 4'hd) && write_enable;


// FIXME: The RAM probably need an enable also.
wire peripherals_enable;
assign peripherals_enable = (bank == 4'hd) && bus_enable;


always @ * begin
  if (bank <= 3) begin
    data_out <= ram_data_out;
  end else if (bank == 4'hf) begin
    data_out <= rom_data_out;
  end else if (bank == 4'hd) begin
    data_out <= peripherals_data_out;
  end else begin
    data_out <= 0;
  end
end

ram ram_0(
  .address      (address[11:0]),
  .data_in      (data_in),
  .data_out     (ram_data_out),
  .write_enable (ram_write_enable),
  .clk          (raw_clk)
);

rom rom_0(
  .address   (address[11:0]),
  .data_out  (rom_data_out),
  .clk   (raw_clk)
);

peripherals peripherals_0(
  .enable       (peripherals_enable),
  .address      (address[5:0]),
  .data_in      (data_in),
  .data_out     (peripherals_data_out),
  .write_enable (peripherals_write_enable),
  .clk          (clk),
  .raw_clk      (raw_clk),
  .speaker_p    (speaker_p),
  .speaker_m    (speaker_m),
  .ioport_0     (ioport_0),
  .ioport_1     (ioport_1),
  .ioport_2     (ioport_2),
  .ioport_3     (ioport_3),
  .ioport_4     (ioport_4),
  .button_0     (button_0),
  .uart_tx_0    (uart_tx_0),
  .uart_rx_0    (uart_rx_0),
  .load_count   (load_count),
  .reset        (reset)
);


endmodule

