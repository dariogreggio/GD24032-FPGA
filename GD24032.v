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
reg [5:0]  state = 0;
reg [5:0]  next_state = 0;
reg [5:0]  wb_state = 0;
reg [24:0]  clock_div;		// ridurre poi!
reg [14:0] delay_loop;
wire clk;

reg [4:0] IRQlevel;

// Lower this (down to one) to increase speed.
assign clk = clock_div[0];
	// grok dice che usare più clock è sbagliato e dannoso in FPGA... ma usare uno stato precedente per confrontare costa un po' di celle!
	// v. 74c926 stranamente, usare il bit 15 usa 1-2 celle più che il bit 13 o 14...

// Registers and stack.
reg [31:0] regs[31:0];
reg [31:0] ssp,usp;
reg [31:0] wp;

wire [2:0] size_m;
reg [2:0] size_imm;
//reg [2:0] size_wb;


// Program counter, instruction, effective address.
reg [31:0] instruction;
reg [31:0] pc = 0;
reg [31:0] ea = 0;
reg [31:0] ea_indirect;

wire [7:0] Imm8;
wire [2:0] Mm;
wire [4:0] Rs;
wire [3:0] Ts;
wire [3:0] Cond;
wire [4:0] Rd;
wire [3:0] Td;
wire [1:0] Sz;
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
assign Sz = instruction[23:22];
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
reg affects_s;

// Used for MOVS ecc
reg [31:0] block_source;
reg [31:0] block_destination;

// Addressing mode.
wire [3:0] addressing_mode;
wire [2:0] extra_bytes;
reg  [1:0] indirect_count;
reg  [1:0] indirect_total;
reg  [2:0] absolute_count;
reg  [2:0] immediate_count;
reg  [2:0] push_count;
reg  [2:0] pop_count;		// non � mai usato insieme a push, ma se li unifico spreco pi� celle...
reg  [1:0] wb_count;		// usare per write a 64bit

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

parameter STATE_RESET             = 0;
parameter STATE_DELAY_LOOP        = 1;
parameter STATE_FETCH_OP_0        = 2;
parameter STATE_FETCH_OP_1        = 3;
parameter STATE_DECODE            = 4;

parameter STATE_FETCH_INDIRECT_0  = 5;
parameter STATE_FETCH_INDIRECT_1  = 6;
parameter STATE_FETCH_INDIRECT_2  = 7;
parameter STATE_FETCH_INDIRECT_3  = 8;
parameter STATE_FETCH_INDIRECT_Y  = 9;
parameter STATE_FETCH_ABSOLUTE_0  = 10;
parameter STATE_FETCH_ABSOLUTE_1  = 11;
parameter STATE_FETCH_DIRECT_PAGE = 12;
parameter STATE_FETCH_STACK_INDEXED = 13;
parameter STATE_FETCH_INDEXED     = 14;
parameter STATE_FETCH_IMMEDIATE_0 = 15;
parameter STATE_FETCH_IMMEDIATE_1 = 16;

parameter STATE_EXECUTE_00_0      = 17;
parameter STATE_EXECUTE_00_1      = 18;

parameter STATE_EXECUTE_01_0      = 19;
parameter STATE_EXECUTE_01_1      = 20;

parameter STATE_EXECUTE_10_0      = 21;
parameter STATE_EXECUTE_10_1      = 22;

parameter STATE_WRITEBACK_R       = 23;

parameter STATE_WRITEBACK_MEM_P   = 26;
parameter STATE_WRITEBACK_MEM_0   = 27;
parameter STATE_WRITEBACK_MEM_1   = 28;

parameter STATE_BRANCH_0          = 29;
parameter STATE_BRANCH_1          = 30;

parameter STATE_SET_FLAGS_0       = 31;
parameter STATE_SET_FLAGS_1       = 32;

parameter STATE_PUSH_0            = 33;
parameter STATE_PUSH_1            = 34;
parameter STATE_PUSH_2            = 35;

parameter STATE_POP_0             = 36;
parameter STATE_POP_1             = 37;
parameter STATE_POP_WB            = 38;

parameter STATE_RTI_0             = 43;
parameter STATE_RTI_1             = 44;

parameter STATE_TEST_BITS         = 52;

parameter STATE_JMP_ABS_0         = 53;
parameter STATE_JMP_ABS_1         = 54;
parameter STATE_JMP_ABS_2         = 55;
parameter STATE_JMP_ABS_3         = 56;

parameter STATE_ERROR             = 60;
parameter STATE_HALTED            = 61;
parameter STATE_IRQ_0	          = 62;
parameter STATE_IRQ_1	          = 63;

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
parameter OP_LDWP   = 7'h72;
parameter OP_STST   = 7'h73;
parameter OP_STWP   = 7'h74;
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
  clock_div <= clock_div + 1;
end

// Debug: This block simply drives the LEDs.
always @(posedge raw_clk) begin
	if (state==STATE_ERROR)
		leds_value <= 31; 
	else if (state==STATE_HALTED)
		leds_value <= 15; 
	else
		leds_value <= ~regs[0][7:0];

end


// This block is the main CPU instruction execute state machine.
always @(posedge clk) begin

  tsc <= tsc + 1;
	
  if(!button_reset)
    state = STATE_RESET;
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

//				pc <= { rom_0[16'hfffd],rom_0[16'hfffc]};
/*          mem_bus_enable <= 1;
            mem_address = 16'hfffc;
            pc[7:0]    <= mem_read;
            mem_address = mem_address+1;
            pc[15:8]   <= mem_read;
				// non va...
				
            pc <= 16'hf000;
            mem_address = pc;
				reg_a=mem_read;
          mem_bus_enable <= 0;

            state <= STATE_FETCH_OP_0;
	*/			
				
						mem_bus_enable <= 0;
            pc <= 32'h00000004;
            mem_address <= 32'h00000004;
						flags <= 32'h00000000;		// leggere da ram!
						if (MODE_SVC >= 0)
							ssp <= 32'h0000000c;		// leggere da ram!
						else
							usp <= 32'h0000000c;		// leggere da ram!
 //           mem_address <= 32'h0000000c;
						wp <= 32'h00000008;		// leggere da ram!

						instruction <= 32'h40000000;		// JMP
						state <= STATE_DECODE;
				
          end

          delay_loop <= delay_loop - 1;
        end
		  
      STATE_FETCH_OP_0:
        begin
          source <= 0;
          indirect_count <= 0;
          indirect_total <= 1;
          absolute_count <= 0;
          immediate_count <= 0;
          push_count <= 0;
          pop_count <= 0;
          wb_count <= 0;
          ea <= 0;
          ea_indirect <= 0;
          size_imm <= SIZE_8;
          is_sub <= 0;
          affects_ov <= 0;
          affects_c <= 0;
          affects_s <= 1;
          wb <= 1;
          wb_state <= STATE_WRITEBACK_R;
          branch_offset <= 0;
          mem_address <= pc;
          mem_bus_enable <= 1;
			 
				 if(!button_irq) begin
					size_imm <= 3;
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
          instruction <= mem_read;
					if(Opcode>=7'h70 && flag_cpumode<MODE_SVC) begin
						// eccezione!
					end
					if(Opcode == OP_CLR || Opcode == OP_SET || Opcode == OP_SE || Opcode == OP_DAA
						|| Opcode == OP_SWAP || Opcode == OP_EX || Opcode == OP_INC
						|| Opcode == OP_DEC || Opcode == OP_NEG || Opcode == OP_NOT || Opcode == OP_ABS
						|| Opcode == OP_ROT || Opcode == OP_CALL || Opcode == OP_BLWP
						|| Opcode == OP_RET || Opcode == OP_SKIP || Opcode == OP_TRAP 
						|| Opcode == OP_RTWP || Opcode == OP_HALT) begin
						if (IsCond) begin
							if (condIsOk(Cond) == 0) begin
								state <= STATE_FETCH_OP_0;
							// finire di skippare operandi...
							end else begin
								state <= STATE_DECODE;
							end
						end else begin
							state <= STATE_DECODE;
						end
					end else begin
						state <= STATE_DECODE;
					end
          pc <= pc + 4;
        end
		  
      STATE_DECODE:
        begin
          case (Opcode)
						OP_NOP:
							begin
							end
						OP_MOV:
							begin
							end

					endcase
			 
				if(!button_halt)
				 state <= STATE_HALTED;
			 
        end
		  
      STATE_FETCH_INDIRECT_0:
        begin
          mem_address <= pc;
          mem_bus_enable <= 4;
          pc <= pc + 4;
          state <= STATE_FETCH_INDIRECT_1;
        end
		  
      STATE_FETCH_INDIRECT_1:
        begin
          mem_bus_enable <= 0;

          if (addressing_mode == MODE_INDEXED)
              ea_indirect <= mem_read + regs[Rs];
            ea_indirect[31:0] <= mem_read[31:0];

          state <= STATE_FETCH_INDIRECT_2;
        end
		  
      STATE_FETCH_INDIRECT_2:
        begin

          // FIXME: Is this correct?
          mem_address <= ea_indirect;
          ea_indirect <= ea_indirect + 1;
          mem_bus_enable <= 1;
          state <= STATE_FETCH_INDIRECT_3;
        end
		  
      STATE_FETCH_INDIRECT_3:
        begin
          mem_bus_enable <= 0;
          indirect_count <= indirect_count + 1;

          case (indirect_count)
            0: ea[31:0] <= mem_read[31:0];
            1: ; // ea[63:32] <= mem_read[31:0];
          endcase

          if (indirect_count == indirect_total) begin
            if (addressing_mode == MODE_INDIRECT)
              state <= STATE_FETCH_IMMEDIATE_0;
            else
              state <= STATE_FETCH_INDIRECT_Y;
          end else begin
            state <= STATE_FETCH_INDIRECT_2;
          end
        end
		  
      STATE_FETCH_INDIRECT_Y:
        begin
          ea <= ea + regs[Rd];
          state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_FETCH_ABSOLUTE_0:
        begin
 
          mem_address <= pc;
          mem_bus_enable <= 1;
          pc <= pc + 1;
          absolute_count <= absolute_count + 1;

          state <= STATE_FETCH_ABSOLUTE_1;
        end
		  
      STATE_FETCH_ABSOLUTE_1:
        begin
          mem_bus_enable <= 0;

          case (absolute_count)
            1: ea[31:0] <= mem_read[31:0];
            2: ; // ea[63:32] <= mem_read[31:0];
          endcase

          if (absolute_count == extra_bytes)
            if (addressing_mode == MODE_IMMEDIATE) begin
              state <= STATE_FETCH_DIRECT_PAGE;
            end else if (addressing_mode == MODE_INDIRECT) begin
              state <= STATE_FETCH_IMMEDIATE_0;
            end else if (addressing_mode == MODE_INDEXED_SHORT) begin
              state <= STATE_FETCH_STACK_INDEXED;
            end else begin
              offset <= regs[Rs];
              state <= STATE_FETCH_INDEXED;
            end
          else
            state <= STATE_FETCH_ABSOLUTE_0;
        end
		  
      STATE_FETCH_DIRECT_PAGE:
        begin
          state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_FETCH_STACK_INDEXED:
        begin
					if(flag_cpumode<MODE_SVC)
						ea <= ea + ssp;
					else
						ea <= ea + usp;
          state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_FETCH_INDEXED:
        begin
            ea <= ea + offset[31:0];
//            SIZE_16: 
          state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_FETCH_IMMEDIATE_0:
        begin
          mem_address <= ea + immediate_count;
          mem_bus_enable <= 1;
          immediate_count <= immediate_count + 1;
          state <= STATE_FETCH_IMMEDIATE_1;
        end
		  
      STATE_FETCH_IMMEDIATE_1:
        begin
          mem_bus_enable <= 0;

          case (size_m)
            1: source[7:0]   <= mem_read[7:0];
            2: source[15:0]  <= mem_read[15:0];
            3: source[31:0]  <= mem_read[31:0];
          endcase

          if (immediate_count == size_imm)
            state <= next_state;
          else
            state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_EXECUTE_00_0:
        begin
        end
		  
      STATE_EXECUTE_00_1:
        begin
        end
		  
      STATE_EXECUTE_01_0:
        begin

          case (size_m)
            SIZE_8:  temp <= { 24'b0, regs[0][7:0]  };
            SIZE_16: temp <= { 16'b0, regs[0][15:0] };
            SIZE_32: temp <= {        regs[0][31:0] };
          endcase
					
          state <= STATE_EXECUTE_01_1;
        end
		  
      STATE_EXECUTE_01_1:
        begin
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
          endcase

        end
		  
      STATE_EXECUTE_10_0:
        begin

            case (size_m)
              SIZE_8:  temp <= { 24'b0, regs[0][7:0]  };
              SIZE_16: temp <= { 16'b0, regs[0][15:0] };
              SIZE_32: temp <= {        regs[0][31:0] };
            endcase
          state <= STATE_EXECUTE_10_1;
        end
		  
      STATE_EXECUTE_10_1:
        begin

          case (Opcode)
            OP_ROT:
						case (Mm)
							0: begin			// SLA
								case (size_m)
									SIZE_8:  result[8:0]  <= { source[7],  source[6:0],  1'b0 };
									SIZE_16: result[16:0] <= { source[15], source[14:0], 1'b0 };
									SIZE_32: result[32:0] <= { source[31], source[30:0], 1'b0 };
								endcase
								affects_c <= 1;
								end
							1: begin			// SRA
								case (size_m)
									SIZE_8:  result[8:0]  <= { source[0], source[7], source[7:1]  };
									SIZE_16: result[16:0] <= { source[0], source[15], source[15:1] };
									SIZE_32: result[32:0] <= { source[0], source[31], source[31:1] };
								endcase
								affects_c <= 1;
								end
							2: begin			// SRL
								case (size_m)
									SIZE_8:  result[8:0]  <= { source[0], 1'b0, source[7:1]  };
									SIZE_16: result[16:0] <= { source[0], 1'b0, source[15:1] };
									SIZE_32: result[32:0] <= { source[0], 1'b0, source[31:1] };
								endcase
								affects_c <= 1;
								end
							3: begin			// RR
								case (size_m)
									SIZE_8:  result[8:0]  <= { source[0], source[0], source[7:1]  };
									SIZE_16: result[16:0] <= { source[0], source[0], source[15:1] };
									SIZE_32: result[32:0] <= { source[0], source[0], source[31:1] };
								endcase
								affects_c <= 1;
								end
							4: begin			// RRC
								case (size_m)
									SIZE_8:  result[8:0]  <= { source[0], flag_c, source[7:1]  };
									SIZE_16: result[16:0] <= { source[0], flag_c, source[15:1] };
									SIZE_32: result[32:0] <= { source[0], flag_c, source[31:1] };
								endcase
								affects_c <= 1;
								end
							5: begin			// RL
								case (size_m)
									SIZE_8:  result[8:0]  <= { source[7],  source[6:0],  source[7] };
									SIZE_16: result[16:0] <= { source[15], source[14:0], source[15] };
									SIZE_32: result[32:0] <= { source[31], source[30:0], source[31] };
								endcase
								affects_c <= 1;
								end
							6: begin			// RLC
								case (size_m)
									SIZE_8:  result[8:0]  <= { source[7],  source[6:0],  flag_c };
									SIZE_16: result[16:0] <= { source[15], source[14:0], flag_c };
									SIZE_32: result[32:0] <= { source[31], source[30:0], flag_c };
								endcase
								affects_c <= 1;
								end
							endcase
            OP_DEC: 
							result <= source - 1;
            OP_INC: 
							result <= source + 1;
          endcase


          begin
            state <= addressing_mode == MODE_REGISTER ?
              STATE_WRITEBACK_R : STATE_WRITEBACK_MEM_P;
          end
        end
		  
      STATE_WRITEBACK_R:
        begin
					case (size_m)
						SIZE_8:  regs[Rd][7:0] <= result[7:0];
						SIZE_16: regs[Rd][15:0] <= result[15:0];
						SIZE_32: regs[Rd][31:0] <= result[31:0];
					endcase
					if(DoFlags) begin
						case (size_m)
							SIZE_8:
								begin
									if (affects_c) flags[FLAG_C] <= result[8];
									flags[FLAG_Z] <= result[7:0] == 0;
									flags[FLAG_S] <= result[7];
									if (affects_ov) flags[FLAG_OV] <= temp[7] == (source[7] ^ is_sub) && result[7] != temp[7];
								end
							SIZE_16:
								begin
									if (affects_c) flags[FLAG_C] <= result[16];
									flags[FLAG_Z] <= result[15:0] == 0;
									flags[FLAG_S] <= result[15];
									if (affects_ov) flags[FLAG_OV] <= temp[15] == (source[15] ^ is_sub) && result[15] != temp[15];
								end
							SIZE_32:
								begin
									if (affects_c) flags[FLAG_C] <= result[32];
									flags[FLAG_Z] <= result[31:0] == 0;
									flags[FLAG_S] <= result[31];
									if (affects_ov) flags[FLAG_OV] <= temp[31] == (source[31] ^ is_sub) && result[31] != temp[31];
								end
							SIZE_64:
								begin
								end
						endcase
					end
          state <= STATE_FETCH_OP_0;
        end
		  
	  
      STATE_WRITEBACK_MEM_P:
        begin

					if(DoFlags) begin
						case (size_m)
							SIZE_8:
								begin
									if (affects_c) flags[FLAG_C] <= result[8];
									flags[FLAG_Z] <= result[7:0] == 0;
									flags[FLAG_S] <= result[7];
									if (affects_ov) flags[FLAG_OV] <= temp[7] == (source[7] ^ is_sub) && result[7] != temp[7];
								end
							SIZE_16:
								begin
									if (affects_c) flags[FLAG_C] <= result[16];
									flags[FLAG_Z] <= result[15:0] == 0;
									flags[FLAG_S] <= result[15];
									if (affects_ov) flags[FLAG_OV] <= temp[15] == (source[15] ^ is_sub) && result[15] != temp[15];
								end
							SIZE_32:
								begin
									if (affects_c) flags[FLAG_C] <= result[32];
									flags[FLAG_Z] <= result[31:0] == 0;
									flags[FLAG_S] <= result[31];
									if (affects_ov) flags[FLAG_OV] <= temp[31] == (source[31] ^ is_sub) && result[31] != temp[31];
								end
							SIZE_64:
								begin
								end
						endcase
					end
					
					case (size_m)
						SIZE_8:
							wb_count=1;
						SIZE_16:
							wb_count=1;
						SIZE_32:
							wb_count=1;
						SIZE_64:
							wb_count=2;
					endcase
						
          state <= STATE_WRITEBACK_MEM_0;
        end
		  
      STATE_WRITEBACK_MEM_0:
        begin
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          mem_address <= ea + wb_count;

          mem_write[31:0] <= result[31:0];

          wb_count <= wb_count + 1;

          state <= STATE_WRITEBACK_MEM_1;
        end
		  
      STATE_WRITEBACK_MEM_1:
        begin
          mem_bus_enable <= 0;
          mem_write_enable <= 0;

          if (wb_count == size_imm)
            state <= STATE_FETCH_OP_0;
          else
            state <= STATE_WRITEBACK_MEM_0;
        end
		  
      STATE_BRANCH_0:
        begin

          pc <= pc + 4;
          mem_address <= pc;
          mem_bus_enable <= 1;
          state <= STATE_BRANCH_1;
        end
		  
      STATE_BRANCH_1:
        begin
          mem_bus_enable <= 0;
          immediate_count <= immediate_count + 1;

          if (condIsOk(Cond)) 
						pc[31:0] <= $signed(pc[31:0]) + $signed(mem_read);
          state <= STATE_FETCH_OP_0;
        end
		  
      STATE_SET_FLAGS_0:
        begin
          mem_address <= pc;
          mem_bus_enable <= 1;
          pc <= pc + 4;
          state <= STATE_SET_FLAGS_1;
        end
		  
      STATE_SET_FLAGS_1:
        begin
          mem_bus_enable <= 0;
					
					if (DoFlags) begin
					end

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
					if(flag_cpumode<MODE_SVC)
						mem_address <= ssp;
					else
						mem_address <= usp;

          case (push_count)
            1: mem_write[31:0] <= result[31:0];
						2: ;
          endcase

          push_count <= push_count - 1;
					if(flag_cpumode<MODE_SVC)
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
					if(flag_cpumode<MODE_SVC) begin
						ssp <= ssp + 4;
						mem_address <= ssp;
						end
					else begin
						usp <= usp + 4;
						mem_address <= usp;
						end
          mem_bus_enable <= 1;
          pop_count <= pop_count + 1;
          state <= STATE_POP_1;
        end
		  
      STATE_POP_1:
        begin
          mem_bus_enable <= 0;

          case (pop_count)
            1: source[31:0] <= mem_read[31:0];
            2: ;
          endcase

          if (pop_count == size_imm)
            state <= STATE_POP_WB;
          else
            state <= STATE_POP_0;
        end
		  
      STATE_POP_WB:
        begin

          state <= STATE_FETCH_OP_0;
        end
		  
      STATE_RTI_0:
        begin
					if(flag_cpumode<MODE_SVC) begin
						ssp <= ssp + 4;
						mem_address <= ssp;
						end
					else begin
						usp <= usp + 4;
						mem_address <= usp;
						end
          mem_bus_enable <= 1;
          immediate_count <= immediate_count + 1;
          state <= STATE_RTI_1;
        end
		  
      STATE_RTI_1:
        begin
          mem_bus_enable <= 0;

          case (immediate_count)
            1: flags[31:0] <= mem_read[31:0];
            2: pc[31:0]  <= mem_read[31:0];
          endcase

          if (immediate_count == size_imm)
            state <= STATE_FETCH_OP_0;
          else
            state <= STATE_RTI_0;
        end
		  
	  
      STATE_TEST_BITS:
        begin
			 flags[FLAG_Z] <= source[31:0]  & regs[Ts][31:0]  == 0;

			 
				result[31:0] <= source[31:0] & ~regs[Ts][31:0];
          state <= STATE_WRITEBACK_MEM_0;
        end
		  
      STATE_JMP_ABS_0:
        begin
          mem_address <= pc;
          mem_bus_enable <= 1;
          pc <= pc + 4;
          state <= STATE_JMP_ABS_1;
        end
		  
      STATE_JMP_ABS_1:
        begin
          if (indirect_count == 0) begin
            ea_indirect[31:0] <= mem_read[31:0];
            state <= STATE_JMP_ABS_0;
          end else begin

              ea_indirect[31:0] <= mem_read[31:0];
              state <= STATE_JMP_ABS_2;
          end

          indirect_count <= indirect_count + 1;
          mem_bus_enable <= 0;
        end
		  
      STATE_JMP_ABS_2:
        begin
          mem_address <= ea_indirect;
          mem_bus_enable <= 1;
          ea_indirect <= ea_indirect + 1;
          state <= STATE_JMP_ABS_3;
        end
		  
      STATE_JMP_ABS_3:
        begin
          if (immediate_count == 0) begin
            source[31:0] <= mem_read[31:0];
            state <= STATE_JMP_ABS_2;
          end else begin
            pc <= { mem_read, source[7:0] };

            if (Opcode != 7'h40) begin
              // JSR.
              size_imm <= 2;
              result <= pc[31:0];
              state <= STATE_PUSH_0;
            end else begin
              state <= STATE_FETCH_OP_0;
            end
          end

          immediate_count <= immediate_count + 1;
          mem_bus_enable <= 0;
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
          mem_address <= regs[31];
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          immediate_count <= immediate_count + 1;
          case (immediate_count)
            1: mem_write[31:0] <= pc[31:0];
            3: mem_write[31:0] <= flags[31:0];
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
//				pc <= 16'hff50;
				
            pc <= IRQlevel << 3;
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

	

always @(posedge raw_clk) begin
  case (mux_state)
		0: seg_data = seven_seg(digit0);
		1: seg_data = seven_seg(digit1);
		2: seg_data = seven_seg(digit2);
		3: seg_data = seven_seg(digit3);
  endcase


// Multiplexing + refresh
  refresh_counter <= refresh_counter + 1;

  if (refresh_counter == 16'd49999) begin   // ~250 Hz (Grok delirava :D : con 24999 200Hz per digit ? refresh totale ~800Hz
		refresh_counter <= 0;
		digit3 <= pc[15:12];
		digit2 <= pc[11:8];
		digit1 <= pc[7:4];
		digit0 <= pc[3:0];
		mux_state <= mux_state + 1;
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

addressing_mode addressing_mode_0(
  .Mm          (Mm),
  .Rs          (Rs),
  .Ts          (Ts),
  .Rd          (Rd),
  .Td          (Td),
  .Sz          (Sz),
  .mode        (addressing_mode),
  .extra_words (extra_words)
);

reg_mode reg_mode_0(
  .x      (flag_b)
);

endmodule


