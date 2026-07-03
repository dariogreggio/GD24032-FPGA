// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii


module io_bus(
  input [7:0] address,
  input  [7:0] data_in,
  output reg [7:0] data_out,
  input  bus_enable,
  input  write_enable,
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

wire [7:0] io_data_out;

wire peripherals_write_enable;


wire peripherals_enable;
assign peripherals_enable =  bus_enable;


always @ * begin
  begin
    data_out <= 0;
  end
end


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

