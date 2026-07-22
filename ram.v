// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii

// This creates 16384 bytes of RAM on the FPGA itself which begins at 0x00100000.

module ram(
  input  [15:0] address,
  input  [1:0] size,
  input  wire [3:0] byte_en,      // byte enable (uno per byte)
	input  wire  force_32bit,   // nuovo: forza lettura a 32 bit (per fetch)
  output wire address_error,
  input  [31:0] data_in,
  output reg [31:0] data_out,
  input write_enable,
  input clk
);

`include "reg_mode.vinc"

/*(* ram_style = "M9K" *) dà unrecognized PD grok*/ (* preserve *) reg [31:0] memory[4095:0];

initial begin
//dump_memory(0,2047);
end

always @(posedge clk) begin
  if (write_enable) begin
		/*case (size)
			SIZE_8:  memory[address[11:2]][ address[1:0]*8 +:8 ] <= data_in[7:0];
			SIZE_16: memory[address[11:2]][ address[1]*16 +:16 ] <= data_in[15:0];
			default: memory[address[11:2]] <= data_in; // 32 bit
		endcase*/
/*            if (byte_en[0]) memory[address[11:2]][ 7: 0] <= data_in[ 7: 0];
            if (byte_en[1]) memory[address[11:2]][15: 8] <= data_in[15: 8];
            if (byte_en[2]) memory[address[11:2]][23:16] <= data_in[23:16];
            if (byte_en[3]) memory[address[11:2]][31:24] <= data_in[31:24];		*/
            /*if (byte_en[0]) memory[address[11:2]][ 7: 0] <= data_in[ 7: 0];
            if (byte_en[1]) memory[address[11:2]][15: 8] <= data_in[15: 8];
            if (byte_en[2]) memory[address[11:2]][23:16] <= data_in[23:16];
            if (byte_en[3]) memory[address[11:2]][31:24] <= data_in[31:24];*/
// Scrittura mascherata (questa forma è più amichevole per Quartus) - tutti gli altri fanno impazzire il numero di celle e il tempo di compilazione! Secondo Grok questa è più adatta/friendly...
            memory[address[11:2]] <= 
                ( {32{byte_en[3]}} & data_in[31:24] << 24 ) |
                ( {32{byte_en[2]}} & data_in[23:16] << 16 ) |
                ( {32{byte_en[1]}} & data_in[15: 8] <<  8 ) |
                ( {32{byte_en[0]}} & data_in[ 7: 0] <<  0 );
								/*							memory[address[11:2]] <= 
                (byte_en[3] ? data_in[31:24] : memory[address[11:2]][31:24]) &
                (byte_en[2] ? data_in[23:16] : memory[address[11:2]][23:16]) &
                (byte_en[1] ? data_in[15: 8] : memory[address[11:2]][15: 8]) &
                (byte_en[0] ? data_in[ 7: 0] : memory[address[11:2]][ 7: 0]);						*/
								
			//memory[address[11:2]] <= data_in; // 32 bit
  end else begin
    if (force_32bit) begin
      data_out <= memory[address[11:2]];                    // sempre 32 bit
    end else begin
			case (size)
				SIZE_8:  data_out <= {24'b0, memory[address[11:2]][address[1:0]*8 +:8]};
				SIZE_16: data_out <= {16'b0, memory[address[11:2]][address[1]*16 +:16]};
				default: data_out <= memory[address[11:2]];       // SIZE_32
			endcase
    end
	end
	
	if (address[15:12]) begin
	//	address_error <= 1;
	end
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

