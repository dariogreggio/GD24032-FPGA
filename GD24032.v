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
`ifdef SIMULATION
(* preserve, noprune *)
`endif
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
`ifdef SIMULATION
(* preserve, noprune *)
reg [31:0] pc;		// per simulazione PD @£$%&
`endif
`ifdef SIMULATION
(* preserve, noprune *)
reg [31:0] reg0;		// per simulazione PD @£$%&
(* preserve, noprune *)
reg [31:0] reg1;		// 
(* preserve, noprune *)
reg [31:0] reg2;		// 
`endif


reg [3:0] size_imm;	// questo è in byte (arrotondato a dword cmq ossia 4, 8
//reg [2:0] size_wb;


// Program counter, instruction, effective address.
reg [31:0] instruction;
reg [31:0] ea_indirectS;
reg [31:0] ea_indirectD;
// pc � regs[31] ma ho paura che appesantisca... e in fondo non ha molto senso, magari mettere a parte
// tra l'altro, il pc dovrebbe essere 64 bit!

wire [2:0] Reg3;
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
assign Reg3 = instruction[2:0];
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
wire [16:0] Branch;
assign Branch = {instruction[20:12],instruction[7:0]};
wire [3:0] RotateCnt;
assign RotateCnt = instruction[6:3];



// Used for ALU.
reg [MAX_OPERAND_SIZE-1:0] source;		// 
reg [MAX_OPERAND_SIZE /*-1*/:0] temp;		// serve extra bit per rotate
reg [MAX_OPERAND_SIZE:0] result;
reg wb;
reg is_sub;
reg in_repeat;
reg [1:0] irq_or_trap;		// 0 IRQ, 1 Eccezione, 2 Trap, 3 XOP
reg affects_c;
reg affects_ov;
reg affects_s;		// questo forse non serve

// Used for MOVS ecc
//reg [31:0] block_source;			// servono davvero?
//reg [31:0] block_destination;

// Addressing mode.
reg [1:0] indirect_count;		// # dword
reg [1:0] indirect_total;		// # dword
reg [3:0] immediate_count;		// 1..8 (arrotondato a dword)
reg [5:0] rotate_count;		// 0..63
reg [3:0] push_count;
reg [3:0] pop_count;		// non � mai usato insieme a push, ma se li unifico spreco pi� celle...
reg [3:0] wb_count;		// 1..8 (arrotondato a dword) (usare per write a 64bit
reg [1:0] post_count;

reg [31:0] reg_mask;		// per STM/LDM
reg [31:0] reg_count;		

// per BINS ecc (ottimizzare
reg [31:0] bit_src;      // sorgente
reg [31:0] bit_dest;     // destinazione (per BINS)
reg [31:0] bit_result;
reg [5:0]  bit_pos;
reg [5:0]  bit_len;
reg [5:0]  bit_len_orig;
reg [5:0]  bit_counter;
reg        bit_sign_ext;
reg        bit_fill;        // per BINS "copri"
reg        search_dir;
reg        search_type;
reg [31:0] bbb_type;



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

reg [4:0] excep_code;		// max 28 codici e vettori
reg [31:0] excep_addr;
reg [31:0] excep_pc;
reg [3:0] excep_state;

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

parameter STATE_FETCH_IMMEDIATE_0 = 6'd9;
parameter STATE_FETCH_IMMEDIATE_1 = 6'd10;

parameter STATE_EXECUTE_0_0      = 6'd11;
parameter STATE_EXECUTE_0_1      = 6'd12;

parameter STATE_EXECUTE_1_0      = 6'd13;
parameter STATE_EXECUTE_1_1      = 6'd14;

parameter STATE_EXECUTE_2_0      = 6'd15;
parameter STATE_EXECUTE_2_1      = 6'd16;

parameter STATE_EXECUTE_3_0      = 6'd17;
parameter STATE_EXECUTE_3_1      = 6'd18;

parameter STATE_EXECUTE_4_0      = 6'd50;		// riordinare!
parameter STATE_EXECUTE_4_1      = 6'd51;
parameter STATE_EXECUTE_4_2      = 6'd52;

parameter STATE_EXECUTE_5        = 6'd53;

parameter STATE_WRITEBACK_R       = 6'd19;

parameter STATE_WRITEBACK_MEM_P   = 6'd20;
parameter STATE_WRITEBACK_MEM_0   = 6'd21;
parameter STATE_WRITEBACK_MEM_1   = 6'd22;

parameter STATE_SET_FLAGS_0       = 6'd23;
parameter STATE_SET_FLAGS_1       = 6'd24;

parameter STATE_READ_IO_0         = 6'd25;
parameter STATE_READ_IO_1         = 6'd26;

parameter STATE_WRITE_IO_0        = 6'd27;
parameter STATE_WRITE_IO_1        = 6'd28;

parameter STATE_PUSH_0            = 6'd29;
parameter STATE_PUSH_1            = 6'd30;
parameter STATE_PUSH_2            = 6'd31;

parameter STATE_POP_0             = 6'd32;
parameter STATE_POP_1             = 6'd33;
parameter STATE_POP_WB            = 6'd34;

parameter STATE_RTI_0             = 6'd35;
parameter STATE_RTI_1             = 6'd36;

parameter STATE_LDM_STM           = 6'd37;

parameter STATE_LDM_0             = 6'd38;
parameter STATE_LDM_1             = 6'd39;

parameter STATE_STM_0             = 6'd40;
parameter STATE_STM_1             = 6'd41;

parameter STATE_STEX_0            = 6'd41;
parameter STATE_STEX_1            = 6'd42;

`ifdef USA_DSP
parameter STATE_VMA_0             = 6'd58;
`endif

parameter STATE_IRQ_0							= 6'd59;
parameter STATE_IRQ_1							= 6'd60;

parameter STATE_ERROR             = 6'd61;
parameter STATE_EXCEPTION         = 6'd62;
parameter STATE_HALTED            = 6'd63;

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
parameter OP_B			= 7'h50;
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

parameter MODE_USER=2'd0;
parameter MODE_FIQ=2'd1;
parameter MODE_IRQ=2'd2;
parameter MODE_SVC=2'd3;

parameter TRAP_BUS_ERROR=5'd0;
parameter TRAP_ADDRESS_ERROR=5'd1;
parameter TRAP_ADDRESS_ERROR2=5'd2;				// occhio verificare con Sim !
parameter TRAP_ILLEGAL_OPCODE=5'd3;
parameter TRAP_DIVIDE_BY_ZERO=5'd4;
parameter TRAP_OUT_OF_BOUNDS=5'd5;
parameter TRAP_OVERFLOW=5'd6;
parameter TRAP_PRIVILEGE_VIOLATION=5'd7;
parameter TRAP_IOPL_VIOLATION=5'd8;
parameter TRAP_TRACE=5'd9;
parameter TRAP_LAST=5'd30;

parameter TRAP_IRQ_LEVEL=4'd6;
parameter XOP_IRQ_LEVEL=4'd6;

parameter IRQ_BUTTON_0=4'd1;		// define per questi non va £$%#


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
	else if (state==STATE_HALTED || state==STATE_EXCEPTION)
		leds_value <= 15; 
	else
		leds_value <= ~regs[0][4:0];

end



// This block is the main CPU instruction execute state machine.
always @(posedge clk) begin

`ifdef SIMULATION
	pc <= regs[31][31:0];		// per simulazione PD @£$%&
	reg0 <= regs[0][31:0];		// per simulazione PD @£$%&
	reg1 <= regs[1][31:0];		// per simulazione PD @£$%&
	reg2 <= regs[2][31:0];		// per simulazione PD @£$%&
`endif

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

						
/* provare, come irq/trap
						ea_indirectD <= 32'h00000004;
						instruction <= 32'h80880000;		// JMP, INDEXED, Rd=0
						size_imm <= 4'd4;
						state <= STATE_EXECUTE_1_0 //STATE_DECODE;
						*/

						
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
          ea_indirectS <= 0;
          ea_indirectD <= 0;
					post_count <= 0;
          size_imm <= 4;
          is_sub <= 0;
					in_repeat <= 0;
					irq_or_trap <= 0;
          affects_ov <= 0;
          affects_c <= 0;
          affects_s <= 1;
          wb <= 1;

//					if (regs[31][1:0] || ssp[1:0] || usp[1:0]) begin				METTERE? o fare diversamente?
//											excep_code <= TRAP_ADDRESS_ERROR;
//						state <= STATE_EXCEPTION;
//					end

					io_bus_enable <= 0;
					io_write_enable <= 0;

          mem_address <= regs[31];
          mem_bus_enable <= 1;
			 
				  if(!button_irq) begin
						if (IRQ_BUTTON_0 < flag_irqmask) begin

							size_imm <= 8;		// 2 dword da salvare
	//						immediate_count <= 0;
							IRQlevel <= IRQ_BUTTON_0;
							irq_or_trap <= 0;
							state <= STATE_IRQ_0;
						end
						else
							state <= STATE_FETCH_OP_1;
					end
					else
						state <= STATE_FETCH_OP_1;
					end

		  
      STATE_FETCH_OP_1:
        begin
          mem_bus_enable <= 0;
          instruction = mem_read;		// NON <=
					
					if(Opcode == OP_CLR || Opcode == OP_SET || Opcode == OP_SE || Opcode == OP_DAA
						|| Opcode == OP_SWAP || Opcode == OP_EX || Opcode == OP_INC
						|| Opcode == OP_DEC || Opcode == OP_NEG || Opcode == OP_NOT || Opcode == OP_ABS
						|| Opcode == OP_ROT || Opcode == OP_CALL || Opcode == OP_BLWP
						|| Opcode == OP_RET || Opcode == OP_SKIP || Opcode == OP_TRAP 
						|| Opcode == OP_RTWP || Opcode == OP_HALT) begin
						if (condIsOk(Cond) == 0) begin
							reg [4:0] skip_count=0;		// max 16

							if (Td == MODE_INDEXED)
								skip_count = skip_count + 4;		// gestire addr 64


		          regs[31] <= regs[31] + skip_count;
							state <= STATE_FETCH_OP_0;

						end else begin
							state <= STATE_DECODE;
						end
					end else begin
						state <= STATE_DECODE;
					end

					// DOPO!
					if((Opcode==7'h70 || Opcode==7'h72 || Opcode==7'h76 || Opcode==7'h7f) && flag_cpumode<MODE_SVC) begin
						// eccezione!
						excep_code <= TRAP_PRIVILEGE_VIOLATION;
						state <= STATE_EXCEPTION;
					end
          regs[31] <= regs[31] + 4;
        end
		  
      STATE_DECODE:
        begin
				  tsc <= tsc + 1;		// direi giusto qua

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
//									if (MAX_OPERAND_SIZE==64) // meglio lasciarlo cmq per eseguire lo stesso le istruzioni, seppur tronche!
										size_imm <= size_m == SIZE_64 ? 4'd8 : 4'd4;
//									else
//										size_imm <= 4'd4;
									if (size_m == SIZE_8) begin
										source[7:0] <= Imm8;
										state <= STATE_EXECUTE_2_0;
										end
									else begin
										ea_indirectS <= regs[31];
										state <= STATE_FETCH_IMMEDIATE_0;
									end
								end
							MODE_IMMEDIATE8:
								begin
									source[7:0] <= Imm8;
									state <= STATE_EXECUTE_2_0;
								end
							MODE_REGISTER:
								begin
									case (size_m)
										SIZE_8:  source[7:0] <= regs[Rs][7:0];
										SIZE_16: source[15:0] <= regs[Rs][15:0];
										SIZE_32: source[31:0] <= regs[Rs][31:0];
										SIZE_64: begin 
											if (MAX_OPERAND_SIZE==64) begin
												source[31:0] <= regs[Rs][31:0]; 
											end
											else
												;
											end
									endcase
									state <= STATE_EXECUTE_2_0;
								end
							MODE_REGISTER_INDIRECT:
								begin
									ea_indirectS <= regs[Rs];
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDEXED:
								begin
									if (Rs) begin
										ea_indirectS <= regs[Rs];
									end else begin
										ea_indirectS <= 0;
									end
									state <= STATE_FETCH_INDIRECT_0;
								end
							MODE_INDEXED_2_REG:
								begin
									ea_indirectS <= regs[Rs]+regs[Mm];
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDEXED_SHORT:
								begin
									ea_indirectS <= regs[Rs]+Imm8;
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT_PREINC:
								begin
									case (size_m)
										SIZE_8: begin
											ea_indirectS <= regs[Rs]+1;
											regs[Rs] <= regs[Rs]+1;
											end
										SIZE_16: begin
											ea_indirectS <= regs[Rs]+2;
											regs[Rs] <= regs[Rs]+2;
											end
										SIZE_32: begin
											ea_indirectS <= regs[Rs]+4;
											regs[Rs] <= regs[Rs]+4;
											end
									endcase
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT_PREDEC:
								begin
									case (size_m)
										SIZE_8: begin
											ea_indirectS <= regs[Rs]-1;
											regs[Rs] <= regs[Rs]-1;
											end
										SIZE_16: begin
											ea_indirectS <= regs[Rs]-2;
											regs[Rs] <= regs[Rs]-2;
											end
										SIZE_32: begin
											ea_indirectS <= regs[Rs]-4;
											regs[Rs] <= regs[Rs]-4;
											end
									endcase
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT_POSTINC:
								begin
									ea_indirectS <= regs[Rs];
									case (size_m)
										SIZE_8: begin
											regs[Rs] <= regs[Rs]+1;
											end
										SIZE_16: begin
											regs[Rs] <= regs[Rs]+2;
											end
										SIZE_32: begin
											regs[Rs] <= regs[Rs]+4;
											end
									endcase
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT_POSTDEC:
								begin
									ea_indirectS <= regs[Rs];
									case (size_m)
										SIZE_8: begin
											regs[Rs] <= regs[Rs]-1;
											end
										SIZE_16: begin
											regs[Rs] <= regs[Rs]-2;
											end
										SIZE_32: begin
											regs[Rs] <= regs[Rs]-4;
											end
									endcase
									state <= STATE_FETCH_INDIRECT_2;
								end
							MODE_INDIRECT64:
								begin
									if (MAX_ADDRESS_SIZE==64) begin
										if (flag_addr64)
											indirect_total <= 2;
										else begin
											excep_code <= TRAP_ILLEGAL_OPCODE;
											state <= STATE_EXCEPTION;
										end
									end
									else begin
										excep_code <= TRAP_ILLEGAL_OPCODE;
										state <= STATE_EXCEPTION;
									end
								end
							MODE_INDIRECT64_POSTINC:
								begin
									if (MAX_ADDRESS_SIZE==64) begin
										if (flag_addr64)
											indirect_total <= 2;
										else begin
											excep_code <= TRAP_ILLEGAL_OPCODE;
											state <= STATE_EXCEPTION;
										end
									end
									else begin
										excep_code <= TRAP_ILLEGAL_OPCODE;
										state <= STATE_EXCEPTION;
									end
								end
							MODE_INDIRECT64_2_REG:
								begin
									if (MAX_ADDRESS_SIZE==64) begin
										if (flag_addr64)
											indirect_total <= 2;
										else begin
											excep_code <= TRAP_ILLEGAL_OPCODE;
											state <= STATE_EXCEPTION;
										end
										end
									else begin
										excep_code <= TRAP_ILLEGAL_OPCODE;
										state <= STATE_EXCEPTION;
									end
								end
						endcase
					end
					else begin
						if(Opcode == OP_CLR || Opcode == OP_SET || Opcode == OP_SE || Opcode == OP_DAA
						// creare un Opcode senza LSB per fare meglio i confronti?
							|| Opcode == OP_SWAP
							|| Opcode == OP_RDTS || Opcode == OP_CPUID || Opcode == OP_INC || Opcode == OP_DEC
							|| Opcode == OP_NEG || Opcode == OP_NOT || Opcode == OP_ABS || Opcode == OP_ROT
							|| Opcode == OP_JMP || Opcode == OP_DJNZ || Opcode == OP_CALL || Opcode == OP_BLWP
							|| Opcode == OP_RET || Opcode == OP_POP || Opcode == OP_LDM
							|| Opcode == OP_STM || Opcode == OP_STST || Opcode == OP_STSP
							) begin
							state <= STATE_EXECUTE_2_0;
							end 
						else if(Opcode == OP_B) begin
						  if (condIsOk(Cond)) begin
								regs[31][31:0] <= $signed(regs[31][31:0]) + $signed( { Branch,2'd0 } );
							end
							state <= STATE_FETCH_OP_0;
							end
						else if(Opcode == OP_POP) begin
							size_imm <= 4'd4;
							state <= STATE_POP_0;
						end
						else if(Opcode == OP_NOP) begin
							state <= STATE_FETCH_OP_0;
						end
						else if(Opcode == OP_TRAP) begin
							if (!Imm8[7] || flag_ov) begin		// TRAPV
								immediate_count <= 0;
								size_imm <= 4'd8;
//									regs[31] <= 32'h00000100 | (Imm8[5:0] << 3);

								// SALVARE WP?!
								wp <= 32'h00000104 | (Imm8 << 3);
								// FARE INDIREZIONE!!

								flags[FLAG_CPUMODE+1:FLAG_CPUMODE] <= MODE_SVC;
								irq_or_trap <= 2;
								flags[FLAG_TRAP] <= 1;
								state <= STATE_IRQ_0;

							end
							else
								state <= STATE_FETCH_OP_0;
							end
						else
							state <= STATE_EXECUTE_2_0;
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
          ea_indirectS[31:0] <= ea_indirectS[31:0] + mem_read[31:0];
          state <= STATE_FETCH_INDIRECT_2;
        end
		  
      STATE_FETCH_INDIRECT_2:
        begin
          mem_address <= ea_indirectS;
          ea_indirectS <= ea_indirectS + 4;
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
            state <= STATE_EXECUTE_2_0;
          end else begin
            state <= STATE_FETCH_INDIRECT_2;
          end
        end
		  
      STATE_FETCH_IMMEDIATE_0:			// 11
        begin
          mem_address <= ea_indirectS + immediate_count;
          mem_bus_enable <= 1;
					regs[31] <= regs[31] + 4;
          immediate_count <= immediate_count + 4'd4;
          state <= STATE_FETCH_IMMEDIATE_1;
        end
		  
      STATE_FETCH_IMMEDIATE_1:			// 12
        begin
          mem_bus_enable <= 0;

          case (size_m)
            SIZE_8: source[7:0]   <= mem_read[7:0];
            SIZE_16: source[15:0]  <= mem_read[15:0];
            SIZE_32: source[31:0]  <= mem_read[31:0];
            SIZE_64: begin 
							if (MAX_OPERAND_SIZE==64) begin
								source[31:0]  <= mem_read[31:0]; 		// FINIRE! gestire 64 con immediate_count=8 
							end
							else
								;
							end
          endcase

          if (immediate_count == size_imm)
            state <= STATE_EXECUTE_2_0;
          else
            state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_EXECUTE_2_0:		// 13; pre-esecuzione, vado a leggere secondo operando
        begin
					if(Opcode == OP_PUSH) begin
						result[31:0] <= source[31:0];
						state <= STATE_PUSH_0;
					end
					else if(Opcode == OP_LDIM) begin
						flags[31:FLAG_IRQMASK] <= source[4:0];
						state <= STATE_FETCH_OP_0;
					end
					else if(Opcode == OP_LDSP) begin
						if (instruction[13]) begin		// LDSP
							if(instruction[12])
								ssp[31:0] <= source[31:0];
							else
								usp[31:0] <= source[31:0];
							end
						else begin		// LDWP
							if(flag_remapr)
								wp[31:0] <= source[31:0];
							end
						state <= STATE_FETCH_OP_0;
					end
					else if(Opcode == OP_LDST) begin
						if(flag_cpumode==MODE_SVC) begin
							case (size_m)
								SIZE_8:  flags[7:0] <= source[7:0];
								default: flags[31:0] <= source[31:0];
							endcase
						end
						else
							flags[7:0] <= source[7:0]; // ev. eccezione se size>8
						state <= STATE_FETCH_OP_0;
					end
					else if(Opcode == OP_HALT) begin
					// halt
						state <= STATE_HALTED;
					end
/*					else if(Opcode == OP_MOV) begin	// in effetti � una cagata... volevo evitare di leggere la dest ma tutto il resto serve!
						case (Td)
							MODE_INDEXED:
								begin
									if (Rd) begin
										ea_indirectD <= regs[Rd];
									end else begin
										ea_indirectD <= 0;
									end
									regs[31] <= regs[31] + 4;
									state <= STATE_EXECUTE_1_0;
								end
							default:
									state <= STATE_EXECUTE_1_0;
							endcase
					end
					else if(Opcode != OP_MOV) begin
					*/
					else begin
						case (Td)
							MODE_IMMEDIATE:
								begin
//								if (MAX_OPERAND_SIZE==64) // meglio lasciarlo cmq per eseguire lo stesso le istruzioni, seppur tronche!
										size_imm <= size_m == SIZE_64 ? 4'd8 : 4'd4;
//									else
//										size_imm <= 4'd4;
									if (size_m == SIZE_8) begin			// ma qua c'� o no??
										temp[7:0] <= Imm8;
										state <= STATE_EXECUTE_2_1;
										end
									else begin
										ea_indirectD <= regs[31];
										regs[31] <= regs[31] + 4;
										state <= STATE_EXECUTE_1_0;
									end
								end
							MODE_IMMEDIATE8:		// ma qua c'� o no?? s� per LDM/STM direi
								begin
									temp[7:0] <= Imm8;
									state <= STATE_EXECUTE_2_1;
								end
							MODE_REGISTER:
								begin
									case (size_m)
										SIZE_8:  temp[7:0] <= regs[Rd][7:0];
										SIZE_16: temp[15:0] <= regs[Rd][15:0];
										SIZE_32: temp[31:0] <= regs[Rd][31:0];
										SIZE_64: begin 
											if (MAX_OPERAND_SIZE==64) begin
												temp[31:0] <= regs[Rd][31:0];		// finire
											end
											else
												;
											end
									endcase
									state <= STATE_EXECUTE_2_1;
								end
							MODE_REGISTER_INDIRECT:
								begin
									ea_indirectD <= regs[Rd];
									state <= STATE_EXECUTE_1_0;
								end
							MODE_INDEXED:
								begin
									if (Rd) begin
										ea_indirectD <= regs[Rd];
									end else begin
										ea_indirectD <= 0;
									end
//									regs[31] <= regs[31] + 4;
									state <= STATE_EXECUTE_0_0;
								end
							MODE_INDEXED_2_REG:
								begin
									ea_indirectD <= regs[Rd]+regs[Mm];		// sicuro qua?
									state <= STATE_EXECUTE_1_0;
								end
							MODE_INDEXED_SHORT:
								begin
									ea_indirectD <= regs[Rd]+Imm8;				// sicuro qua?
									state <= STATE_EXECUTE_1_0;
								end
							MODE_INDIRECT_PREINC:
								begin
									case (size_m)
										SIZE_8: begin
											ea_indirectD <= regs[Rd]+1;
											regs[Rd] <= regs[Rd]+1;
											end
										SIZE_16: begin
											ea_indirectD <= regs[Rd]+2;
											regs[Rd] <= regs[Rd]+2;
											end
										SIZE_32: begin
											ea_indirectD <= regs[Rd]+4;
											regs[Rd] <= regs[Rd]+4;
											end
									endcase
									state <= STATE_EXECUTE_1_0;
								end
							MODE_INDIRECT_PREDEC:
								begin
									case (size_m)
										SIZE_8: begin
											ea_indirectD <= regs[Rs]-1;
											regs[Rd] <= regs[Rd]-1;
											end
										SIZE_16: begin
											ea_indirectD <= regs[Rs]-2;
											regs[Rd] <= regs[Rd]-2;
											end
										SIZE_32: begin
											ea_indirectD <= regs[Rs]-4;
											regs[Rd] <= regs[Rd]-4;
											end
									endcase
									state <= STATE_EXECUTE_1_0;
								end
							MODE_INDIRECT_POSTINC:
								begin
									ea_indirectD <= regs[Rd];
									state <= STATE_EXECUTE_1_0;
									post_count <= 1;
								end
							MODE_INDIRECT_POSTDEC:
								begin
									ea_indirectD <= regs[Rd];
									state <= STATE_EXECUTE_1_0;
									post_count <= -1;		// 2'd non lo prende...
								end
							MODE_INDIRECT64:
								begin
									if (MAX_ADDRESS_SIZE==64) begin
										if (flag_addr64)
											;
										else begin
											excep_code <= TRAP_ILLEGAL_OPCODE;
											state <= STATE_EXCEPTION;
										end
									end
									else begin
										excep_code <= TRAP_ILLEGAL_OPCODE;
										state <= STATE_EXCEPTION;
									end
								end
							MODE_INDIRECT64_POSTINC:
								begin
									if (MAX_ADDRESS_SIZE==64) begin
										if (flag_addr64)
											;
										else begin
											excep_code <= TRAP_ILLEGAL_OPCODE;
											state <= STATE_EXCEPTION;
										end
									end
									else begin
										excep_code <= TRAP_ILLEGAL_OPCODE;
										state <= STATE_EXCEPTION;
									end
								end
							MODE_INDIRECT64_2_REG:
								begin
									if (MAX_ADDRESS_SIZE==64) begin
										if (flag_addr64)
											;
										else begin
											excep_code <= TRAP_ILLEGAL_OPCODE;
											state <= STATE_EXCEPTION;
										end
										end
									else begin
										excep_code <= TRAP_ILLEGAL_OPCODE;
										state <= STATE_EXCEPTION;
									end
								end
						endcase

						if(Opcode == OP_POP) begin
							state <= STATE_POP_0;
						end
						else begin
//							state <= STATE_EXECUTE_1_0;
						end
					end
					
					end

      STATE_EXECUTE_0_0:		// 11; qua faccio indirezione a partire da valore subito dopo PC
        begin
          mem_address <= regs[31];
					regs[31] <= regs[31]+4;
          mem_bus_enable <= 1;
          immediate_count <= 0;
					size_imm <= 4;
		      state <= STATE_EXECUTE_0_1;
				end

      STATE_EXECUTE_0_1:		// 12
        begin
          mem_bus_enable <= 0;
          ea_indirectD <= ea_indirectD + mem_read[31:0];

          state <= STATE_EXECUTE_1_0;
				end
		  
      STATE_EXECUTE_1_0:			// 13; qua faccio indirezione a partire da ea_indirectD
        begin
          mem_address <= ea_indirectD + immediate_count;
//					regs[31] <= regs[31]+4;
          mem_bus_enable <= 1;
          immediate_count <= immediate_count + 4'd4;
	      state <= STATE_EXECUTE_1_1;
        end
		  
      STATE_EXECUTE_1_1:			// 14
        begin
          mem_bus_enable <= 0;
          case (size_m)
            SIZE_8: temp[7:0]   <= mem_read[7:0];
            SIZE_16: temp[15:0]  <= mem_read[15:0];
            SIZE_32: temp[31:0]  <= mem_read[31:0];
            SIZE_64: begin  
							if (MAX_OPERAND_SIZE==64) begin
								temp[31:0]  <= mem_read[31:0];	 	// FINIRE! gestire 64 con immediate_count=8 
							end
							else
								;
							end
          endcase
          if (immediate_count == size_imm)
	          state <= STATE_EXECUTE_2_1;
          else
	          state <= STATE_EXECUTE_1_0;
        end
		  
      STATE_EXECUTE_2_1:			// 16; eseguo istruzione
        begin
          state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;

          case (Opcode)
            OP_MOV,OP_MOVS:
							begin
								result <= source;
								in_repeat <= Opcode[0];
							end
	           OP_XLAT:		// 				// usare condiz per scegliere BYTE o DWORD puntatore..??
							 begin
//										if (MAX_OPERAND_SIZE==64) begin
									if (/*IsCond*/ instruction[21])
										mem_address <= temp[31:0] + source[31:0] << size_m;		// unsigned
									else
										mem_address <= temp[31:0] + source[7:0] << size_m;		// unsigned;
				          mem_bus_enable <= 1;
									state <= STATE_EXECUTE_5;
							 end
		         OP_CLR:
							result <= 0;
            OP_SET:
							result <= ~0;
            OP_RDTS:
							result[MAX_OPERAND_SIZE-1:0] <= tsc[MAX_OPERAND_SIZE-1:0];
            OP_CPUID:
							if (MAX_OPERAND_SIZE==64) 
								result[63:0] <= 64'h3033322047443234;			// "GD24032 "
							else
								result[31:0] <= 32'h47443234;			// , "GD24"
            OP_OR: 
							result <= temp | source;
            OP_AND:
							begin
								result <= temp & source;
								if (IsCond) begin		//            TEST
									wb <= 0;
									state <= STATE_SET_FLAGS_0;
								end
							end
            OP_XOR: 
							result <= temp ^ source;
            OP_NAND: 
							result <= ~(temp & source);
            OP_NOR:
							result <= ~(temp | source);
            OP_NEG:
							result <= ~temp;
            OP_NOT:
							case (size_m)
								SIZE_8:  result <= temp[7:0] ? 0 : ~0;
								SIZE_16: result <= temp[15:0] ? 0 : ~0;
								SIZE_32: result <= temp[31:0] ? 0 : ~0;
								SIZE_64: begin
									if (MAX_OPERAND_SIZE==64) begin
										result <= temp[63:0] ? 0 : ~0;
									end
									else
										;
									end
							endcase
            OP_ABS:
							case (size_m)
								SIZE_8:  result <= temp[7] ? -temp[7:0] : temp[7:0];
								SIZE_16: result <= temp[15] ? -temp[15:0] : temp[15:0];
								SIZE_32: result <= temp[31] ? -temp[31:0] : temp[31:0];
								SIZE_64: begin
									if (MAX_OPERAND_SIZE==64) begin
										result <= temp[63] ? -temp[63:0] : temp[63:0];
									end
									else
										;
									end
							endcase
            OP_TB:
							begin
								result <= temp & (1 << source[5:0]);			// beh :)
                wb <= 0;
							end
            OP_SBO:
							result <= temp | (1 << source[5:0]);
            OP_SBZ:
							result <= temp & ~(1 << source[5:0]);
            OP_DAA:
							begin
	/*						        case BYTE_SIZE:
          res3.w.l;
          i=_status.CCR.Carry;
          _status.CCR.Carry=0;
          if((res2.b.l & 0xf) > 9 || _status.CCR.HalfCarry) {
            res3.w.l+=6;
            res2.b.l=res3.b.l;
            _status.CCR.Carry= i || HIBYTE(res3.w.l);
            _status.CCR.HalfCarry=1;
            }
          else
            _status.CCR.HalfCarry=0;
          if((res2.b.l>0x99) || i) {
            res2.b.l+=0x60;  
            _status.CCR.Carry=1;
            }
          else
            _status.CCR.Carry=0;
*/
							end
            OP_EX:
							begin
								result[31:0] <= source[31:0];
// serve uno stato speciale, credo...
							end
            OP_SWAP:
							begin
								if (instruction[3]) begin		// SWAPR
									case (size_m)
										SIZE_32: result[31:0] <= { source[7:0], source[15:8], source[23:16], source[31:24] } ;
										default: begin
											excep_code <= TRAP_ILLEGAL_OPCODE;
											state <= STATE_EXCEPTION;
											end
									endcase
								end
								else begin
									case (size_m)
										SIZE_8: result[7:0] <= { source[3:0], source[7:4] } ;
										SIZE_16: result[15:0] <= { source[7:0], source[15:8] } ;
										SIZE_32: result[31:0] <= { source[15:0], source[31:16] } ;
										SIZE_64: begin
											if (MAX_OPERAND_SIZE==64) begin
												result[63:0] <= { source[31:0], source[63:32] } ;		// FINIRE
											end
											else
												;
											end
									endcase
								end
							end
            OP_ADD:
              begin
								case (size_m)
									SIZE_8: result[8:0] <= temp[7:0] + source[7:0];
									SIZE_16: result[16:0] <= temp[15:0] + source[15:0];
									SIZE_32: result[32:0] <= temp[31:0] + source[31:0];
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											result[64:0] <= temp[31:0] + source[31:0];		// FINIRE
										end
										else
											;
										end
								endcase
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_ADC:
              begin
								case (size_m)
									SIZE_8: result[8:0] <= temp[7:0] + source[7:0] + flag_c;
									SIZE_16: result[16:0] <= temp[15:0] + source[15:0] + flag_c;
									SIZE_32: result[32:0] <= temp[31:0] + source[31:0] + flag_c;
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											result[64:0] <= temp[31:0] + source[31:0];		// FINIRE
										end
										else
											;
										end
								endcase
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_SUB:
              begin
								case (size_m)
									SIZE_8: result[8:0] <= source[7:0] - temp[7:0];
									SIZE_16: result[16:0] <= source[15:0] - temp[15:0];
									SIZE_32: result[32:0] <= source[31:0] - temp[31:0];
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											result[64:0] <= source[31:0] - temp[31:0];		// FINIRE
										end
										else
											;
										end
								endcase
                is_sub <= 1;
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_SBC:
              begin
								case (size_m)
									SIZE_8: result[8:0] <= source[7:0] - temp[7:0] - flag_c;
									SIZE_16: result[16:0] <= source[15:0] - temp[15:0] - flag_c;
									SIZE_32: result[32:0] <= source[31:0] - temp[31:0] - flag_c;
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											result[64:0] <= source[31:0] - temp[31:0];		// FINIRE
										end
										else
											;
										end
								endcase
                is_sub <= 1;
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_CMP,OP_CMPS:
              begin
								case (size_m)
									SIZE_8: result[8:0] <= temp[7:0] - source[7:0];
									SIZE_16: result[16:0] <= temp[15:0] - source[15:0];
									SIZE_32: result[32:0] <= temp[31:0] - source[31:0];
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											result[64:0] <= temp[31:0] - source[31:0];		// FINIRE
										end
										else
											;
										end
								endcase
								in_repeat <= Opcode[0];
                wb <= 0;
                is_sub <= 1;
                affects_c <= 1;
              end
            OP_MUL:
              begin
								case (size_m)
									SIZE_8: result[8:0] <= temp[7:0] * source[7:0];
									SIZE_16: result[16:0] <= temp[15:0] * source[15:0];
									SIZE_32: result[32:0] <= temp[31:0] * source[31:0];
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											result[64:0] <= temp[31:0] * source[31:0];		// FINIRE
										end
										else
											;
										end
								endcase
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_DIV:
              begin
								case (size_m)
									SIZE_8: begin 
										if (!temp[7:0]) begin
											excep_code <= TRAP_DIVIDE_BY_ZERO;
											state <= STATE_EXCEPTION;
										end
										else
											result[8:0] <= source[7:0] / temp[7:0];
										end
									SIZE_16:  begin 
										if (!temp[15:0]) begin
											excep_code <= TRAP_DIVIDE_BY_ZERO;
											state <= STATE_EXCEPTION;
										end
										else
											result[16:0] <= source[15:0] / temp[15:0];
										end
									SIZE_32:  begin 
										if (!temp[31:0]) begin
											excep_code <= TRAP_DIVIDE_BY_ZERO;
											state <= STATE_EXCEPTION;
										end
										else
											result[32:0] <= source[31:0] / temp[31:0];
										end
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											if (!temp[31:0]) begin
												excep_code <= TRAP_DIVIDE_BY_ZERO;
												state <= STATE_EXCEPTION;
											end
											else
												result[64:0] <= source[31:0] / temp[31:0];		// FINIRE
										end
										else
											;
										end
								endcase
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_IMUL:
              begin
								case (size_m)
									SIZE_8: result[8:0] <= $signed(temp[7:0]) * $signed(source[7:0]);
									SIZE_16: result[16:0] <= $signed(temp[15:0]) * $signed(source[15:0]);
									SIZE_32: result[32:0] <= $signed(temp[31:0]) * $signed(source[31:0]);
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											result[64:0] <= $signed(temp[31:0]) * $signed(source[31:0]);		// FINIRE
										end
										else
											;
										end
								endcase
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_IDIV:
              begin
								case (size_m)
									SIZE_8: begin 
										if (!temp[7:0]) begin
											excep_code <= TRAP_DIVIDE_BY_ZERO;
											state <= STATE_EXCEPTION;
										end
										else
											result[8:0] <= $signed(source[7:0]) / $signed(temp[7:0]);
										end
									SIZE_16: begin 
										if (!temp[15:0]) begin
											excep_code <= TRAP_DIVIDE_BY_ZERO;
											state <= STATE_EXCEPTION;
										end
										else
											result[16:0] <= $signed(source[15:0]) / $signed(temp[15:0]);
										end
									SIZE_32: begin
										if (!temp[31:0]) begin
											excep_code <= TRAP_DIVIDE_BY_ZERO;
											state <= STATE_EXCEPTION;
										end
										else
											result[32:0] <= $signed(source[31:0]) / $signed(temp[31:0]);
										end
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											if (!temp[31:0]) begin
												excep_code <= TRAP_DIVIDE_BY_ZERO;
												state <= STATE_EXCEPTION;
											end
											else
												result[64:0] <= $signed(source[31:0]) / $signed(temp[31:0]);		// FINIRE
										end
										else
											;
										end
								endcase
                affects_c <= 1;
                affects_ov <= 1;
              end

						OP_INC,OP_DEC,OP_ROT:
							begin
								state <= STATE_EXECUTE_3_0;		// UNIRE per risparmiare un ciclo
							end

            OP_BINS,OP_BXTR,OP_BSFR:
							begin
								if (Reg3 == 0) begin
									mem_address <= ea_indirectS + immediate_count;
									mem_bus_enable <= 1;
									regs[31] <= regs[31] + 4;
								end
								else
									bbb_type <= regs[Reg3];
								
								state <= STATE_EXECUTE_4_0;		// 
              end

/*
// ==================== Registri da dichiarare nel modulo CPU ====================
reg [31:0] bit_temp;      // valore su cui lavorare
reg [31:0] bit_dest;      // destinazione per BINS
reg [5:0]  bit_counter;   // contatore per loop
reg [4:0]  bit_pos;       // posizione corrente
reg [5:0]  bit_len;       // lunghezza (0 = 32)
reg        bit_sign_ext;
reg [1:0]  bit_op;        // 0=BXTR, 1=BINS, 2=BSFR

// ==================== STATE_BITOP_PREP ====================
STATE_BITOP_PREP: begin
    case (Opcode)
        0x33: begin // BINS - Bit Insert
            bit_op      <= 2'd1;
            bit_pos     <= bs;                       // start bit
            bit_len     <= (bn == 0) ? 6'd32 : bn;
            bit_temp    <= res1.d;                   // dato da inserire
            bit_dest    <= res2.d;                   // destinazione originale
            bit_sign_ext<= (HIWORD(k) & 0x8000) ? 1'b1 : 1'b0;
            // TODO: gestisci flag "copri" (bit 30 di k)
        end

        0x34: begin // BXTR - Bit Extract
            bit_op      <= 2'd0;
            bit_pos     <= bs;
            bit_len     <= (bn == 0) ? 6'd32 : bn;
            bit_temp    <= res1.d;                   // sorgente
            bit_sign_ext<= (HIWORD(k) & 0x8000) ? 1'b1 : 1'b0;
            bit_dest    <= 32'h00000000;             // accumulatore per extract
        end

        0x35: begin // BSFR - Bit Search
            bit_op      <= 2'd2;
            bit_temp    <= res1.d;
            bit_counter <= 0;
            // dir e type gi� estratti da reg3
        end
    endcase
    
    state <= STATE_BITOP_EXEC;
end

// ==================== STATE_BITOP_EXEC (loop) ====================
STATE_BITOP_EXEC: begin
    case (bit_op)
        2'd0: begin // ==================== BXTR ====================
            if (bit_len == 0) begin
                result <= bit_dest;
                // sign extend
                if (bit_sign_ext && bit_dest[bit_len-1])   // attenzione: bit_len gi� decrementato
                    result <= bit_dest | ~((1 << original_bn) - 1);
                state <= WRITEBACK_STATE;
            end else begin
                bit_dest[31 - bit_len] <= bit_temp[bit_pos];  // allineamento a destra (MSB first)
                bit_pos  <= bit_pos + 1;
                bit_len  <= bit_len - 1;
            end
        end

        2'd1: begin // ==================== BINS ====================
            if (bit_len == 0) begin
                result <= bit_dest;
                state  <= WRITEBACK_STATE;
            end else begin
                bit_dest[bit_pos] <= bit_temp[0];
                bit_temp <= bit_temp >> 1;
                bit_pos  <= bit_pos + 1;
                bit_len  <= bit_len - 1;
            end
        end

        2'd2: begin // ==================== BSFR ====================
            if (bit_counter == 32) begin
                result <= 32'd32;           // non trovato
                // imposta flag Zero
                state  <= WRITEBACK_STATE;
            end
            else if (bit_temp[bit_search_dir ? (31 - bit_counter) : bit_counter] == bit_search_type) begin
                result <= bit_counter;
                state  <= WRITEBACK_STATE;
            end
            else begin
                bit_counter <= bit_counter + 1;
            end
        end
    endcase
end*/

/*
// Registri ausiliari
reg [31:0] bit_src, bit_dest, bit_mask, bit_result;
reg [5:0]  bit_pos, bit_len;
reg [5:0]  bit_counter;
reg        bit_sign_ext;
reg        fill_enable;
reg [1:0]  bit_op;   // 0=BXTR, 1=BINS, 2=BSFR

// ====================== PREP ======================
STATE_BITOP_PREP: begin
    case (Opcode)
        0x33: begin // BINS
            bit_op       <= 1;
            bit_src      <= res1.d;                    // valore da inserire
            bit_dest     <= res2.d;                    // destinazione
            bit_pos      <= LOBYTE(LOWORD(k)) & 5'h1F; // bs
            bit_len      <= (HIBYTE(LOWORD(k)) == 0) ? 6'd32 : HIBYTE(LOWORD(k)) & 5'h1F;
            bit_sign_ext <= HIWORD(k) & 16'h8000;
            fill_enable  <= HIWORD(k) & 16'h4000;
            bit_mask     <= 32'h00000001 << (LOBYTE(LOWORD(k)) & 5'h1F);
        end

        0x34: begin // BXTR
            bit_op       <= 0;
            bit_src      <= res1.d;
            bit_pos      <= LOBYTE(LOWORD(k)) & 5'h1F;
            bit_len      <= (HIBYTE(LOWORD(k)) == 0) ? 6'd32 : HIBYTE(LOWORD(k)) & 5'h1F;
            bit_sign_ext <= HIWORD(k) & 16'h8000;
            bit_result   <= 32'h0;
            bit_mask     <= 32'h80000000 >> (LOBYTE(LOWORD(k)) & 5'h1F);  // per extract
        end

        0x35: begin // BSFR
            bit_op      <= 2;
            bit_src     <= res1.d;
            bit_counter <= 0;
        end
    endcase
    state <= STATE_BITOP_EXEC;
end

// ====================== EXEC (bit per bit) ======================
STATE_BITOP_EXEC: begin
    case (bit_op)
        0: begin // BXTR
            if (bit_len == 0) begin
                result <= bit_result;
                if (bit_sign_ext && bit_result[bit_len-1])   // da aggiustare
                    result <= bit_result | ~((1 << original_len)-1);
                state <= WRITEBACK;
            end else begin
                bit_result[bit_len-1] <= bit_src[bit_pos];
                bit_pos  <= bit_pos + 1;
                bit_len  <= bit_len - 1;
            end
        end

        1: begin // BINS
            if (bit_len == 0) begin
                result <= bit_dest;
                state  <= WRITEBACK;
            end else begin
                bit_dest[bit_pos] <= bit_src[0];
                bit_src  <= bit_src >> 1;
                bit_pos  <= bit_pos + 1;
                bit_len  <= bit_len - 1;
            end
        end

        2: begin // BSFR
            if (bit_counter == 32) begin
                result <= 32'd32;
                state  <= WRITEBACK;
            end else if (bit_src[ bit_search_dir ? (31-bit_counter) : bit_counter ] == bit_search_type) begin
                result <= bit_counter;
                state  <= WRITEBACK;
            end else begin
                bit_counter <= bit_counter + 1;
            end
        end
    endcase
end*/

/*
// Registri da aggiungere
reg [31:0] bit_src;      // sorgente
reg [31:0] bit_dest;     // destinazione (per BINS)
reg [31:0] bit_result;
reg [5:0]  bit_pos;
reg [5:0]  bit_len;
reg [5:0]  bit_counter;
reg        bit_sign_ext;
reg        bit_fill;        // per BINS "copri"
reg [1:0]  bit_op;          // 0 = BXTR, 1 = BINS, 2 = BSFR
reg        search_dir;
reg        search_type;

// ====================== STATE_BITOP_PREP ======================
STATE_BITOP_PREP: begin
    // k = control word (da registro o immediato successivo)
    wire [31:0] k = 0 ; // logica per leggere k 

    case (Opcode)
        8'h33: begin // BINS
            bit_op      <= 2'd1;
            bit_src     <= res1.d;                          // valore da inserire
            bit_dest    <= res2.d;                          // destinazione
            bit_pos     <= k[7:0] & 6'h3F;                  // start position
            bit_len     <= (k[15:8] == 0) ? 6'd32 : k[15:8] & 6'h3F;
            bit_sign_ext<= k[31];
            bit_fill    <= k[30];                           // "copri"
        end

        8'h34: begin // BXTR
            bit_op      <= 2'd0;
            bit_src     <= res1.d;
            bit_pos     <= k[7:0] & 6'h3F;
            bit_len     <= (k[15:8] == 0) ? 6'd32 : k[15:8] & 6'h3F;
            bit_sign_ext<= k[31];
            bit_result  <= 32'h0;
        end

        8'h35: begin // BSFR
            bit_op       <= 2'd2;
            bit_src      <= res1.d;
            bit_counter  <= 6'd0;
            search_dir   <= 0;  // bit dal formato 
            search_type  <= 0;  // bit dal formato 
        end
    endcase

    state <= STATE_BITOP_EXEC;
end

// ====================== STATE_BITOP_EXEC ======================
STATE_BITOP_EXEC: begin
    case (bit_op)
        2'd0: begin // BXTR - Bit Extract
            if (bit_len == 0) begin
                result <= bit_result;
                if (bit_sign_ext && bit_result[bit_len_orig-1])
                    result <= bit_result | ~((1 << bit_len_orig) - 1);
                state <= WRITEBACK;
            end else begin
                bit_result[bit_len-1] <= bit_src[bit_pos];
                bit_pos <= bit_pos + 1;
                bit_len <= bit_len - 1;
            end
        end

        2'd1: begin // BINS - Bit Insert
            if (bit_len == 0) begin
                result <= bit_dest;
                state  <= WRITEBACK;
            end else begin
                bit_dest[bit_pos] <= bit_src[0];
                bit_src  <= bit_src >> 1;
                bit_pos  <= bit_pos + 1;
                bit_len  <= bit_len - 1;
            end
        end

        2'd2: begin // BSFR - Bit Search
            if (bit_counter == 32) begin
                result <= 32'd32;           // non trovato
                state  <= WRITEBACK;
            end else if (bit_src[ search_dir ? (31-bit_counter) : bit_counter ] == search_type) begin
                result <= bit_counter;
                state  <= WRITEBACK;
            end else begin
                bit_counter <= bit_counter + 1;
            end
        end
    endcase
end*/

            OP_STST:
							result[31:0] <= flags[31:0];
            OP_STSP:
							case (instruction[5:3]) 
								0: result[MAX_ADDRESS_SIZE-1:0] <= wp[MAX_ADDRESS_SIZE-1:0];			// STWP
								1: if(flag_cpumode>=MODE_IRQ) begin					 // STST; in IRQ uso ssp
										result[MAX_ADDRESS_SIZE-1:0] <= ssp;
									end
									else begin
										result[MAX_ADDRESS_SIZE-1:0] <= usp;
									end
								default:		// STEX
									begin
										immediate_count <= 0;
										state <= STATE_STEX_0;
									end

							endcase

            OP_LEA:
							begin
								result[MAX_ADDRESS_SIZE-1:0] <= ea_indirectS[MAX_ADDRESS_SIZE-1:0];
								if (!instruction[24]) begin		// LEA
								end
								else begin		 // PEA
									size_imm <= 4;
			            state <= STATE_PUSH_0;
								end
							end

            OP_ENTER:
							begin
								size_imm <= 4;
								result[31:0] <= regs[Rd][31:0];
								if (MAX_ADDRESS_SIZE)
									;
								if(flag_cpumode>=MODE_IRQ) begin		// in IRQ uso ssp
									regs[Rd] <= ssp;
									ssp[MAX_ADDRESS_SIZE-1:0] <= ssp[MAX_ADDRESS_SIZE-1:0] - source[31:0];
								end
								else begin
									regs[Rd] <= usp;
									usp[MAX_ADDRESS_SIZE-1:0] <= usp[MAX_ADDRESS_SIZE-1:0] - source[31:0];
								end
		            state <= STATE_PUSH_0;
							end
            OP_LEAVE:
							begin
								if(flag_cpumode>=MODE_IRQ) begin		// idem
									ssp <= regs[Rd];
								end
								else begin
									usp <= regs[Rd];
								end
								size_imm <= 4;
		            state <= STATE_POP_0;
							end
            OP_CHK:
							begin
								case (size_m)
									SIZE_8: begin 
										if (temp[7:0] < 0 || temp[7:0] > source[7:0]) begin
											excep_code <= TRAP_OUT_OF_BOUNDS;
											state <= STATE_EXCEPTION;
											end
										end
									SIZE_16: begin 
										if (temp[15:0] < 0 || temp[15:0] > source[15:0]) begin
											excep_code <= TRAP_OUT_OF_BOUNDS;
											state <= STATE_EXCEPTION;
											end
										end
									SIZE_32: begin
										if (temp[31:0] < 0 || temp[31:0] > source[31:0]) begin
											excep_code <= TRAP_OUT_OF_BOUNDS;
											state <= STATE_EXCEPTION;
											end
										end
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											if (temp[63:0] < 0 || temp[63:0] > source[63:0]) begin
												excep_code <= TRAP_OUT_OF_BOUNDS;
												state <= STATE_EXCEPTION;
												end
											end
										else
											;
										end
								endcase

							end

            OP_LDM:
							begin
								if (Td == MODE_IMMEDIATE8) begin
			            state <= STATE_LDM_0;
								end
								else begin
								  mem_address <= regs[31];
				          mem_bus_enable <= 1;
								  regs[31] <= regs[31] + 4;
			            state <= STATE_LDM_STM;
								end
								reg_mask[31:0] <= 32'h00000001;
								reg_count <= 0;
							end
			// (andrebbe invertita la bitmask tra LDM e STM?? come 68000...
            OP_STM:
							begin
								if (Td == MODE_IMMEDIATE8) begin
									reg_mask[31:0] <= 32'h00000080;
									reg_count <= 5'd7;
			            state <= STATE_STM_0;
								end
								else begin
									reg_mask[31:0] <= 32'h80000000;
									reg_count <= 5'd31;
								  mem_address <= regs[31];
				          mem_bus_enable <= 1;
								  regs[31] <= regs[31] + 4;
			            state <= STATE_LDM_STM;
								end
							end
				
						`ifdef USA_DSP
            OP_MAS,OP_MSS:
              begin
								case (size_m)
									SIZE_8: 
										begin
											result[7:0] <= temp[7:0];
											if (source[7:0]) begin
												if (instruction[21]) 			// sarebbe Condiz
													result[7:0] <= result[7:0] * -source[7:0];
												else
													result[7:0] <= result[7:0] * source[7:0];
											end
											else
												result[7:0] <= result[7:0] * result[7:0];
											if (Opcode == OP_MAS)
												result[7:0] <= result[7:0] + regs[Reg3][7:0];
											else
												result[7:0] <= result[7:0] - regs[Reg3][7:0];
										end
									SIZE_16:
										begin
											result[15:0] <= temp[15:0];
											if (source[15:0]) begin
												if (instruction[21]) 			// sarebbe Condiz
													result[15:0] <= result[15:0] * -source[15:0];
												else
													result[15:0] <= result[15:0] * source[15:0];
											end
											else
												result[15:0] <= result[15:0] * result[15:0];
											if (Opcode == OP_MAS)
												result[15:0] <= result[15:0] + regs[Reg3][15:0];
											else
												result[15:0] <= result[15:0] - regs[Reg3][15:0];
										end
									SIZE_32:
										begin
											result[31:0] <= temp[31:0];
											if (source[31:0]) begin
												if (instruction[21]) 			// sarebbe Condiz
													result[31:0] <= result[31:0] * -source[31:0];
												else
													result[31:0] <= result[31:0] * source[31:0];
											end
											else
												result[31:0] <= result[31:0] * result[31:0];
											if (Opcode == OP_MAS)
												result[31:0] <= result[31:0] + regs[Reg3][31:0];
											else
												result[31:0] <= result[31:0] - regs[Reg3][31:0];
										end
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											if (source[63:0]) begin
												if (instruction[21]) 			// sarebbe Condiz
													result[63:0] <= result[63:0] * -source[63:0];
												else
													result[63:0] <= result[63:0] * source[63:0];
											end
											else
												result[63:0] <= result[63:0] * result[63:0];
											if (Opcode == OP_MAS)
												result[63:0] <= result[63:0] + regs[Reg3][63:0];
											else
												result[63:0] <= result[63:0] - regs[Reg3][63:0];
										end
										else
											;
										end
								endcase
                affects_c <= 1;
                affects_ov <= 1;
              end
            OP_SSA:
							begin
								case (size_m)
									SIZE_8: 
										begin
											result[7:0] <= source[7:0]*source[7:0];
											if (source[7:0]) begin
												if (instruction[21]) 			// sarebbe Condiz
													result[7:0] <= result[7:0] + regs[Reg3][7:0]*regs[Reg3][7:0];
											end
											result[7:0] <= result[7:0] + temp[7:0];
										end
									SIZE_16:
										begin
											result[15:0] <= source[15:0]*source[15:0];
											if (source[15:0]) begin
												if (instruction[21]) 			// sarebbe Condiz
													result[15:0] <= result[15:0] + regs[Reg3][15:0]*regs[Reg3][15:0];
											end
											result[15:0] <= result[15:0] + temp[15:0];
										end
									SIZE_32:
										begin
											result[31:0] <= source[31:0]*source[31:0];
											if (source[31:0]) begin
												if (instruction[21]) 			// sarebbe Condiz
													result[31:0] <= result[31:0] + regs[Reg3][31:0]*regs[Reg3][31:0];
											end
											result[31:0] <= result[31:0] + temp[31:0];
										end
									SIZE_64: begin
										if (MAX_OPERAND_SIZE==64) begin
											result[63:0] <= source[63:0]*source[63:0];
											if (source[63:0]) begin
												if (instruction[21]) 			// sarebbe Condiz
													result[63:0] <= result[63:0] + regs[Reg3][63:0]*regs[Reg3][63:0];
											end
											result[63:0] <= result[63:0] + temp[63:0];
										end
										else
											;
										end
								endcase
							end
            OP_VMA:
							begin

		            state <= STATE_VMA_0;	// finire!
							end
						`endif

            OP_IN,OP_INS:
							begin
							in_repeat <= Opcode[0];
	            state <= STATE_READ_IO_0;
							end
            OP_OUT,OP_OUTS:
							begin
							in_repeat <= Opcode[0];
	            state <= STATE_WRITE_IO_0;
							end

						OP_JMP:
							begin
								regs[31] <= temp[MAX_ADDRESS_SIZE-1:0];	
							end
						OP_DJNZ:
							begin
								state <= STATE_EXECUTE_3_0;	// vado a eseguire DEC! ma forse � sbagliato.. deve riscrivere su S e non su D
								// UNIRE per risparmiare un ciclo
							end
						OP_SKIP:
							begin
								regs[31] <= regs[31] + { Imm8,2'b0 };
							end
						OP_CALL,OP_BLWP:
							begin
								if (condIsOk(Cond)) begin
									if (!instruction[24]) begin
										size_imm <= 4;
										result[MAX_ADDRESS_SIZE-1:0] <= regs[31][31:0];
										state <= STATE_PUSH_0;
									end
									else begin
										regs[30][31:0] <= regs[31][31:0];
										state <= STATE_FETCH_OP_0;
									end
									regs[31] <= temp[31:0];
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
						OP_RETI:
							begin
								if (flag_cpumode<MODE_IRQ) begin
									excep_code <= TRAP_PRIVILEGE_VIOLATION;
									state <= STATE_EXCEPTION;
								end
								else begin
				          size_imm <= 8;
									state <= STATE_RTI_0;
								end
							end
						OP_XOP:		// VERIFICARE e inserire sopra!
							begin
								immediate_count <= 0;
								size_imm <= 4;
								result[31:0] <= regs[31][31:0];
								state <= STATE_IRQ_0;
	//	            regs[31] <= 32'h00000100 | (Imm8 << 3);
								// FARE INDIREZIONE!!

		            wp <= 32'h00000104 | (Imm8 << 3);
									// FARE INDIREZIONE!!

									irq_or_trap <= 3;
							end

						OP_X:
							begin
								instruction[31:0] <= source[31:0];
								source[31:0] <= temp[31:0];
								state <= STATE_DECODE;

							end
         endcase

        end
		  
      STATE_EXECUTE_3_0:		// altra execute, per casi speciali
        begin
					case (Opcode)
						OP_ROT:
							begin
								reg [5:0] new_count;

								new_count = (Rs[4]) ? RotateCnt : regs[Rs[3:0]][5:0];		// qua, su local, = non d� problemi
    						if (new_count == 0)
									new_count = 6'd63;
								rotate_count <= new_count;    // gestire 64bit!!?
								state <= STATE_EXECUTE_3_1;
								// si pu� usare un ciclo for?? grok sconsiglia, ed � prevedibile
							end
						OP_DJNZ:
							begin
								result <= source - 1;
								if (result)
									regs[31] <= temp[MAX_ADDRESS_SIZE-1:0];	

								state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
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
		  
      STATE_EXECUTE_3_1:		// 18
        begin

          case (Opcode)
            OP_ROT:
						begin

	/*					STATE_ROT_LOOP: begin
    if (shift_count == 0) begin
        result <= shift_temp;
        state  <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
    end
    else begin
        // Applichiamo gli shift in ordine decrescente (16 ? 8 ? 4 ? 2 ? 1)
        if (shift_count[4]) begin   // bit 4 ? shift di 16
            shift_temp  <= do_shift(shift_temp, Mm, size_m, 4'd16);
            shift_count <= shift_count - 16;
        end
        else if (shift_count[3]) begin  // shift di 8
            shift_temp  <= do_shift(shift_temp, Mm, size_m, 4'd8);
            shift_count <= shift_count - 8;
        end
        else if (shift_count[2]) begin  // shift di 4
            shift_temp  <= do_shift(shift_temp, Mm, size_m, 4'd4);
            shift_count <= shift_count - 4;
        end
        else if (shift_count[1]) begin  // shift di 2
            shift_temp  <= do_shift(shift_temp, Mm, size_m, 4'd2);
            shift_count <= shift_count - 2;
        end
        else begin                      // shift di 1
            shift_temp  <= do_shift(shift_temp, Mm, size_m, 4'd1);
            shift_count <= shift_count - 1;
        end
    end
end
*/
    if (rotate_count == 0) begin
        result <= temp;
				affects_c <= 1;
        state  <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
    end
    else begin
							case (Mm)
								0: begin			// SLA
									case (size_m)
										SIZE_8:  temp[8:0]  <= { temp[7],  temp[6:0],  1'b0 };
										SIZE_16: temp[16:0] <= { temp[15], temp[14:0], 1'b0 };
										SIZE_32: temp[32:0] <= { temp[31], temp[30:0], 1'b0 };
										SIZE_64:
											begin
												if (MAX_OPERAND_SIZE==64) begin
												end
											end
									endcase
									end
								1: begin			// SRA
									case (size_m)
										SIZE_8:  temp[8:0]  <= { temp[0], temp[7], temp[7:1]  };
										SIZE_16: temp[16:0] <= { temp[0], temp[15], temp[15:1] };
										SIZE_32: temp[32:0] <= { temp[0], temp[31], temp[31:1] };
										SIZE_64:
											begin
												if (MAX_OPERAND_SIZE==64) begin
												end
											end
									endcase
									end
								2: begin			// SRL
									case (size_m)
										SIZE_8:  temp[8:0]  <= { temp[0], 1'b0, temp[7:1]  };
										SIZE_16: temp[16:0] <= { temp[0], 1'b0, temp[15:1] };
										SIZE_32: temp[32:0] <= { temp[0], 1'b0, temp[31:1] };
										SIZE_64:
											begin
												if (MAX_OPERAND_SIZE==64) begin
												end
											end
									endcase
									end
								3: begin			// RR
									case (size_m)
										SIZE_8:  temp[8:0]  <= { temp[0], temp[0], temp[7:1]  };
										SIZE_16: temp[16:0] <= { temp[0], temp[0], temp[15:1] };
										SIZE_32: temp[32:0] <= { temp[0], temp[0], temp[31:1] };
										SIZE_64:
											begin
												if (MAX_OPERAND_SIZE==64) begin
												end
											end
									endcase
									end
								4: begin			// RRC
									case (size_m)
										SIZE_8:  temp[8:0]  <= { temp[0], flag_c, temp[7:1]  };
										SIZE_16: temp[16:0] <= { temp[0], flag_c, temp[15:1] };
										SIZE_32: temp[32:0] <= { temp[0], flag_c, temp[31:1] };
										SIZE_64:
											begin
											end
									endcase
									end
								5: begin			// RL
									case (size_m)
										SIZE_8:  temp[8:0]  <= { temp[7],  temp[6:0],  temp[7] };
										SIZE_16: temp[16:0] <= { temp[15], temp[14:0], temp[15] };
										SIZE_32: temp[32:0] <= { temp[31], temp[30:0], temp[31] };
										SIZE_64:
											begin
											end
									endcase
									end
								6: begin			// RLC
									case (size_m)
										SIZE_8:  temp[8:0]  <= { temp[7],  temp[6:0],  flag_c };
										SIZE_16: temp[16:0] <= { temp[15], temp[14:0], flag_c };
										SIZE_32: temp[32:0] <= { temp[31], temp[30:0], flag_c };
										SIZE_64:
											begin
											end
									endcase
									end
							endcase
							rotate_count <= rotate_count - 6'd1;
							end
						end
          endcase
        end

			STATE_EXECUTE_4_0:			// altra execute per bit operations
        begin
					if (Reg3 == 0) begin
	          mem_bus_enable <= 0;
            bbb_type  <= mem_read[31:0];
					end
				state <= STATE_EXECUTE_4_1;
				end

			STATE_EXECUTE_4_1:
        begin
					case (Opcode)
						OP_BINS: 
							begin // BINS
								bit_src     <= source;                          // valore da inserire
								bit_dest    <= temp;                          // destinazione
								bit_pos     <= bbb_type[7:0] & 6'h3F;                  // start position
								bit_len     <= (bbb_type[15:8] == 0) ? 6'd32 : bbb_type[15:8] & 6'h3F;
								bit_sign_ext<= bbb_type[31];
								bit_fill    <= bbb_type[30];                           // "copri"
							end

						OP_BXTR: 
							begin // BXTR
								bit_src     <= source;
								bit_pos     <= bbb_type[7:0] & 6'h3F;
								bit_len     <= (bbb_type[15:8] == 0) ? 6'd32 : bbb_type[15:8] & 6'h3F;
								bit_sign_ext<= bbb_type[31];
								bit_result  <= 32'h0;
							end

						OP_BSFR: 
							begin // BSFR  si potrebbe cercare stringa e non solo 1 bit...
								bit_src      <= source;
								bit_counter  <= 6'd0;
								search_dir   <= 0 ;  // bit dal formato
								search_type  <= 0;  // bit dal formato
							end
					endcase

					state <= STATE_EXECUTE_4_2;
        end
		  
			STATE_EXECUTE_4_2:
        begin
					case (Opcode)
						OP_BXTR: 
							begin 
								if (bit_len == 0) begin
									result <= bit_result;
									if (bit_sign_ext && bit_result[bit_len_orig-1])
										result <= bit_result | ~((1 << bit_len_orig) - 1);
									state  <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
								end else begin
									bit_result[bit_len-1] <= bit_src[bit_pos];
									bit_pos <= bit_pos + 1;
									bit_len <= bit_len - 1;
								end
							end

						OP_BINS: 
							begin 
								if (bit_len == 0) begin
									result <= bit_dest;
									state  <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
								end else begin
									bit_dest[bit_pos] <= bit_src[0];
									bit_src  <= bit_src >> 1;
									bit_pos  <= bit_pos + 1;
									bit_len  <= bit_len - 1;
								end
							end

						OP_BSFR:
							begin 
								if (bit_counter == 32) begin
									result <= 32'd32;           // non trovato
									state  <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
								end else if (bit_src[ search_dir ? (31-bit_counter) : bit_counter ] == search_type) begin
									result <= bit_counter;
									state  <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
								end else begin
									bit_counter <= bit_counter + 1;
								end
							end
					endcase
        end

		  STATE_EXECUTE_5:		// per XLAT
				begin
          mem_bus_enable <= 0;
          case (size_m)
            SIZE_8: result[7:0]   <= mem_read[7:0];
            SIZE_16: result[15:0]  <= mem_read[15:0];
            SIZE_32: result[31:0]  <= mem_read[31:0];
            SIZE_64: begin  
							if (MAX_OPERAND_SIZE==64) begin
								result[31:0]  <= mem_read[31:0];	 	// FINIRE! gestire 64 con immediate_count=8 
							end
							else
								;
							end
          endcase
					state  <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
        end


      STATE_WRITEBACK_R:		// 23
        begin
					if(wb) begin
						case (size_m)
							SIZE_8:  regs[Rd][7:0] <= result[7:0];
							SIZE_16: regs[Rd][15:0] <= result[15:0];
							SIZE_32: regs[Rd][31:0] <= result[31:0];
							SIZE_64: begin  
								if (MAX_OPERAND_SIZE==64) begin
									regs[Rd][31:0] <= result[31:0];		// FINIRE
								end
								else
									;
								end
						endcase
					end
						
					if (DoFlags)
						state <= STATE_SET_FLAGS_0;
					else begin
						if (in_repeat) begin
							regs[Reg3] <= regs[Reg3] - 1;
							state <= regs[Reg3] ? STATE_DECODE : STATE_FETCH_OP_0;
						end
						else
							state <= STATE_FETCH_OP_0;
					end
	      end
	  
      STATE_WRITEBACK_MEM_P:		// 26
        begin
					if(wb) begin
//						if (MAX_OPERAND_SIZE==64) // meglio lasciarlo cmq per eseguire lo stesso le istruzioni, seppur tronche!
							size_imm <= size_m == SIZE_64 ? 4'd8 : 4'd4;
//						else
//							size_imm <= 4'd4;
						case (size_m)
							SIZE_8:
								wb_count=0;
							SIZE_16:
								wb_count=0;
							SIZE_32:
								wb_count=0;
							SIZE_64: begin
								if (MAX_OPERAND_SIZE==64) 
									wb_count=4;
								else
									;
								end
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
          mem_address <= ea_indirectD + wb_count;

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
							begin
								if (MAX_OPERAND_SIZE==64) begin
									mem_write[31:0] <= result[31:0];
								end
								else
									;
							end
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
						else begin
							if (in_repeat) begin
								regs[Reg3] <= regs[Reg3] - 1;
								state <= regs[Reg3] ? STATE_DECODE : STATE_FETCH_OP_0;
							end
							else
								state <= STATE_FETCH_OP_0;
						end
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
								flags[FLAG_HC] <= result[4];		// se _ROT va a 0!
							end
						SIZE_16:
							begin
								if(affects_c) flags[FLAG_C] <= result[16];
								flags[FLAG_Z] <= result[15:0] == 0;
								flags[FLAG_S] <= result[15];
								if(affects_ov) flags[FLAG_OV] <= temp[15] == (source[15] ^ is_sub) && result[15] != temp[15];
								flags[FLAG_HC] <= result[8];
							end
						SIZE_32:
							begin
								if(affects_c) flags[FLAG_C] <= result[32];
								flags[FLAG_Z] <= result[31:0] == 0;
								flags[FLAG_S] <= result[31];
								if(affects_ov) flags[FLAG_OV] <= temp[31] == (source[31] ^ is_sub) && result[31] != temp[31];
								flags[FLAG_HC] <= result[16];
							end
						SIZE_64:
							begin
								if (MAX_OPERAND_SIZE==64) begin
									if(affects_c) flags[FLAG_C] <= result[64];
									flags[FLAG_Z] <= result[64:0] == 0;
									flags[FLAG_S] <= result[64];
									if(affects_ov) flags[FLAG_OV] <= temp[63] == (source[63] ^ is_sub) && result[63] != temp[63];
									flags[FLAG_HC] <= result[32];
								end
								else
									;
							end
					endcase

					if (Opcode == OP_ADD || Opcode == OP_ADC || Opcode == OP_SBO || Opcode == OP_SBZ || Opcode == OP_TB)
						flags[FLAG_AS] <= 0;
					else if (Opcode == OP_SUB || Opcode == OP_SBC)
						flags[FLAG_AS] <= 1;

					if (in_repeat) begin
						flags[FLAG_AS] <= 0;
						flags[FLAG_D] <= (Td == MODE_INDIRECT_PREINC || Td == MODE_INDIRECT_POSTINC) ? 0 : 1;
						regs[Reg3] <= regs[Reg3] - 1;
						state <= regs[Reg3] ? STATE_DECODE : STATE_FETCH_OP_0;
					end
					else
						state <= STATE_FETCH_OP_0;
        end
		  
			STATE_READ_IO_0:
        begin
					io_bus_enable <= 1;
					state <= STATE_READ_IO_1;
        end

			STATE_READ_IO_1:
        begin
					case (size_m)
						SIZE_8: result[7:0] <= io_read[7:0];
						SIZE_16: result[15:0] <= io_read[7:0];		// boh, vedere se..
						SIZE_32: result[31:0] <= io_read[7:0];
					endcase
					io_bus_enable <= 0;
					state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
        end

			STATE_WRITE_IO_0:
        begin
					io_bus_enable <= 1;
					io_write_enable <= 1;
					case (size_m)
						SIZE_8: io_write[7:0] <= source[7:0];
						SIZE_16: io_write[7:0] <= source[7:0];		// boh idem
						SIZE_32: io_write[7:0] <= source[7:0];
					endcase
					state <= STATE_WRITE_IO_1;
        end

			STATE_WRITE_IO_1:
        begin
					io_write_enable <= 0;
					io_bus_enable <= 0;
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
					if(flag_cpumode>=MODE_IRQ) begin
						mem_address <= ssp-4;
						ssp <= ssp - 4;
						end
					else begin
						mem_address <= usp-4;
						usp <= usp - 4;
						end

// non va cmq			ram.dump_memory(0,2047);
// unsupported, cancro a voi						$fdisplay(log_file,"CALL: PC was %h, saved at = %h, push_count = %h", result, mem_address, push_count);
						
          case (push_count)
            4: mem_write[31:0] <= result[31:0];
						0: ;
          endcase

          push_count <= push_count - 3'd4;
          state <= STATE_PUSH_2;
        end
		  
      STATE_PUSH_2:
        begin
          mem_write_enable <= 0;
          mem_bus_enable <= 0;

          if (push_count == 0) begin
						case (Opcode)
							OP_TRAP:
								begin
									state <= STATE_IRQ_0;
								end
							OP_XOP:
								begin
									state <= STATE_IRQ_0;
								end
							default:
								state <= STATE_FETCH_OP_0;
							endcase
						end
          else
            state <= STATE_PUSH_1;
        end
		  
      STATE_POP_0:
        begin
          mem_bus_enable <= 1;
					if(flag_cpumode>=MODE_IRQ) begin
						mem_address <= ssp;
						ssp <= ssp + 4;
						end
					else begin
						mem_address <= usp;
						usp <= usp + 4;
						end
          pop_count <= pop_count + 3'd4;
          state <= STATE_POP_1;
        end
		  
      STATE_POP_1:
        begin
          mem_bus_enable <= 0;

          case (pop_count)
            4: source[31:0] <= mem_read[31:0];
            8: ;
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
// unsupported, cancro a voi			$fdisplay(log_file,"RET: loading from stack[%h] = %h  , pop_count = %h", mem_address, source[31:0], pop_count);								
// non va cmq			ram.dump_memory(0,2047);
								regs[31][31:0] <= source[31:0];
								if (Td != MODE_IMMEDIATE) begin
									result[7:0] <= Imm8;
					        state <= (Td == MODE_REGISTER) ? STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
								end
								else
									state <= STATE_FETCH_OP_0;
							end
						OP_LEAVE:
							begin
								regs[Rd][31:0] <= source[31:0];
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
					//if(flag_cpumode>=MODE_IRQ) begin		// stile 68000 - IRQ in modo user esistono solo dal 286 :) (ristorando i flag mi inculo! invertire o boh
						mem_address <= ssp;
						ssp <= ssp + 4;
//						end
          mem_bus_enable <= 1;
          immediate_count <= immediate_count + 4'd4;
          state <= STATE_RTI_1;
        end
		  
      STATE_RTI_1:
        begin
          mem_bus_enable <= 0;

          case (immediate_count)
            4: flags[31:0] <= mem_read[31:0];
            8: regs[31][31:0]  <= mem_read[31:0];
          endcase

          if (immediate_count == size_imm)
            state <= STATE_FETCH_OP_0;
          else
            state <= STATE_RTI_0;
        end

			STATE_LDM_STM:
				begin
          mem_bus_enable <= 0;
          temp[31:0] <= mem_read[31:0];
		      state <= Opcode == OP_LDM ? STATE_LDM_0 : STATE_STM_0;
        end
// (andrebbe invertita la bitmask tra LDM e STM?? come 68000... predecrement ossia save in stack parte da MSB=R31 e postincrement da LSB

			STATE_LDM_0:
				begin
          mem_address <= ea_indirectS;
          mem_bus_enable <= 1;
					if (!reg_mask)
	          state <= STATE_FETCH_OP_0;
					else if (temp & reg_mask)
	          state <= STATE_LDM_1;
					if (Td == MODE_IMMEDIATE8) begin
						reg_mask[7:0] <= (reg_mask[7:0] << 1);
						end
					else begin
						reg_mask[31:0] <= reg_mask[31:0] << 1;
					end
					reg_count <= reg_count + 5'd1;
				end

			STATE_LDM_1:
				begin
          mem_bus_enable <= 0;

					regs[reg_count] <= mem_read;
					case (size_m)
						SIZE_8:
							begin
		          ea_indirectS <= ea_indirectS + 1;
							end
						SIZE_16:
							begin
		          ea_indirectS <= ea_indirectS + 2;
							end
						SIZE_32:
							begin
		          ea_indirectS <= ea_indirectS + 4;
							end
						SIZE_64:
							begin
		          ea_indirectS <= ea_indirectS + 8;
							end
					endcase

					if(reg_mask)
						state <= STATE_LDM_0;
					else
	          state <= STATE_FETCH_OP_0;
				end

			STATE_STM_0:
				begin
//reg_mask
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          mem_address <= ea_indirectD;

					if (source & reg_mask) begin
						mem_write <= regs[reg_count];
						case (size_m)
							SIZE_8:
								begin
								ea_indirectD <= ea_indirectD + 1;
								end
							SIZE_16:
								begin
								ea_indirectD <= ea_indirectD + 2;
								end
							SIZE_32:
								begin
								ea_indirectD <= ea_indirectD + 4;
								end
							SIZE_64:
								begin
								ea_indirectD <= ea_indirectD + 8;
								end
						endcase
						end

					if (!reg_mask)
	          state <= STATE_FETCH_OP_0;
					else if (temp & reg_mask)
	          state <= STATE_STM_1;
					reg_mask[31:0] <= reg_mask[31:0] >> 1;
					reg_count <= reg_count - 5'd1;

				end

			STATE_STM_1:
				begin
          mem_write_enable <= 0;
          mem_bus_enable <= 0;

					if(reg_mask)
						state <= STATE_STM_0;
					else
            state <= STATE_FETCH_OP_0;
				end


			STATE_STEX_0:
				begin
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
					mem_address <= ssp-4;
					ssp <= ssp - 4;
						
          case (immediate_count)
            0: mem_write[31:0] <= excep_code[4:0];
            1: mem_write[31:0] <= excep_pc[31:0];
            2: mem_write[31:0] <= excep_addr[31:0];
            3: mem_write[31:0] <= excep_state[3:0];
          endcase

          immediate_count <= immediate_count + 3'd1;
          state <= STATE_STEX_1;
				end

			STATE_STEX_1:
				begin
          mem_write_enable <= 0;
          mem_bus_enable <= 0;

//fare!					
        if (immediate_count == 4)
          state <= STATE_FETCH_OP_0;
				else
          state <= STATE_STEX_0;
				end


`ifdef USA_DSP
			STATE_VMA_0:
				begin

					regs[Reg3] <= regs[Reg3] - 1;
					if (regs[Reg3])
            state <= STATE_FETCH_OP_0;
					else
            state <= STATE_FETCH_OP_0;
					flags[FLAG_HC] <= 0;
					flags[FLAG_AS] <= 0;
					flags[FLAG_D] <= 0;
				end
`endif
	  

      STATE_ERROR:
        begin
          state <= STATE_ERROR;
          mem_bus_enable <= 0;
          mem_write_enable <= 0;
        end
		  
      STATE_EXCEPTION:
				begin
          //excep_state[7:0];
          excep_addr[31:0] <= ea_indirectS[31:0];			// finire!
          excep_pc[31:0] <= regs[31][31:0];
          //excep_code[7:0];
					flags[FLAG_CPUMODE+1:FLAG_CPUMODE] <= MODE_SVC;
					irq_or_trap <= 1;
					state <= STATE_IRQ_0;
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
		  
      STATE_IRQ_0:		// // stile 68000 - IRQ in modo user esistono solo dal 286 :) 
        begin
//          if (flag_cpumode==MODE_SVC) begin
						mem_address <= ssp - 4;
	          ssp <= ssp - 4;
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          case (immediate_count)
            0: mem_write[31:0] <= regs[31][31:0];
            4: mem_write[31:0] <= flags[31:0];

								// SALVARE WP?!

          endcase

          immediate_count <= immediate_count + 4'd4;
          state <= STATE_IRQ_1;
        end
		  
      STATE_IRQ_1:
        begin
          mem_write_enable <= 0;
          mem_bus_enable <= 0;

          if (immediate_count == size_imm) begin
            state <= STATE_FETCH_OP_0;
				
						// SALVARE WP?!
            wp <= 32'h00000304 | (IRQlevel << 3);

						case (irq_or_trap) 
							1: begin		// Eccezioni
								flags[FLAG_CPUMODE+1:FLAG_CPUMODE] <= MODE_SVC;
								flags[FLAG_TRAP] <= 0;
//								flags[31:FLAG_IRQMASK] <= TRAP_IRQ_LEVEL; boh qua
								ea_indirectD <= 32'h00000010 | (excep_code << 3);
								end
							2: begin		// TRAP
//								regs[31] <= 32'h00000100 | (Imm8[5:0] << 3);
								flags[FLAG_CPUMODE+1:FLAG_CPUMODE] <= MODE_SVC;
								flags[FLAG_TRAP] <= 1;
								flags[31:FLAG_IRQMASK] <= TRAP_IRQ_LEVEL;
								if (!Imm8[7])
									ea_indirectD <= 32'h00000100 | (Imm8[5:0] << 3);
								else
									ea_indirectD <= 32'h00000040;
								end
							3: begin		// XOP
								flags[FLAG_CPUMODE+1:FLAG_CPUMODE] <= MODE_SVC;
								flags[FLAG_TRAP] <= 0;
								flags[31:FLAG_IRQMASK] <= XOP_IRQ_LEVEL;
								ea_indirectD <= temp;
								end
							0: begin		// IRQ
								flags[FLAG_CPUMODE+1:FLAG_CPUMODE] <= MODE_IRQ;
								flags[FLAG_TRAP] <= 0;	// s�? 
								flags[31:FLAG_IRQMASK] <= IRQlevel;
								ea_indirectD <= 32'h00000300 | (IRQlevel << 3);
								end
						endcase
						instruction <= 32'h80880000;		// JMP, INDEXED, Rd=0
						size_imm <= 4'd4;
						state <= STATE_EXECUTE_1_0 /*STATE_DECODE*/;
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
			4'hc: condIsOk = !flag_z && (flag_s == flag_ov);			// BGT
			4'hd: condIsOk = (flag_z || (flag_s != flag_ov));			// BLE
			4'he: condIsOk = flag_p;			// BPE
			4'hf: condIsOk = !flag_p;			// BPO
	endcase
endfunction

function [31:0] do_shift;
    input [31:0] data;
    input [2:0]  mode;      // Mm
    input [1:0]  size;
    input [4:0]  amount;
    
    reg [31:0] tmp;
    begin
        tmp = data;
        case (mode)
					0: ;
        endcase
        do_shift = tmp;
    end
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
	
memory_bus memory_bus_0(
  .address        (mem_address),
//	.size						(size_m),		// se lo metto triplica le celle!
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

	 
endmodule


