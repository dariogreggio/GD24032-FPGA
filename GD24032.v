// GD24032 basato su W65C832 FPGA Soft Processor di Michael Kohn
//   Board: Cyclone EP4CE6E22 
//
// GD 07/2026  superguerra & scisma daiiiiiii


module GD24032(
  output [7:0] leds,
  input raw_clk,
  output speaker_p,
  output speaker_m,
  output ioport_0,
  output ioport_1,
  output ioport_2,
  output ioport_3,
  output ioport_4,
  input  button_reset,
  input  button_halt,
  input  button_irq,
  input  button_nmi,
  input  button_0,
  output uart_tx_0,
  input  uart_rx_0,
  
  output reg [6:0] segments, // a b c d e f g; aggiungere punto
  output reg [3:0] digits,    // Digit selector (attivo basso se common cathode)
  output reg [3:0] digit3, digit2, digit1, digit0
);

`define SIMULATION 1

`include "addressing_mode.vinc"
`include "reg_mode.vinc"



// 5 LEDs used for debugging.
reg [4:0] leds_value;

assign leds = leds_value;

// Memory bus (ROM, RAM) ; IO bus (peripherals).
reg [31:0] mem_address = 0;
reg [31:0]  mem_write = 0;
wire [31:0] mem_read;
reg mem_write_enable = 0;
reg mem_bus_enable = 0;
reg mem_bus_reset = 1;
wire mem_bus_halted;
reg [7:0] io_address = 0;
reg [7:0]  io_write = 0;
wire [7:0] io_read;
reg io_write_enable = 0;
reg io_bus_enable = 0;

// FIXME: Can remove this later.
//reg was_ever_halted = 0;

// Clock.
reg [63:0] tsc = 0;
`ifdef SIMULATION
(* preserve, noprune *)
`endif
reg [5:0]  state = 0;
reg [5:0]  next_state = 0;
reg [24:0]  clock_div;		// ridurre poi!
reg [14:0] delay_loop;
wire clk;

reg [4:0] IRQlevel;

// Lower this (down to one) to increase speed.
assign clk = clock_div[0];
	// grok dice che usare più clock è sbagliato e dannoso in FPGA... ma usare uno stato precedente per confrontare costa un po' di celle!
	// v. 74c926 stranamente, usare il bit 15 usa 1-2 celle più che il bit 13 o 14...

// Registers and stack.
`ifdef SIMULATION
(* preserve, noprune *)
`endif
reg [31:0] regs[31:0];
`ifdef SIMULATION
(* preserve, noprune *)
`endif
reg [31:0] ssp;
reg [31:0] usp;
`ifdef SIMULATION
(* preserve, noprune *)
`endif
reg [31:0] wp;

reg [3:0] size_imm;	// questo è in byte (arrotondato a dword cmq ossia 4, 8
//reg [2:0] size_wb;


// Program counter, instruction, effective address.
reg [31:0] instruction;
reg [31:0] ea_indirect;
// pc � regs[31] ma ho paura che appesantisca... e in fondo non ha molto senso, magari mettere a parte

wire [7:0] Imm8;
wire [2:0] Mm;
wire [4:0] Rs;
wire [3:0] Ts;
wire [3:0] Cond;
wire [4:0] Rd;
wire [3:0] Td;
wire [1:0] size_m;	// questo è 0..3 ossia SIZE_8 ecc
wire IsCond;
wire DoFlags;
wire [6:0] Opcode;
assign Imm8 = instruction[7:0];
assign Mm  = instruction[2:0];
assign Rs = instruction[7:3];
assign Ts = instruction[11:8];
assign Cond = instruction[11:8];
assign Rd = instruction[16:12];
assign Td = instruction[20:17];
assign IsCond = instruction[21];
assign size_m = instruction[23:22];
assign DoFlags = instruction[24];
assign Opcode = instruction[31:25];

// (reg_x or reg_y for indexed.
reg [31:0] offset;


// Used for ALU.
reg [31:0] source;		// usato anche per JMP e simili
reg [31:0] temp;
reg [32:0] result;
reg wb;
reg is_sub;
reg affects_c;
reg affects_ov;
reg affects_s;		// questo forse non serve

// Used for MOVS ecc
reg [31:0] block_source;
reg [31:0] block_destination;

// Addressing mode.
reg  [1:0] indirect_count;		// # dword
reg  [1:0] indirect_total;		// # dword
reg  [3:0] immediate_count;		// 1..8 (arrotondato a dword)
reg  [5:0] rotate_count;		// 0..63
reg  [3:0] push_count;
reg  [3:0] pop_count;		// non � mai usato insieme a push, ma se li unifico spreco pi� celle...
reg  [3:0] wb_count;		// 1..8 (arrotondato a dword) (usare per write a 64bit
reg  [1:0] post_count;


// Branches.
reg [31:0] branch_offset;

// Flags.
parameter FLAG_IRQMASK = 27;
parameter FLAG_CPUMODE = 25;
parameter FLAG_TRACE = 24;
parameter FLAG_ADDR64 = 15;
parameter FLAG_ENFALIGN = 14;
parameter FLAG_REMAPR = 13;
parameter FLAG_TRAP = 12;
parameter FLAG_IOPL = 11;
parameter FLAG_PRIV = 10;
parameter FLAG_NT   = 9;
parameter FLAG_X   = 8;
parameter FLAG_D   = 7;
parameter FLAG_AS   = 6;
parameter FLAG_OV   = 5;
parameter FLAG_P   = 4;
parameter FLAG_HC   = 3;
parameter FLAG_C   = 2;
parameter FLAG_S   = 1;
parameter FLAG_Z   = 0;

reg [31:0] flags;

wire [4:0] flag_irqmask;
wire [1:0] flag_cpumode;
wire flag_trace;
wire flag_addr64;
wire flag_enfalign;
wire flag_remapr;
wire flag_trap;
wire flag_iopl;
wire flag_priv;
wire flag_nt;
wire flag_x;
wire flag_d;
wire flag_as;
wire flag_ov;
wire flag_p;
wire flag_hc;
wire flag_c;
wire flag_s;
wire flag_z;

assign flag_irqmask = flags[31:FLAG_IRQMASK];
assign flag_cpumode = flags[FLAG_CPUMODE+1:FLAG_CPUMODE];
assign flag_trace = flags[FLAG_TRACE];
assign flag_addr64 = flags[FLAG_ADDR64];
assign flag_enfalign = flags[FLAG_ENFALIGN];
assign flag_remapr = flags[FLAG_REMAPR];
assign flag_trap = flags[FLAG_TRAP];
assign flag_iopl = flags[FLAG_IOPL];
assign flag_priv = flags[FLAG_PRIV];
assign flag_nt   = flags[FLAG_X];
assign flag_x   = flags[FLAG_X];
assign flag_d   = flags[FLAG_D];
assign flag_as   = flags[FLAG_AS];
assign flag_ov  = flags[FLAG_OV];
assign flag_p   = flags[FLAG_P];
assign flag_hc  = flags[FLAG_HC];
assign flag_c   = flags[FLAG_C];
assign flag_s   = flags[FLAG_S];
assign flag_z   = flags[FLAG_Z];

// Debug.
//reg [7:0] debug_0 = 0;
//reg [7:0] debug_1 = 0;
//reg [7:0] debug_2 = 0;
//reg [7:0] debug_3;

parameter STATE_RESET             = 6'd0;
parameter STATE_DELAY_LOOP        = 6'd1;
parameter STATE_FETCH_OP_0        = 6'd2;
parameter STATE_FETCH_OP_1        = 6'd3;
parameter STATE_DECODE            = 6'd4;

parameter STATE_FETCH_INDIRECT_0  = 6'd5;
parameter STATE_FETCH_INDIRECT_1  = 6'd6;
parameter STATE_FETCH_INDIRECT_2  = 6'd7;
parameter STATE_FETCH_INDIRECT_3  = 6'd8;

parameter STATE_FETCH_ABSOLUTE_0  = 6'd10;
parameter STATE_FETCH_ABSOLUTE_1  = 6'd11;

parameter STATE_FETCH_INDEXED     = 6'd14;

parameter STATE_FETCH_IMMEDIATE_0 = 6'd15;
parameter STATE_FETCH_IMMEDIATE_1 = 6'd16;

parameter STATE_EXECUTE_00_0      = 6'd17;
parameter STATE_EXECUTE_00_1      = 6'd18;

parameter STATE_EXECUTE_01_0      = 6'd19;
parameter STATE_EXECUTE_01_1      = 6'd20;

parameter STATE_EXECUTE_10_0      = 6'd21;
parameter STATE_EXECUTE_10_1      = 6'd22;

parameter STATE_WRITEBACK_R       = 6'd23;

parameter STATE_WRITEBACK_MEM_P   = 6'd26;
parameter STATE_WRITEBACK_MEM_0   = 6'd27;
parameter STATE_WRITEBACK_MEM_1   = 6'd28;

parameter STATE_BRANCH_0          = 6'd29;
parameter STATE_BRANCH_1          = 6'd30;

parameter STATE_SET_FLAGS_0       = 6'd31;
parameter STATE_SET_FLAGS_1       = 6'd32;

parameter STATE_PUSH_0            = 6'd33;
parameter STATE_PUSH_1            = 6'd34;
parameter STATE_PUSH_2            = 6'd35;

parameter STATE_POP_0             = 6'd36;
parameter STATE_POP_1             = 6'd37;
parameter STATE_POP_WB            = 6'd38;

parameter STATE_RTI_0             = 6'd43;
parameter STATE_RTI_1             = 6'd44;

parameter STATE_TEST_BITS         = 6'd52;

parameter STATE_JMP_0         = 6'd53;
parameter STATE_JMP_1         = 6'd54;
parameter STATE_JMP_2         = 6'd55;
parameter STATE_JMP_3         = 6'd56;

parameter STATE_ERROR             = 6'd60;
parameter STATE_HALTED            = 6'd61;
parameter STATE_IRQ_0	          = 6'd62;
parameter STATE_IRQ_1	          = 6'd63;

// Instruction format: 

parameter OP_NOP     = 7'h00;
parameter OP_MOV     = 7'h02;
parameter OP_MOVS    = 7'h03;
parameter OP_XLAT    = 7'h04;
parameter OP_CLR    = 7'h05;
parameter OP_SET    = 7'h06;
parameter OP_SE    = 7'h07;
parameter OP_DAA    = 7'h08;
parameter OP_SWAP    = 7'h09;
parameter OP_EX    = 7'h0a;
parameter OP_LEA    = 7'h0b;
parameter OP_RDTS    = 7'h0c;
parameter OP_CPUID  = 7'h0d;
parameter OP_ADD    = 7'h10;
parameter OP_ADC    = 7'h11;
parameter OP_SUB    = 7'h12;
parameter OP_SBC    = 7'h13;
parameter OP_CMP    = 7'h14;
parameter OP_CMPS    = 7'h15;
parameter OP_INC    = 7'h18;
parameter OP_DEC    = 7'h19;
parameter OP_MUL    = 7'h1c;
parameter OP_IMUL   = 7'h1d;
parameter OP_DIV    = 7'h1e;
parameter OP_IDIV    = 7'h1f;
parameter OP_OUT    = 7'h20;
parameter OP_OUTS    = 7'h21;
parameter OP_IN    = 7'h22;
parameter OP_INS    = 7'h23;
parameter OP_AND    = 7'h28;
parameter OP_OR    = 7'h29;
parameter OP_XOR    = 7'h2a;
parameter OP_NAND    = 7'h2b;
parameter OP_NOR    = 7'h2c;
parameter OP_NEG    = 7'h2d;
parameter OP_NOT    = 7'h2e;
parameter OP_ABS    = 7'h2f;
parameter OP_SBO    = 7'h30;
parameter OP_SBZ    = 7'h31;
parameter OP_TB     = 7'h32;
parameter OP_BINS    = 7'h33;
parameter OP_BXTR    = 7'h34;
parameter OP_BSFR    = 7'h35;
parameter OP_ROT    = 7'h38;		// SLA SRA ecc
parameter OP_MAS    = 7'h3c;
parameter OP_MSS    = 7'h3d;
parameter OP_SSA    = 7'h3e;
parameter OP_VMA    = 7'h3f;
parameter OP_JMP    = 7'h40;
parameter OP_CALL   = 7'h41;
parameter OP_BLWP   = 7'h42;
parameter OP_RET    = 7'h43;
parameter OP_ENTER  = 7'h44;
parameter OP_LEAVE  = 7'h45;
parameter OP_CHK    = 7'h46;
parameter OP_X      = 7'h47;
parameter OP_PUSH   = 7'h48;
parameter OP_POP    = 7'h49;
parameter OP_LDM    = 7'h4c;
parameter OP_STM    = 7'h4d;
parameter OP_B		= 7'h50;
parameter OP_DJNZ   = 7'h51;
parameter OP_SKIP   = 7'h52;
parameter OP_TRAP   = 7'h6f;
parameter OP_LDIM   = 7'h70;
parameter OP_LDST   = 7'h71;
parameter OP_LDSP   = 7'h72;
parameter OP_STST   = 7'h73;
parameter OP_STSP   = 7'h74;
parameter OP_RTWP   = 7'h75;
parameter OP_RETI   = 7'h76;
parameter OP_XOP    = 7'h7e;
parameter OP_HALT   = 7'h7f;

parameter MODE_USER=0;
parameter MODE_FIQ=1;
parameter MODE_IRQ=2;
parameter MODE_SVC=3;

parameter TRAP_BUS_ERROR=0;
parameter TRAP_ADDRESS_ERROR=1;
parameter TRAP_ADDRESS_ERROR2=2;
parameter TRAP_ILLEGAL_OPCODE=3;
parameter TRAP_DIVIDE_BY_ZERO=4;
parameter TRAP_OUT_OF_BOUNDS=5;
parameter TRAP_OVERFLOW=6;
parameter TRAP_PRIVILEGE_VIOLATION=7;
parameter TRAP_IOPL_VIOLATION=8;
parameter TRAP_TRACE=9;
parameter TRAP_LAST=30;


    // ================== Multiplexing 7-Segmenti ==================
    reg [1:0]  mux_state = 0;
    reg [15:0] refresh_counter = 0;   // ~200-300 Hz refresh totale

    // Decodificatore BCD -> 7 segmenti (common cathode)
    reg [6:0] seg_data;

	 
// This block is simply a clock divider for the raw_clk.
always @(posedge raw_clk) begin
  clock_div <= clock_div + 25'd1;
end

// Debug: This block simply drives the LEDs.
always @(posedge raw_clk) begin
	if (state==STATE_ERROR)
		leds_value <= 31; 
	else if (state==STATE_HALTED)
		leds_value <= 15; 
	else
		leds_value <= ~regs[0][4:0];

end


// This block is the main CPU instruction execute state machine.
always @(posedge clk) begin

  tsc <= tsc + 1;		// o a ogni decode??
	
  if(!button_reset)
    state <= STATE_RESET;
  else 
    case (state)
      STATE_RESET:
        begin
          flags <= 0;
          mem_address <= 0;
          mem_write_enable <= 0;
          mem_bus_enable <= 0;
          mem_bus_reset <= 1;
          delay_loop <= 30;			// cfr. freq raw_clk e div.
//          regs[0] <= 0;
          state <= STATE_DELAY_LOOP;
        end
		  
      STATE_DELAY_LOOP:
        begin
          // This is probably not needed. The chip starts up fine without it.
          if (delay_loop == 0) begin
            mem_bus_reset <= 0;

//				regs[31] <= { rom_0[16'hfffd],rom_0[16'hfffc]};
/*          mem_bus_enable <= 1;
            mem_address = 16'hfffc;
            regs[31][7:0]    <= mem_read;
            mem_address = mem_address+1;
            regs[31][15:8]   <= mem_read;
				// non va...
				
            regs[31] <= 16'hf000;
            mem_address = regs[31];
				reg_a=mem_read;
          mem_bus_enable <= 0;

            state <= STATE_FETCH_OP_0;
	*/			
				
						mem_bus_enable <= 0;
            regs[31] <= 32'h00000004;
            mem_address <= 32'h00000004;
						flags <= 32'h00000000;		// leggere da ram!
						if (flag_cpumode==MODE_SVC)
							ssp <= 32'h0000000c;		// leggere da ram!
						else
							usp <= 32'h0000000c;		// leggere da ram!
 //           mem_address <= 32'h0000000c;
						wp <= 32'h00000008;		// leggere da ram!

						instruction <= 32'h40000000;		// JMP
						state <= STATE_DECODE;

						
						
						flags <= 32'h06000000;		// per ora...
						regs[31] <= 32'h00000500;
						wp <= 32'h00000000;
						ssp <= 32'h00101000;
						state <= STATE_FETCH_OP_0;
						
				
          end

          delay_loop <= delay_loop - 15'd1;
        end
		  
      STATE_FETCH_OP_0:
        begin
          source <= 0;
          indirect_count <= 0;
          indirect_total <= 1;
          immediate_count <= 0;
          push_count <= 0;
          pop_count <= 0;
          wb_count <= 0;
          ea_indirect <= 0;
					post_count <= 0;
          size_imm <= 4;
          is_sub <= 0;
          affects_ov <= 0;
          affects_c <= 0;
          affects_s <= 1;
          wb <= 1;
          branch_offset <= 0;
          mem_address <= regs[31];
          mem_bus_enable <= 1;
			 
				  if(!button_irq) begin
						size_imm <= 8;		// 2 dword da salvare
						immediate_count <= 0;
						IRQlevel=1;
						state <= STATE_IRQ_0;
					end
					else
						state <= STATE_FETCH_OP_1;
					end

		  
      STATE_FETCH_OP_1:
        begin
          mem_bus_enable <= 0;
          instruction = mem_read;		// NON <=
					
					if(Opcode>=7'h70 && flag_cpumode<MODE_SVC) begin
						// eccezione!
						// MA LDST e STST devono passare!!
					end
					if(Opcode == OP_CLR || Opcode == OP_SET || Opcode == OP_SE || Opcode == OP_DAA
						|| Opcode == OP_SWAP || Opcode == OP_EX || Opcode == OP_INC
						|| Opcode == OP_DEC || Opcode == OP_NEG || Opcode == OP_NOT || Opcode == OP_ABS
						|| Opcode == OP_ROT || Opcode == OP_CALL || Opcode == OP_BLWP
						|| Opcode == OP_RET || Opcode == OP_SKIP || Opcode == OP_TRAP 
						|| Opcode == OP_RTWP || Opcode == OP_HALT) begin
						if (condIsOk(Cond) == 0) begin
							state <= STATE_FETCH_OP_0;
						// finire di skippare operandi...
						end else begin
							state <= STATE_DECODE;
						end
					end else begin
						state <= STATE_DECODE;
					end
          regs[31] <= regs[31] + 4;
        end
		  
      STATE_DECODE:
        begin
					if(Opcode == OP_MOV || Opcode == OP_MOVS || Opcode == OP_XLAT || Opcode == OP_EX
					// creare un Opcode senza LSB per fare meglio i confronti?
						|| Opcode == OP_LEA
						|| Opcode == OP_ADD || Opcode == OP_ADC || Opcode == OP_SUB || Opcode == OP_SBC
						|| Opcode == OP_CMP || Opcode == OP_CMPS || Opcode == OP_MUL
						|| Opcode == OP_IMUL || Opcode == OP_DIV || Opcode == OP_IDIV
						|| Opcode == OP_OUT || Opcode == OP_OUTS || Opcode == OP_IN || Opcode == OP_INS
						|| Opcode == OP_AND || Opcode == OP_OR || Opcode == OP_XOR || Opcode == OP_NAND
						|| Opcode == OP_NOR || Opcode == OP_SBZ || Opcode == OP_SBO || Opcode == OP_TB
						|| Opcode == OP_BINS || Opcode == OP_BXTR || Opcode == OP_BSFR || Opcode == OP_MAS
						|| Opcode == OP_MSS || Opcode == OP_SSA || Opcode == OP_VMA || Opcode == OP_ENTER
						|| Opcode == OP_CHK || Opcode == OP_X || Opcode == OP_PUSH || Opcode == OP_LDIM
						|| Opcode == OP_LDST || Opcode == OP_LDSP
						) begin
						case (Ts)
							MODE_IMMEDIATE:
								begin
									size_imm <= size_m == SIZE_64 ? 4'd8 : 4'd4;
									if (size_m == SIZE_8) begin
										source[7:0] <= Imm8;
										state <= STATE_EXECUTE_00_0;
										end
									else begin
										ea_indirect <= regs[31];
										state <= STATE_FETCH_IMMEDIATE_0;
									end
								end
							MODE_IMMEDIATE8:
								begin
									source[7:0] <= Imm8;
									state <= STATE_EXECUTE_00_0;
								end
							MODE_REGISTER:
								begin
									case (size_m)
										SIZE_8:  source <= regs[Rs][7:0];
										SIZE_16: source <= regs[Rs][15:0];
										SIZE_32: source <= regs[Rs][31:0];
									endcase
									state <= STATE_EXECUTE_00_0;
								end
							MODE_REGISTER_INDIRECT:
								begin
									ea_indirect <= regs[Rs];
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDEXED:
								begin
									if (Rs) begin
										ea_indirect <= regs[Rs];
									end else begin
										ea_indirect <= 0;
									end
									state <= STATE_FETCH_INDIRECT_0;
								end
							MODE_INDEXED_2_REG:
								begin
									ea_indirect <= regs[Rs]+regs[Mm];
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDEXED_SHORT:
								begin
									ea_indirect <= regs[Rs]+Imm8;
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT_PREINC:
								begin
									case (size_m)
										0: begin
											ea_indirect <= regs[Rs]+0;
											regs[Rs] <= regs[Rs]+1;
											end
										1: begin
											ea_indirect <= regs[Rs]+0;
											regs[Rs] <= regs[Rs]+2;
											end
										2: begin
											ea_indirect <= regs[Rs]+4;
											regs[Rs] <= regs[Rs]+4;
											end
									endcase
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT_PREDEC:
								begin
									case (size_m)
										0: begin
											ea_indirect <= regs[Rs]-4;
											regs[Rs] <= regs[Rs]-1;
											end
										1: begin
											ea_indirect <= regs[Rs]-4;
											regs[Rs] <= regs[Rs]-2;
											end
										2: begin
											ea_indirect <= regs[Rs]-4;
											regs[Rs] <= regs[Rs]-4;
											end
									endcase
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT_POSTINC:
								begin
									ea_indirect <= regs[Rs];
									case (size_m)
										0: begin
											regs[Rs] <= regs[Rs]+1;
											end
										1: begin
											regs[Rs] <= regs[Rs]+2;
											end
										2: begin
											regs[Rs] <= regs[Rs]+4;
											end
									endcase
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT_POSTDEC:
								begin
									ea_indirect <= regs[Rs];
									case (size_m)
										0: begin
											regs[Rs] <= regs[Rs]-1;
											end
										1: begin
											regs[Rs] <= regs[Rs]-2;
											end
										2: begin
											regs[Rs] <= regs[Rs]-4;
											end
									endcase
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT64:
								begin

									indirect_total <= 2;
								end
							MODE_INDIRECT64_POSTINC:
								begin

									indirect_total <= 2;
								end
							MODE_INDIRECT64_2_REG:
								begin

									indirect_total <= 2;
								end
						endcase
					end
					else begin
						if(Opcode == OP_CLR || Opcode == OP_SET || Opcode == OP_SE || Opcode == OP_DAA
						// creare un Opcode senza LSB per fare meglio i confronti?
							|| Opcode == OP_SWAP
							|| Opcode == OP_RDTS || Opcode == OP_CPUID || Opcode == OP_INC || Opcode == OP_DEC
							|| Opcode == OP_NEG || Opcode == OP_NOT || Opcode == OP_ABS
							|| Opcode == OP_JMP || Opcode == OP_CALL || Opcode == OP_BLWP
							|| Opcode == OP_RET || Opcode == OP_POP || Opcode == OP_LDM
							|| Opcode == OP_STM || Opcode == OP_STST || Opcode == OP_STSP
							) begin
							state <= STATE_EXECUTE_00_0;
							end 
						else if(Opcode == OP_ROT) begin
							state <= STATE_EXECUTE_10_0;
							end 
						else if(Opcode == OP_B) begin
						  if (condIsOk(Cond)) begin
								regs[31][31:0] <= $signed(regs[31][31:0]) + $signed({instruction[20:12],instruction[7:0]});
								end
							state <= STATE_FETCH_OP_0;
							end
						else if(Opcode == OP_POP) begin
							size_imm <= SIZE_32;
							state <= STATE_POP_0;
						end
						else if(Opcode == OP_NOP) begin
							state <= STATE_FETCH_OP_0;
						end
						else
							state <= STATE_EXECUTE_00_0;
					end
			 
				if(!button_halt)
				 state <= STATE_HALTED;
			 
        end
		  
      STATE_FETCH_INDIRECT_0:
        begin
          mem_address <= regs[31];
          mem_bus_enable <= 1;
          regs[31] <= regs[31] + 4;
          state <= STATE_FETCH_INDIRECT_1;
        end
		  
      STATE_FETCH_INDIRECT_1:
        begin
          mem_bus_enable <= 0;
          ea_indirect[31:0] <= ea_indirect[31:0]+mem_read[31:0];
          state <= STATE_FETCH_INDIRECT_2;
        end
		  
      STATE_FETCH_INDIRECT_2:
        begin
          mem_address <= ea_indirect;
          ea_indirect <= ea_indirect + 4;
          mem_bus_enable <= 1;
          state <= STATE_FETCH_INDIRECT_3;
        end
		  
      STATE_FETCH_INDIRECT_3:
        begin
          mem_bus_enable <= 0;
          indirect_count <= indirect_count + 2'd1;

          case (indirect_count)
            0: case (size_m)
							SIZE_8: case (mem_address[1:0])
									0: source[7:0] <= mem_read[7:0];
									1: source[7:0] <= mem_read[15:8];
									2: source[7:0] <= mem_read[23:16];
									3: source[7:0] <= mem_read[31:24];
								endcase
							SIZE_16: case (mem_address[1])
									0: source[15:0] <= mem_read[15:0];
									1: source[15:0] <= mem_read[31:16];
								endcase
							SIZE_32: source[31:0] <= mem_read[31:0];
							endcase
            1: ; // ea[63:32] <= mem_read[31:0];
          endcase

          if (indirect_count == indirect_total) begin
            state <= STATE_EXECUTE_00_0;
          end else begin
            state <= STATE_FETCH_INDIRECT_2;
          end
        end
		  
      STATE_FETCH_IMMEDIATE_0:			// 15
        begin
          mem_address <= ea_indirect + immediate_count;
					regs[31] <= regs[31]+4;
          mem_bus_enable <= 1;
          immediate_count <= immediate_count + 4'd4;
          state <= STATE_FETCH_IMMEDIATE_1;
        end
		  
      STATE_FETCH_IMMEDIATE_1:			// 16
        begin
          mem_bus_enable <= 0;

          case (size_m)
            SIZE_8: source[7:0]   <= mem_read[7:0];
            SIZE_16: source[15:0]  <= mem_read[15:0];
            SIZE_32: source[31:0]  <= mem_read[31:0];
            SIZE_64: source[31:0]  <= mem_read[31:0];		// FINIRE! gestire 64 con immediate_count=8 
          endcase

          if (immediate_count == size_imm)
            state <= STATE_EXECUTE_00_0;
          else
            state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_EXECUTE_00_0:		// 17
        begin
					if(Opcode == OP_PUSH) begin
						state <= STATE_PUSH_0;
					end
					else if(Opcode == OP_LDIM) begin
						IRQlevel[4:0] <= source[4:0];
						state <= STATE_FETCH_OP_0;
					end
					else if(Opcode == OP_LDSP) begin
						if (instruction[13]) begin		// LDSP
							if(instruction[12])
								ssp <= source;
							else
								usp <= source;
							end
						else begin		// LDWP
							if(flag_remapr)
								wp <= source;
							end
						state <= STATE_FETCH_OP_0;
					end
					else if(Opcode == OP_LDST) begin
						if(flag_cpumode==MODE_SVC)
							flags[31:0] <= source[31:0];
						else
							flags[7:0] <= source[7:0];
						state <= STATE_FETCH_OP_0;
					end
					else if(Opcode == OP_HALT) begin
					// halt
						state <= STATE_HALTED;
					end
					else if(Opcode == OP_MOV) begin
						case (Td)
							MODE_INDEXED:
								begin
									if (Rd) begin
										ea_indirect <= regs[Rd];
									end else begin
										ea_indirect <= 0;
									end
									regs[31] <= regs[31] + 4;
									state <= STATE_EXECUTE_00_1;
								end
							default:
									state <= STATE_EXECUTE_00_1;
							endcase
					end
					else if(Opcode != OP_MOV) begin
						case (Td)
							MODE_IMMEDIATE:
								begin
									size_imm <= size_m == SIZE_64 ? 4'd8 : 4'd4;
									if (size_m == SIZE_8) begin			// ma qua c'� o no??
										temp[7:0] <= Imm8;
										state <= STATE_EXECUTE_01_1;
										end
									else begin
										ea_indirect <= regs[31];
										state <= STATE_EXECUTE_00_1;
									end
								end
							MODE_IMMEDIATE8:		// ma qua c'� o no??
								begin
									temp[7:0] <= Imm8;
									state <= STATE_EXECUTE_01_1;
								end
							MODE_REGISTER:
								begin
									case (size_m)
										SIZE_8:  temp <= regs[Rd][7:0];
										SIZE_16: temp <= regs[Rd][15:0];
										SIZE_32: temp <= regs[Rd][31:0];
										SIZE_64: temp <= regs[Rd][31:0];		// finire
									endcase
									state <= STATE_EXECUTE_01_1;
								end
							MODE_REGISTER_INDIRECT:
								begin
									ea_indirect <= regs[Rd];
									state <= STATE_EXECUTE_00_1;
								end
							MODE_INDEXED:
								begin
									if (Rd) begin
										ea_indirect <= regs[Rd];
									end else begin
										ea_indirect <= 0;
									end
									regs[31] <= regs[31] + 4;
									state <= STATE_EXECUTE_00_1;
								end
							MODE_INDEXED_2_REG:
								begin
									ea_indirect <= regs[Rd]+regs[Mm];		// sicuro qua?
									state <= STATE_EXECUTE_00_1;
								end
							MODE_INDEXED_SHORT:
								begin
									ea_indirect <= regs[Rd]+Imm8;				// sicuro qua?
									state <= STATE_EXECUTE_00_1;
								end
							MODE_INDIRECT_PREINC:
								begin
									case (size_m)
										0: begin
											ea_indirect <= regs[Rd]+0;
											regs[Rd] <= regs[Rd]+1;
											end
										1: begin
											ea_indirect <= regs[Rd]+0;
											regs[Rd] <= regs[Rd]+2;
											end
										2: begin
											ea_indirect <= regs[Rd]+4;
											regs[Rd] <= regs[Rd]+4;
											end
									endcase
									state <= STATE_EXECUTE_00_1;
								end
							MODE_INDIRECT_PREDEC:
								begin
									case (size_m)
										0: begin
											ea_indirect <= regs[Rs]-4;
											regs[Rd] <= regs[Rd]-1;
											end
										1: begin
											ea_indirect <= regs[Rs]-4;
											regs[Rd] <= regs[Rd]-2;
											end
										2: begin
											ea_indirect <= regs[Rs]-4;
											regs[Rd] <= regs[Rd]-4;
											end
									endcase
									state <= STATE_EXECUTE_00_1;
								end
							MODE_INDIRECT_POSTINC:
								begin
									ea_indirect <= regs[Rd];
									state <= STATE_EXECUTE_00_1;
									post_count <= 1;
								end
							MODE_INDIRECT_POSTDEC:
								begin
									ea_indirect <= regs[Rd];
									state <= STATE_EXECUTE_00_1;
									post_count <= -1;		// 2'd non lo prende...
								end
							MODE_INDIRECT64:
								begin

								end
							MODE_INDIRECT64_POSTINC:
								begin

								end
							MODE_INDIRECT64_2_REG:
								begin

								end
						endcase

						if(Opcode == OP_POP) begin
							state <= STATE_POP_0;
						end
						else begin
							state <= STATE_EXECUTE_00_1;
						end
					end
					else begin
						state <= STATE_EXECUTE_00_1;		// verificare, completare
					end
					
					end


		  
      STATE_EXECUTE_00_1:			// 18
        begin
          mem_address <= ea_indirect + immediate_count;
          mem_bus_enable <= 1;
          immediate_count <= immediate_count + 4'd4;
	      state <= STATE_EXECUTE_01_0;
        end
		  
      STATE_EXECUTE_01_0:			// 19
        begin
          mem_bus_enable <= 0;
          case (size_m)
            SIZE_8: temp[7:0]   <= mem_read[7:0];
            SIZE_16: temp[15:0]  <= mem_read[15:0];
            SIZE_32: temp[31:0]  <= mem_read[31:0];
            SIZE_64: temp[31:0]  <= mem_read[31:0];		// FINIRE! gestire 64 con immediate_count=8 
          endcase
          if (immediate_count == size_imm)
	          state <= STATE_EXECUTE_01_1;
          else
	          state <= STATE_EXECUTE_00_1;
        end
		  
      STATE_EXECUTE_01_1:			// 20
        begin
          state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;

          case (Opcode)
            OP_MOV:
							result <= source;
            OP_CLR:
							result <= 0;
            OP_SET:
							result <= 32'hffffffff;
            OP_RDTS:
							result <= tsc;		// fare poi 64 bit come tutto
            OP_CPUID:
							result <= 32'h47443234;			// fare 64 bit , "GD24 032 "
            OP_OR: 
							result <= temp | source;
            OP_AND: 
							result <= temp & source;
            OP_XOR: 
							result <= temp ^ source;
            OP_NAND: 
							result <= ~(temp & source);
            OP_NOR:
							result <= ~(temp | source);
            OP_NEG:
							result <= ~source;
            OP_NOT:
							result <= source ? 32'h00000000 : 32'hffffffff;
            OP_ABS:
							result <= source < 0 ? -source : source;
            OP_TB:
				begin
							result <= temp & (1 << source);
                wb <= 0;
				end
            OP_SBO:
							result <= temp | (1 << source);
            OP_SBZ:
							result <= temp & ~(1 << source);
            OP_DAA:
				begin
				
				end
            OP_EX:
				begin
					result <= source;
				end
            OP_SWAP:
				begin
				  case (size_m)
					SIZE_8: result <= { source[3:0], source[7:4] } ;
					SIZE_16: result <= { source[7:0], source[15:8] } ;
					SIZE_32: result <= { source[15:0], source[31:16] } ;
					SIZE_64: ;		// FINIRE! 
				  endcase
				end
            OP_ADD:
              begin
                result <= temp + source;
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_ADC:
              begin
                result <= temp + source + flag_c;
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_SUB:
              begin
                result <= temp - source;
                is_sub <= 1;
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_SBC:
              begin
                result <= temp - source - flag_c;
                is_sub <= 1;
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_CMP:
              begin
                result <= temp - source;
                wb <= 0;
                is_sub <= 1;
                affects_c <= 1;
              end
            OP_MUL:
              begin
                result <= temp * source;
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_DIV:
              begin
                result <= temp / source;
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_IMUL:
              begin
                result <= $signed(temp) * $signed(source);
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_IDIV:
              begin
                result <= $signed(temp) / $signed(source);
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_STST:
							result[31:0] <= flags[31:0];
            OP_LEA:
							begin
								result <= ea_indirect;
								if (!instruction[24]) begin		// LEA
								end
								else begin		 // PEA
			            state <= STATE_PUSH_0;
								end
							end
            OP_LDM:
							begin
		            state <= STATE_WRITEBACK_R;		// finire!
							end
            OP_STM:
							begin
		            state <= STATE_WRITEBACK_MEM_P;	// finire!
							end
				
						OP_JMP:
							begin
								regs[31] <= temp;		// opp state <= STATE_JMP_3; 
							end
						OP_CALL,OP_BLWP:
							begin
								if (condIsOk(Cond)) begin
									if (!instruction[24]) begin
										size_imm <= 4;
										result[31:0] <= regs[31][31:0];
										state <= STATE_PUSH_0;		// opp				state <= STATE_JMP_3;
									end
									else begin
										regs[30][31:0] <= regs[31][31:0];
										state <= STATE_FETCH_OP_0;
									end
									regs[31] <= temp;		// opp state <= STATE_JMP_3; 
									if (Opcode == OP_BLWP && flag_remapr) begin
										regs[29] <= wp;
										wp <= 0;		// finire!!
									end
									end
								else begin
								// saltare parm... UNIRE con altri, qua
									state <= STATE_FETCH_OP_0;
								end
							end
						OP_RET,OP_RTWP:
							begin
								if (condIsOk(Cond)) begin
									if (!instruction[24]) begin
										size_imm <= 4;
										state <= STATE_POP_0;
									end
									else begin
										regs[31][31:0] <= regs[30][31:0];
										state <= STATE_FETCH_OP_0;
									end
									if (Opcode == OP_RTWP && flag_remapr) begin
										wp <= regs[29];		// finire!!
									end
									end
								else begin
								// saltare parm... UNIRE con altri, qua
									state <= STATE_FETCH_OP_0;
								end
							end
         endcase

        end
		  
      STATE_EXECUTE_10_0:
        begin
			case (Opcode)
				OP_ROT:
					begin
						if(Rs[4])		// 
							rotate_count = Rs[3:0];
						else
							rotate_count = regs[Rs[3:0]][5:0];
							// gestire 64bit!!?
						if(!rotate_count)
							rotate_count <= 63;    // gestire 64bit!!?
						state <= STATE_EXECUTE_10_1;
					end
				OP_DEC: 
					begin
						result <= temp - 1;
		        state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
					end
				OP_INC: 
					begin
						result <= temp + 1;
		        state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
					end
			endcase

        end
		  
      STATE_EXECUTE_10_1:
        begin

          case (Opcode)
            OP_ROT:
						begin
							case (Mm)
								0: begin			// SLA
									case (size_m)
										SIZE_8:  result[8:0]  <= { source[7],  source[6:0],  1'b0 };
										SIZE_16: result[16:0] <= { source[15], source[14:0], 1'b0 };
										SIZE_32: result[32:0] <= { source[31], source[30:0], 1'b0 };
									endcase
									end
								1: begin			// SRA
									case (size_m)
										SIZE_8:  result[8:0]  <= { source[0], source[7], source[7:1]  };
										SIZE_16: result[16:0] <= { source[0], source[15], source[15:1] };
										SIZE_32: result[32:0] <= { source[0], source[31], source[31:1] };
									endcase
									end
								2: begin			// SRL
									case (size_m)
										SIZE_8:  result[8:0]  <= { source[0], 1'b0, source[7:1]  };
										SIZE_16: result[16:0] <= { source[0], 1'b0, source[15:1] };
										SIZE_32: result[32:0] <= { source[0], 1'b0, source[31:1] };
									endcase
									end
								3: begin			// RR
									case (size_m)
										SIZE_8:  result[8:0]  <= { source[0], source[0], source[7:1]  };
										SIZE_16: result[16:0] <= { source[0], source[0], source[15:1] };
										SIZE_32: result[32:0] <= { source[0], source[0], source[31:1] };
									endcase
									end
								4: begin			// RRC
									case (size_m)
										SIZE_8:  result[8:0]  <= { source[0], flag_c, source[7:1]  };
										SIZE_16: result[16:0] <= { source[0], flag_c, source[15:1] };
										SIZE_32: result[32:0] <= { source[0], flag_c, source[31:1] };
									endcase
									end
								5: begin			// RL
									case (size_m)
										SIZE_8:  result[8:0]  <= { source[7],  source[6:0],  source[7] };
										SIZE_16: result[16:0] <= { source[15], source[14:0], source[15] };
										SIZE_32: result[32:0] <= { source[31], source[30:0], source[31] };
									endcase
									end
								6: begin			// RLC
									case (size_m)
										SIZE_8:  result[8:0]  <= { source[7],  source[6:0],  flag_c };
										SIZE_16: result[16:0] <= { source[15], source[14:0], flag_c };
										SIZE_32: result[32:0] <= { source[31], source[30:0], flag_c };
									endcase
									end
								endcase
								affects_c <= 1;
								if (rotate_count) begin
									rotate_count <= rotate_count-6'd1;
								end
								else 
								  begin
									state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
								  end
							end
          endcase


        end
		  
      STATE_WRITEBACK_R:		// 23
        begin
					if(wb) begin
						case (size_m)
							SIZE_8:  regs[Rd][7:0] <= result[7:0];
							SIZE_16: regs[Rd][15:0] <= result[15:0];
							SIZE_32: regs[Rd][31:0] <= result[31:0];
						endcase
						
						if (DoFlags)
							state <= STATE_SET_FLAGS_0;
						else
							state <= STATE_FETCH_OP_0;
					end
					else
						state <= STATE_FETCH_OP_0;
	      end
	  
      STATE_WRITEBACK_MEM_P:		// 26
        begin
					if(wb) begin
						size_imm <= size_m == SIZE_64 ? 4'd8 : 4'd4;
					
						case (size_m)
							SIZE_8:
								wb_count=0;
							SIZE_16:
								wb_count=0;
							SIZE_32:
								wb_count=0;
							SIZE_64:
								wb_count=4;
						endcase
							
						state <= STATE_WRITEBACK_MEM_0;
					end
				  else
						state <= STATE_FETCH_OP_0;
        end
		  
      STATE_WRITEBACK_MEM_0:		// 27
        begin
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          mem_address <= ea_indirect + wb_count;

					case (size_m)
						SIZE_8:
							case (mem_address[1:0])
								0: mem_write[7:0] <= result[7:0];
								1: mem_write[15:8] <= result[7:0];
								2: mem_write[23:16] <= result[7:0];
								3: mem_write[31:24] <= result[7:0];
							endcase
						SIZE_16:
							case (mem_address[1])
								0: mem_write[15:0] <= result[15:0];
								1: mem_write[31:16] <= result[15:0];
							endcase
						SIZE_32:
							mem_write[31:0] <= result[31:0];
						SIZE_64:
							mem_write[31:0] <= result[31:0];
					endcase

          wb_count <= wb_count + 4'd4;

          state <= STATE_WRITEBACK_MEM_1;
        end
		  
      STATE_WRITEBACK_MEM_1:		// 28
        begin
          mem_bus_enable <= 0;
          mem_write_enable <= 0;

          if (wb_count == size_imm) begin
						if(post_count>0)
							case (size_m)
								0: begin
									regs[Rd] <= regs[Rd]+0;
									end
								1: begin
									regs[Rd] <= regs[Rd]+0;
									end
								2: begin
									regs[Rd] <= regs[Rd]+4;
									end
							endcase
							regs[Rd] <= regs[Rd]+1;
						if(post_count<0)
							case (size_m)
								0: begin
									regs[Rd] <= regs[Rd]-4;
									end
								1: begin
									regs[Rd] <= regs[Rd]-4;
									end
								2: begin
									regs[Rd] <= regs[Rd]-4;
									end
							endcase

						if (DoFlags)
							state <= STATE_SET_FLAGS_0;
						else
		          state <= STATE_FETCH_OP_0;
					end
          else
            state <= STATE_WRITEBACK_MEM_0;
        end
		  
      STATE_SET_FLAGS_0:
        begin
					
					case (size_m)
						SIZE_8:
							begin
								if(affects_c) flags[FLAG_C] <= result[8];
								flags[FLAG_Z] <= result[7:0] == 0;
								flags[FLAG_S] <= result[7];
								if(affects_ov) flags[FLAG_OV] <= temp[7] == (source[7] ^ is_sub) && result[7] != temp[7];
								flags[FLAG_P] <= parity_gen(temp[7:0]);
								flags[FLAG_HC] <= 0;
							end
						SIZE_16:
							begin
								if(affects_c) flags[FLAG_C] <= result[16];
								flags[FLAG_Z] <= result[15:0] == 0;
								flags[FLAG_S] <= result[15];
								if(affects_ov) flags[FLAG_OV] <= temp[15] == (source[15] ^ is_sub) && result[15] != temp[15];
								flags[FLAG_HC] <= 0;
							end
						SIZE_32:
							begin
								if(affects_c) flags[FLAG_C] <= result[32];
								flags[FLAG_Z] <= result[31:0] == 0;
								flags[FLAG_S] <= result[31];
								if(affects_ov) flags[FLAG_OV] <= temp[31] == (source[31] ^ is_sub) && result[31] != temp[31];
								flags[FLAG_HC] <= 0;
							end
						SIZE_64:
							begin
							end
					endcase

          state <= STATE_FETCH_OP_0;
        end
		  
      STATE_PUSH_0:
        begin
          push_count <= size_imm;
          state <= STATE_PUSH_1;
        end
		  
      STATE_PUSH_1:
        begin
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
					if(flag_cpumode==MODE_SVC)
						mem_address <= ssp;
					else
						mem_address <= usp;

          case (push_count)
            0: mem_write[31:0] <= result[31:0];
						4: ;
          endcase

          push_count <= push_count - 3'd4;
					if(flag_cpumode==MODE_SVC)
						ssp <= ssp - 4;
					else
						usp <= usp - 4;
          state <= STATE_PUSH_2;
        end
		  
      STATE_PUSH_2:
        begin
          mem_bus_enable <= 0;
          mem_write_enable <= 0;

          if (push_count == 0)
            state <= STATE_FETCH_OP_0;
          else
            state <= STATE_PUSH_1;
        end
		  
      STATE_POP_0:
        begin
					if(flag_cpumode==MODE_SVC) begin
						ssp <= ssp + 4;
						mem_address <= ssp;
						end
					else begin
						usp <= usp + 4;
						mem_address <= usp;
						end
          mem_bus_enable <= 1;
          pop_count <= pop_count + 3'd4;
          state <= STATE_POP_1;
        end
		  
      STATE_POP_1:
        begin
          mem_bus_enable <= 0;

          case (pop_count)
            0: source[31:0] <= mem_read[31:0];
            4: ;
          endcase

          if (pop_count == size_imm)
            state <= STATE_POP_WB;
          else
            state <= STATE_POP_0;
        end
		  
      STATE_POP_WB:
        begin
          case (Opcode)
            OP_RET:
							begin
								regs[31][31:0] <= source[31:0];
								if (Td != MODE_IMMEDIATE) begin
									result <= Imm8;
					        state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
								end
								else
									state <= STATE_FETCH_OP_0;
							end
            OP_POP:
							begin
								result[31:0] <= source[31:0];
				        state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
							end
          endcase

        end
		  
      STATE_RTI_0:
        begin
					if(flag_cpumode==MODE_SVC) begin
						ssp <= ssp + 4;
						mem_address <= ssp;
						end
					else begin
						usp <= usp + 4;
						mem_address <= usp;
						end
          mem_bus_enable <= 1;
          immediate_count <= immediate_count + 4'd4;
          state <= STATE_RTI_1;
        end
		  
      STATE_RTI_1:
        begin
          mem_bus_enable <= 0;

          case (immediate_count)
            1: flags[31:0] <= mem_read[31:0];
            2: regs[31][31:0]  <= mem_read[31:0];
          endcase

          if (immediate_count == size_imm)
            state <= STATE_FETCH_OP_0;
          else
            state <= STATE_RTI_0;
        end
		  
	  
      STATE_TEST_BITS:
        begin
			 flags[FLAG_Z] <= (source[31:0] & regs[Rs][31:0]) == 0;

			 
				result[31:0] <= source[31:0] & ~regs[Rs][31:0];
          state <= STATE_WRITEBACK_MEM_0;
        end
		  
      STATE_JMP_0:
        begin
          mem_address <= regs[31];
          mem_bus_enable <= 1;
//          regs[31] <= regs[31] + 4;
          state <= STATE_JMP_1;
        end
		  
      STATE_JMP_1:
        begin
          if (indirect_count == 0) begin
            ea_indirect[31:0] <= mem_read[31:0];
            state <= STATE_JMP_0;
          end else begin

              ea_indirect[31:0] <= mem_read[31:0];
              state <= STATE_JMP_2;
          end

          indirect_count <= indirect_count + 2'd1;
          mem_bus_enable <= 0;
        end
		  
      STATE_JMP_2:
        begin
          mem_address <= ea_indirect;
          mem_bus_enable <= 1;
          ea_indirect <= ea_indirect + 4;
          state <= STATE_JMP_3;
        end
		  
      STATE_JMP_3:
        begin
          mem_bus_enable <= 0;

          regs[31] <= temp;

          if (Opcode != OP_JMP) begin
            // CALL/BL
            size_imm <= 4;
            result <= regs[31][31:0];
            state <= STATE_PUSH_0;
          end else begin
            state <= STATE_FETCH_OP_0;
          end

        end
			
			
      STATE_ERROR:
        begin
          state <= STATE_ERROR;
          mem_bus_enable <= 0;
          mem_write_enable <= 0;
        end
		  
      STATE_HALTED:
        begin
          if(button_halt) begin
            state <= STATE_FETCH_OP_0;
            //flags[FLAG_B] <= 0;
          end else begin
            //flags[FLAG_B] <= 1;
          end

          mem_bus_enable <= 0;
          mem_write_enable <= 0;
        end
		  
      STATE_IRQ_0:		// opp. unire con STATE_PUSH come in JSR
        begin
          mem_address <= flag_cpumode==MODE_SVC ? ssp : usp;
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          immediate_count <= immediate_count + 4'd4;
          case (immediate_count)
            0: mem_write[31:0] <= regs[31][31:0];
            4: mem_write[31:0] <= flags[31:0];
          endcase

          ssp <= ssp - 4;
          state <= STATE_IRQ_1;
        end
		  
      STATE_IRQ_1:
        begin
          mem_bus_enable <= 0;
          mem_write_enable <= 0;

          if (immediate_count == size_imm) begin
            state <= STATE_FETCH_OP_0;
//				regs[31] <= 16'hff50;
				
            regs[31] <= IRQlevel << 3;
            mem_address <= IRQlevel << 3;
			 instruction <= 8'h4c;		// non 6c... strano
				state <= STATE_DECODE;
				end
          else
            state <= STATE_IRQ_0;
	  
        end
		  
    endcase
end

function condIsOk(input [3:0] cond);
	if (!IsCond) 
		condIsOk=1'b1;
	else 
		case (cond)
			4'h0: condIsOk = flag_z;		// BE
			4'h1: condIsOk = !flag_z;			// BNE
			4'h2: condIsOk = flag_c;			// BC
			4'h3: condIsOk = !flag_c;			// BNC
			4'h4: condIsOk = flag_s;		// BMI
			4'h5: condIsOk = !flag_s;		// BPL
			4'h6: condIsOk = flag_ov;		// BV
			4'h7: condIsOk = !flag_ov;		// BNV
			4'h8: condIsOk = flag_c && !flag_z;			// BHI
			4'h9: condIsOk = !(flag_c && !flag_z);			// BLS
			4'ha: condIsOk = flag_s == flag_ov;			// BGE
			4'hb: condIsOk = flag_s != flag_ov;			// BLT
			4'hc: condIsOk = flag_z && (flag_s == flag_ov);			// BGT		sbagliato?? cfr 2026 Simulatore
			4'hd: condIsOk = !(flag_z && (flag_s == flag_ov));			// BLE
			4'he: condIsOk = flag_p;			// BPE
			4'hf: condIsOk = !flag_p;			// BPO
	endcase
endfunction


function parity_gen(input [7:0] d);			// https://www.engineersgarage.com/verilog-tutorial-12-how-to-design-8-bit-parity-generator-and-checker-circuits-in-verilog/
	reg t1,t2,t3,t4,t5,t6;

	t1 = d[0] ^ d[1];
	t2 = d[2] ^ t1;
	t3 = d[3] ^ t2;
	t4 = d[4] ^ t3;
	t5 = d[5] ^ t4;
	t6 = d[6] ^ t5;
	parity_gen = d[7] ^ t6;
endfunction
	

always @(posedge raw_clk) begin
  case (mux_state)
		0: seg_data = seven_seg(digit0);
		1: seg_data = seven_seg(digit1);
		2: seg_data = seven_seg(digit2);
		3: seg_data = seven_seg(digit3);
  endcase


// Multiplexing + refresh
  refresh_counter <= refresh_counter + 16'd1;

  if (refresh_counter == 16'd49999) begin   // ~250 Hz (Grok delirava :D : con 24999 200Hz per digit ? refresh totale ~800Hz
		refresh_counter <= 0;
		digit3 <= regs[31][15:12];
		digit2 <= regs[31][11:8];
		digit1 <= regs[31][7:4];
		digit0 <= regs[31][3:0];
		mux_state <= mux_state + 2'd1;
  end

  segments <= seg_data;           // Segmenti
  digits   <= ~(4'b0001 << mux_state);  // Attiva un digit alla volta (attivo basso)
	
end

    function [6:0] seven_seg(input [3:0] val);
        case (val)
            4'h0: seven_seg = 7'b0111111;
            4'h1: seven_seg = 7'b0000110;
            4'h2: seven_seg = 7'b1011011;
            4'h3: seven_seg = 7'b1001111;
            4'h4: seven_seg = 7'b1100110;
            4'h5: seven_seg = 7'b1101101;
            4'h6: seven_seg = 7'b1111101;
            4'h7: seven_seg = 7'b0000111;
            4'h8: seven_seg = 7'b1111111;
            4'h9: seven_seg = 7'b1101111;
            4'ha: seven_seg = 7'b1110111;
            4'hb: seven_seg = 7'b1111100;
            4'hc: seven_seg = 7'b0111001;
            4'hd: seven_seg = 7'b1011110;
            4'he: seven_seg = 7'b1111001;
            4'hf: seven_seg = 7'b1110001;
        endcase
    endfunction

	 
memory_bus memory_bus_0(
  .address        (mem_address),
  .data_in        (mem_write),
  .data_out       (mem_read),
  .bus_enable     (mem_bus_enable),
  .write_enable   (mem_write_enable),
  .bus_halt       (mem_bus_halted),
  .clk            (clk),
  .raw_clk        (raw_clk),
  //.debug          (debug),
  .reset          (mem_bus_reset)
);

io_bus io_bus_0(
  .address        (io_address),
  .data_in        (io_write),
  .data_out       (io_read),
  .bus_enable     (io_bus_enable),
  .write_enable   (io_write_enable),
  .clk            (clk),
  .raw_clk        (raw_clk),
  .speaker_p      (speaker_p),
  .speaker_m      (speaker_m),
//  .ioport_0       (ioport_0),
  .ioport_0       (ioport_0),
  .ioport_1       (ioport_1),
  .ioport_2       (ioport_2),
  .ioport_3       (ioport_3),
  .ioport_4       (ioport_4),
  .button_0       (button_0),
  .uart_tx_0      (uart_tx_0),
  .uart_rx_0      (uart_rx_0),
  //.debug          (debug),
  .reset          (mem_bus_reset)		// usarne un altro
);

reg_mode reg_mode_0(
  .x      (flag_b)
);

endmodule


