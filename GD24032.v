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

// Memory bus (ROM, RAM, peripherals).
reg [31:0] mem_address = 0;
reg [31:0]  mem_write = 0;
wire [31:0] mem_read;
reg mem_write_enable = 0;
reg mem_bus_enable = 0;
reg mem_bus_reset = 1;
wire mem_bus_halted;

// FIXME: Can remove this later.
//reg was_ever_halted = 0;

// Clock.
reg [21:0] count = 0;
reg [5:0]  state = 0;
reg [5:0]  next_state = 0;
reg [5:0]  wb_state = 0;
reg [24:0]  clock_div;		// ridurre poi!
reg [14:0] delay_loop;
wire clk;

// Lower this (down to one) to increase speed.
assign clk = clock_div[21];
	// grok dice che usare più clock è sbagliato e dannoso in FPGA... ma usare uno stato precedente per confrontare costa un po' di celle!
	// v. 74c926 stranamente, usare il bit 15 usa 1-2 celle più che il bit 13 o 14...

// Registers and stack.
reg [31:0] [31:0] regs;

reg [2:0] size_imm;
//reg [2:0] size_wb;


// Program counter, instruction, effective address.
reg [31:0]  instruction;
reg [31:0] pc = 0;
reg [31:0] ea = 0;
reg [31:0] ea_indirect;

wire [2:0] Mm;
wire [4:0] Rs;
wire [3:0] Ts;
wire [4:0] Rd;
wire [3:0] Td;
wire [1:0] Sz;
wire Ff;
wire [6:0] Opcode;
assign Mm  = instruction[2:0];
assign Rs = instruction[7:3];
assign Ts = instruction[11:8];
assign Rd = instruction[16:12];
assign Td = instruction[20:17];
assign Sz = instruction[23:22];
assign Ff = instruction[24];
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
reg affects_v;
reg affects_n;

// Used for MVP, MVN.
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
reg  [2:0] wb_count;

// Branches.
reg do_branch;
reg [31:0] branch_offset;

// Flags.
parameter FLAG_N   = 7;
parameter FLAG_V   = 6;
parameter FLAG_B   = 4;
parameter FLAG_D   = 3;
parameter FLAG_I   = 2;
parameter FLAG_Z   = 1;
parameter FLAG_C   = 0;

reg [31:0] flags;

wire flag_n;
wire flag_v;
wire flag_b;
wire flag_d;
wire flag_i;
wire flag_z;
wire flag_c;

assign flag_n   = flags[FLAG_N];
assign flag_v   = flags[FLAG_V];
assign flag_b   = flags[FLAG_B];
assign flag_d   = flags[FLAG_D];
assign flag_i   = flags[FLAG_I];
assign flag_z   = flags[FLAG_Z];
assign flag_c   = flags[FLAG_C];

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

parameter STATE_WRITEBACK_A       = 23;
parameter STATE_WRITEBACK_X       = 24;
parameter STATE_WRITEBACK_Y       = 25;

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

//parameter STATE_STZ               = 45;

parameter STATE_TEST_BITS         = 52;

parameter STATE_JMP_ABS_0         = 53;
parameter STATE_JMP_ABS_1         = 54;
parameter STATE_JMP_ABS_2         = 55;
parameter STATE_JMP_ABS_3         = 56;

parameter STATE_ERROR             = 62;
parameter STATE_HALTED            = 63;
parameter STATE_IRQ_0	          = 64;
parameter STATE_IRQ_1	          = 65;

// Instruction format: aaabbbcc

// c = 00 aaa = op, bbb = mode
parameter OP_BIT     = 3'b001;
parameter OP_JMP     = 3'b010; // jmp ADDRESS
parameter OP_JMP_IND = 3'b011; // jmp (ADDRESS)
parameter OP_STY     = 3'b100;
parameter OP_LDY     = 3'b101;
parameter OP_CPY     = 3'b110;
parameter OP_CPX     = 3'b111;

parameter OP_BPL     = 3'b000;
parameter OP_BMI     = 3'b001;
parameter OP_BVC     = 3'b010;
parameter OP_BVS     = 3'b011;
parameter OP_BCC     = 3'b100;
parameter OP_BCS     = 3'b101;
parameter OP_BNE     = 3'b110;
parameter OP_BEQ     = 3'b111;

// cc = 00, bbb = 000.
parameter OP_BRK = 3'b000; // _000_00;
parameter OP_JSR = 3'b001; // _000_00;
parameter OP_RTI = 3'b010; // _000_00;
parameter OP_RTS = 3'b011; // _000_00;
//parameter OP_BRA = 3'b100; // _000_00;

// cc = 00, b = 001.
//parameter OP_MVP = 3'b010; // _001_00;

// cc = 00, bbb = 010.
parameter OP_PHP = 3'b000; // _010_00;
parameter OP_PLP = 3'b001; // _010_00;
parameter OP_PHA = 3'b010; // _010_00;
parameter OP_PLA = 3'b011; // _010_00;
parameter OP_DEY = 3'b100; // _010_00;
parameter OP_TAY = 3'b101; // _010_00;
parameter OP_INY = 3'b110; // _010_00;
parameter OP_INX = 3'b111; // _010_00;

// cc = 00, b = 101.
//parameter OP_STZ = 3'b011; // _101_00;

// cc = 00, b = 110.
parameter OP_CLC = 3'b000; // _110_00;
parameter OP_SEC = 3'b001; // _110_00;
parameter OP_CLI = 3'b010; // _110_00;
parameter OP_SEI = 3'b011; // _110_00;
parameter OP_TYA = 3'b100; // _110_00;
parameter OP_CLV = 3'b101; // _110_00;
parameter OP_CLD = 3'b110; // _110_00;
parameter OP_SED = 3'b111; // _110_00;

// cc = 00, b = 011.
parameter OP_JMP_ABS   = 3'b011; // _111_00;

// cc = 00, b = 111.

// cc = 01 aaa = op, bbb = mode
parameter OP_ORA = 3'b000;
parameter OP_AND = 3'b001;
parameter OP_EOR = 3'b010;
parameter OP_ADC = 3'b011;
parameter OP_STA = 3'b100;
parameter OP_LDA = 3'b101;
parameter OP_CMP = 3'b110;
parameter OP_SBC = 3'b111;

parameter OP_BIT_IMM = 3'b100; // _010_01


// cc = 10 aaa = op, bbb = mode
parameter OP_ASL = 3'b000;
parameter OP_ROL = 3'b001;
parameter OP_LSR = 3'b010;
parameter OP_ROR = 3'b011;
parameter OP_STX = 3'b100;
parameter OP_LDX = 3'b101;
parameter OP_DEC = 3'b110;
parameter OP_INC = 3'b111;

// cc = 10, b = 010.
parameter OP_TXA = 3'b100; // _010_10;
parameter OP_TAX = 3'b101; // _010_10;
parameter OP_DEX = 3'b110; // _010_10;
parameter OP_NOP = 3'b111; // _010_10;

// cc = 10, b = 110.
parameter OP_TXS = 3'b100; // _110_10;
parameter OP_TSX = 3'b101; // _110_10;

// cc = 10, b = 111.
//parameter OP_STZ_2 = 3'b100; // _111_10;

    // ================== Multiplexing 7-Segmenti ==================
    reg [1:0]  mux_state = 0;
    reg [15:0] refresh_counter = 0;   // ~200-300 Hz refresh totale

    // Decodificatore BCD -> 7 segmenti (common cathode)
    reg [6:0] seg_data;

	 
// This block is simply a clock divider for the raw_clk.
always @(posedge raw_clk) begin
  count <= count + 1;
  clock_div <= clock_div + 1;
end

// Debug: This block simply drives the LEDs.
always @(posedge raw_clk) begin
	if (state==STATE_ERROR)
	leds_value <= 31; 
	else if (state==STATE_HALTED)
	leds_value <= 15; 
	else
	leds_value <= ~sp /* ~reg_x[7:0]*/;

end


// This block is the main CPU instruction execute state machine.
always @(posedge clk) begin

  if(!button_reset)
    state = STATE_RESET;
  else 
    case (state)
      STATE_RESET:
        begin
          flags[FLAG_V] <= 0;
          flags[FLAG_B] <= 1;
          flags[FLAG_D] <= 0;
          flags[FLAG_I] <= 0;
          flags[FLAG_C] <= 0;
          flags[FLAG_Z] <= 0;
          mem_address <= 0;
          mem_write_enable <= 0;
          mem_bus_enable <= 0;
          mem_bus_reset <= 1;
          delay_loop <= 30;			// cfr. freq raw_clk e div.
          regs[0] <= 0;
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
            pc <= 16'hfffc;
            mem_address <= 16'hfffc;
//				ea <= 16'hfffc;

			 instruction <= 8'h4c;		// non 6c... strano
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
          affects_v <= 0;
          affects_c <= 0;
          affects_n <= 1;
          wb <= 1;
          wb_state <= STATE_WRITEBACK_A;
          branch_offset <= 0;
          mem_address <= pc;
          mem_bus_enable <= 1;
			 
			 if(!button_irq && !flag_i) begin
				size_imm <= 3;
		          immediate_count <= 0;
				state <= STATE_IRQ_0;
				end
			 else
				state <= STATE_FETCH_OP_1;

			 if(!button_nmi) begin		// finire! test
				size_imm <= 3;
		          immediate_count <= 0;
				state <= STATE_IRQ_0;
				end
			 else
				state <= STATE_FETCH_OP_1;
        end
		  
      STATE_FETCH_OP_1:
        begin
          mem_bus_enable <= 0;
          instruction <= mem_read;
          state <= STATE_DECODE;
          pc <= pc + 1;
        end
		  
      STATE_DECODE:
        begin
          case (instruction[1:0])
            2'b00:
              /*if (aaa == OP_TSB && bbb[0] == 1) begin
                next_state <= STATE_TEST_BITS;
                state <= STATE_FETCH_ABSOLUTE_0;
              end else */if (bbb == 3'b000 && aaa != OP_LDY && aaa != OP_CPY && aaa != OP_CPX) begin
                case (aaa)
                  OP_BRK: 
							state <= STATE_HALTED;
                  OP_JSR:
                    begin
                      ea <= pc;
                      pc <= pc + 2;
                      size_imm <= SIZE_16;
                      state <= STATE_FETCH_IMMEDIATE_0;
                      next_state <= STATE_EXECUTE_00_0;
                    end
                  OP_RTI:
                    begin
                      size_imm <= 3;
                      state <= STATE_RTI_0;
                    end
                  OP_RTS: 
							begin 
								size_imm <= SIZE_16; 
								state <= STATE_POP_0;
							end
//                  OP_BRA: 
//							state <= STATE_BRANCH_0;
                endcase
              end else if (bbb == 3'b010) begin
                if (aaa[2] == 0) begin
                  // PHP, PLP, PHA, PLA.
                  result   <= aaa[1] == 1 ? reg_a  : flags[7:0];
                  size_imm <= /*aaa[1] == 1 ? size_m : */ SIZE_8;
                  state    <= aaa[0] == 0 ? STATE_PUSH_0 : STATE_POP_0;
                end else begin
                  case (aaa[1:0])
                    // DEY, TAY, INY, INX.
                    2'b00: result <= reg_y - 1;
                    2'b01: result <= reg_a;
                    2'b10: result <= reg_y + 1;
                    2'b11: result <= reg_x + 1;
                  endcase
                  state <= aaa[1:0] == 2'b11 ?
                    STATE_WRITEBACK_X : STATE_WRITEBACK_Y;
                end
              end else if (bbb == 3'b100) begin
                state <= STATE_BRANCH_0;
              end /*else if (bbb == 3'b001 && aaa == OP_STZ) begin
                // stz ZP
                size_imm <= SIZE_8;
                next_state <= STATE_STZ;
                state <= STATE_FETCH_ABSOLUTE_0;
              end else if (bbb == 3'b001 && aaa == OP_MVP) begin
                state <= STATE_MOVE_BLOCK_0;
              end*/ else if (bbb == 3'b011 && aaa == OP_JMP_ABS) begin
                state <= STATE_JMP_ABS_0;
              end else if (bbb == 3'b101) begin
/*                case (aaa)
                  OP_STZ:
                    begin
                      // stz ZP, x
                      size_imm <= SIZE_8;
                      next_state <= STATE_STZ;
                      state <= STATE_FETCH_ABSOLUTE_0;
                    end
                endcase*/
					 
					 // B4 40 	LDY $40,X  non c'era... 1/7/26
					 size_imm <= 1;
					 pc <= pc + 1;
                state <= STATE_FETCH_IMMEDIATE_0;

              end else if (bbb == 3'b110) begin
                // CLC, SEC, CLI, SEI, TYA, CLV, CLD, SED.
                case (aaa[2:1])
                  2'b00: 
							flags[FLAG_C] <= aaa[0];
                  2'b01: 
							flags[FLAG_I] <= aaa[0];
                  2'b10:
                    if (aaa[0] == 0)
                      result <= reg_y;
                    else
                      flags[FLAG_V] <= 0;
                  2'b11: 
							flags[FLAG_D] <= aaa[0];
                endcase

                state <= aaa == OP_TYA ? STATE_WRITEBACK_A : STATE_FETCH_OP_0;
              end else if (bbb == 3'b111) begin
                /*else if (aaa == OP_STZ_2) begin
                  // stz absolute;
                  size_imm <= SIZE_8;
                  next_state <= STATE_STZ;
                  state <= STATE_FETCH_ABSOLUTE_0;
                end*/
              end else begin
                if (aaa == OP_JMP && bbb == 3'b011) begin
                  ea <= pc;
                  pc <= pc + 2;
                  size_imm <= 2;
                  next_state <= STATE_EXECUTE_00_0;
                  state <= STATE_FETCH_IMMEDIATE_0;
                end else if (aaa == OP_JMP_IND && bbb == 3'b011) begin
                  size_imm <= 2;
                  next_state <= STATE_EXECUTE_00_0;
                  state <= STATE_FETCH_ABSOLUTE_0;
                end else begin
                  case (addressing_mode)
                    MODE_IMMEDIATE:
                      begin
                        ea <= pc;

                        if (aaa == OP_BIT) begin
                          pc <= pc + SIZE_8;		// VERIFICARE le 2 BIT
                        end else begin
                          pc <= pc + 1;
                          size_imm <= 1;
                        end

                        state <= STATE_FETCH_IMMEDIATE_0;
                      end
                    MODE_ABSOLUTE:   state <= STATE_FETCH_ABSOLUTE_0;
                    MODE_INDIRECT_X: state <= STATE_FETCH_INDIRECT_0;
                    MODE_INDIRECT_Y: state <= STATE_FETCH_INDIRECT_0;
                    MODE_ABSOLUTE_X: state <= STATE_FETCH_ABSOLUTE_0;
                    MODE_ABSOLUTE_Y: state <= STATE_FETCH_ABSOLUTE_0;
                    default:         state <= STATE_HALTED;
                  endcase

                  next_state <= STATE_EXECUTE_00_0;
                end
              end
				  
            2'b01:
              begin
                case (addressing_mode)
                  MODE_IMMEDIATE:
                    begin
                      ea <= pc;
                      pc <= pc + SIZE_8;
                      state <= STATE_FETCH_IMMEDIATE_0;
                    end
                  MODE_ABSOLUTE:   state <= STATE_FETCH_ABSOLUTE_0;
                  MODE_INDIRECT_X: state <= STATE_FETCH_INDIRECT_0;
                  MODE_INDIRECT_Y: state <= STATE_FETCH_INDIRECT_0;
                  MODE_ABSOLUTE_X: state <= STATE_FETCH_ABSOLUTE_0;
                  MODE_ABSOLUTE_Y: state <= STATE_FETCH_ABSOLUTE_0;
                  default:         state <= STATE_ERROR;
                endcase

                next_state <= STATE_EXECUTE_01_0;
              end
				  
            2'b10:
              begin
                if (bbb == 3'b000 && aaa != 3'b101 || instruction[7:2] == 6'b100_000) begin
                  // stx 100_000_10
                  // ldx 101_000_10
                  // stx 0x100  8e  100 011 10
                  // ldx #5     a2  101 000 10
                end else if (bbb == 3'b010 && aaa[2] == 1) begin
                  case (aaa)
                    OP_TXA: 
								begin 
									result <= reg_x; 
									state <= STATE_WRITEBACK_A; 
								end
                    OP_TAX: 
								begin 
									result <= reg_a; 
									state <= STATE_WRITEBACK_X; 
								end
                    OP_DEX: 
								begin result <= reg_x - 1; state <= STATE_WRITEBACK_X; end
                    OP_NOP: 
								state <= STATE_FETCH_OP_0;
                  endcase
                end else if (bbb == 3'b110) begin
                  case (aaa)
                    OP_TXS:
                      begin
                        sp <= reg_x;
                        state <= STATE_FETCH_OP_0;
                      end
                    OP_TSX: 
							begin 
								result <= sp; 
								state <= STATE_WRITEBACK_X; 
							end
                    default: 
							state <= STATE_ERROR;
                  endcase

                  if (aaa[1:0] == 2'b10)
                    result <= aaa[2] == 0 ? reg_y : reg_x;

                  size_imm <= 1;
                end else if (bbb == 3'b111) begin
                  /*if (aaa == OP_STZ_2) begin
                    // stz absolute, x
                    size_imm <= SIZE_8;
                    next_state <= STATE_STZ;
                    state <= STATE_FETCH_ABSOLUTE_0;
                  end else */begin
                    state <= STATE_ERROR;
                  end
                end else if (bbb == 3'b100) begin
                  // Indirect addressing mode (dp).
                  state <= STATE_FETCH_INDIRECT_0;
                  next_state <= STATE_EXECUTE_01_0;
                end else begin
                  case (addressing_mode)
                    MODE_IMMEDIATE:
                      begin
                        ea <= pc;

                        // Only LDX or STX should be able to end up in
                        // here.
                        //if (aaa == OP_LDX || aaa == OP_STX) begin
                          pc <= pc + 1;
                          size_imm <= 1;
                        //end else begin
                        //  pc <= pc + SIZE_8;
                        //end

                        state <= STATE_FETCH_IMMEDIATE_0;
                      end
                    MODE_ABSOLUTE:
							state <= STATE_FETCH_ABSOLUTE_0;
                    MODE_ABSOLUTE_X: 
							state <= STATE_FETCH_ABSOLUTE_0;
                    MODE_A:
                      begin
                        source <= reg_a;
                        state <= STATE_EXECUTE_10_0;
                      end
                    default:         state <= STATE_ERROR;
                  endcase

                  next_state <= STATE_EXECUTE_10_0;
                end
              end
            2'b11:
              case (bbb)
                3'b010:
                  begin
						// tolto cose...
							size_imm <= SIZE_16;						
                  end
                3'b110:
                  begin


                    state <= STATE_FETCH_OP_0;
                  end
                default:
                  begin
                    case (addressing_mode)
                      MODE_STACK_RELATIVE: state <= STATE_FETCH_ABSOLUTE_0;
                      MODE_ABSOLUTE:       state <= STATE_FETCH_ABSOLUTE_0;
//                      MODE_INDIRECT_S_Y:   state <= STATE_FETCH_INDIRECT_0;
                      MODE_ABSOLUTE_X:     state <= STATE_FETCH_ABSOLUTE_0;
                      default:             state <= STATE_ERROR;
                    endcase

                    //state <= STATE_ERROR;
                    next_state <= STATE_EXECUTE_01_0;
                  end
            endcase
          endcase
			 
	  if(!button_halt)
		 state <= STATE_HALTED;
			 
        end
		  
      STATE_FETCH_INDIRECT_0:
        begin
          mem_address <= pc;
          mem_bus_enable <= 1;
          pc <= pc + 1;
          state <= STATE_FETCH_INDIRECT_1;
        end
		  
      STATE_FETCH_INDIRECT_1:
        begin
          mem_bus_enable <= 0;

          if (addressing_mode == MODE_INDIRECT_X)
              ea_indirect <= mem_read + reg_x;
            ea_indirect[15:0] <= mem_read;

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
            0: ea[7:0]    <= mem_read;
            1: ea[15:8]   <= mem_read;
          endcase

          if (indirect_count == indirect_total) begin
            if (addressing_mode == MODE_INDIRECT_X || addressing_mode == MODE_INDIRECT)
              state <= STATE_FETCH_IMMEDIATE_0;
            else
              state <= STATE_FETCH_INDIRECT_Y;
          end else begin
            state <= STATE_FETCH_INDIRECT_2;
          end
        end
		  
      STATE_FETCH_INDIRECT_Y:
        begin
          ea <= ea + reg_y;
          state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_FETCH_ABSOLUTE_0:
        begin
          // MODE_ZP and MODE_ABSOLUTE are the same, the difference is
          // extra_bytes.
 
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
            1: ea[7:0]   <= mem_read;
            2: ea[15:8]  <= mem_read;
          endcase

          if (absolute_count == extra_bytes)
            if (addressing_mode == MODE_ZP && extra_bytes == 1) begin
              state <= STATE_FETCH_DIRECT_PAGE;
            end else if (addressing_mode == MODE_ABSOLUTE) begin
              state <= STATE_FETCH_IMMEDIATE_0;
            end else if (addressing_mode == MODE_STACK_RELATIVE) begin
              state <= STATE_FETCH_STACK_INDEXED;
            end else begin
              offset <= addressing_mode == MODE_ABSOLUTE_X ? reg_x : reg_y;
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
          ea <= ea + sp;
          state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_FETCH_INDEXED:
        begin
            ea <= ea + offset[7:0];
//            SIZE_16: ea <= ea + offset[15:0];// NON dovrebbe esserci
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

          case (immediate_count[1:0])
            1: source[7:0]   <= mem_read;
            2: source[15:8]  <= mem_read;// NON dovrebbe esserci
          endcase

          if (immediate_count == size_imm)
            state <= next_state;
          else
            state <= STATE_FETCH_IMMEDIATE_0;
        end
		  
      STATE_EXECUTE_00_0:
        begin
          if (aaa == OP_JMP || aaa == OP_JMP_IND || (aaa == OP_JSR && bbb == 3'b000)) begin
            pc[15:0] <= source;
          end else if (aaa == OP_BIT) begin
              temp <= reg_a;
            wb <= 0;
            affects_n <= 0;
            flags[FLAG_N] <= source[7];
            flags[FLAG_V] <= source[6];
          end else if (aaa == OP_CPY || aaa == OP_LDY || aaa == OP_STY) begin
            temp <= { 24'b0, reg_y[7:0]  };
            wb_state <= STATE_WRITEBACK_Y;
          end else if (aaa == OP_CPX) begin
            temp <= { 24'b0, reg_x[7:0]  };
            wb_state <= STATE_WRITEBACK_X;
          end

          if (aaa == OP_JMP || aaa == OP_JMP_IND) begin
            state <= STATE_FETCH_OP_0;
          end else if (aaa == OP_JSR && bbb == 3'b000) begin
            result <= pc[15:0];
            state <= STATE_PUSH_0;
          end else begin
            state <= STATE_EXECUTE_00_1;
          end
        end
		  
      STATE_EXECUTE_00_1:
        begin
          case (aaa)
            OP_BIT: 
					begin 
						result <= temp & source; 
						wb <= 0; 
					end
            //OP_JMP: result <= temp & source;
            //OP_JMP_IND: result <= temp ^ source;
            OP_STY: 
					result <= temp;
            OP_LDY: 
					result <= source;
            OP_CPY: 
					begin 
						result <= temp - source; 
						wb <= 0; 
						affects_c <= 1; 
					end
            OP_CPX: 
					begin 
						result <= temp - source; 
						wb <= 0; 
						affects_c <= 1; 
					end
          endcase

          if (aaa == OP_STY) begin
            size_imm <= 1;
            state <= STATE_WRITEBACK_MEM_0;
          end else begin
            state <= wb_state;
          end
        end
		  
      STATE_EXECUTE_01_0:
        begin
          temp <= reg_a;
          state <= STATE_EXECUTE_01_1;
        end
		  
      STATE_EXECUTE_01_1:
        begin
          case (aaa)
            OP_ORA: 
					result <= temp | source;
            OP_AND: 
					result <= temp & source;
            OP_EOR: 
					result <= temp ^ source;
            OP_ADC:
              begin
                result <= temp + source + flag_c;
                affects_c <= 1;
                affects_v <= 1;
              end
            OP_STA:
              if (bbb == 3'b010) begin
                // OP_BIT_IMM: bit #imm
                flags[FLAG_N] <= source[7];
                flags[FLAG_V] <= source[6];
                affects_n <= 0;
                wb <= 0;
                result <= temp & source;
              end else begin
                result <= temp;
              end
            OP_LDA: 
					result <= source;
            OP_CMP:
              begin
                result <= temp - source;
                wb <= 0;
                is_sub <= 1;
                affects_c <= 1;
              end
            OP_SBC:
              begin
                result <= temp - source - 1 + flag_c;
                is_sub <= 1;
                affects_c <= 1;
                affects_v <= 1;
              end
          endcase

          // wb_state should always be STATE_WRITEBACK_A.
          if (aaa == OP_STA && bbb != 3'b010)
            state <= STATE_WRITEBACK_MEM_0;
          else
            state <= wb_state;
        end
		  
      STATE_EXECUTE_10_0:
        begin
          if (aaa == OP_STX || aaa == OP_LDX) begin
            temp <= reg_x;
            wb_state <= STATE_WRITEBACK_X;
          end else begin
            temp <= reg_a;
          end

          state <= STATE_EXECUTE_10_1;
        end
		  
      STATE_EXECUTE_10_1:
        begin
          case (aaa)
            OP_ASL:
                result[8:0]  <= { source[7],  source[6:0],  1'b0 };
            OP_ROL:
                result[8:0]  <= { source[7],  source[6:0],  flag_c };
            OP_LSR:
                result[8:0]  <= { source[0], 1'b0, source[7:1]  };
            OP_ROR:
                result[8:0]  <= { source[0], flag_c, source[7:1]  };
            OP_STX: 
					result <= temp;
            OP_LDX: 
					result <= source;
            OP_DEC: 
					result <= source - 1;
            OP_INC: 
					result <= source + 1;
          endcase

          // For ASL, ROL, LSR, ROR - the C flag is affected.
          if (aaa[2] == 0) 
				affects_c <= 1;

          if (aaa == OP_STX) begin
            size_imm <= 1;
            state <= STATE_WRITEBACK_MEM_0;
          end else if (aaa == OP_LDX) begin
            state <= STATE_WRITEBACK_X;
          end else begin
            state <= addressing_mode == MODE_A ? STATE_WRITEBACK_A : STATE_WRITEBACK_MEM_P;
          end
        end
		  
      STATE_WRITEBACK_A:
        begin
			 if (wb == 1) reg_a[7:0] <= result[7:0];
			 if (affects_c) flags[FLAG_C] <= result[8];
			 flags[FLAG_Z] <= result[7:0] == 0;
			 if (affects_n) flags[FLAG_N] <= result[7];
			 if (affects_v) flags[FLAG_V] <= temp[7] == (source[7] ^ is_sub) && result[7] != temp[7];

          state <= STATE_FETCH_OP_0;
        end
		  
      STATE_WRITEBACK_X:
        begin
			if (wb == 1) 
				reg_x <= result[7:0];
			 flags[FLAG_Z] <= result[7:0] == 0;
			 flags[FLAG_N] <= result[7];

		 state <= STATE_FETCH_OP_0;
        end
		  
      STATE_WRITEBACK_Y:
        begin
			if (wb == 1) 
				reg_y <= result[7:0];
			 flags[FLAG_Z] <= result[7:0] == 0;
			 flags[FLAG_N] <= result[7];

          state <= STATE_FETCH_OP_0;
        end
		  
      STATE_WRITEBACK_MEM_P:
        begin
			 if (affects_c) flags[FLAG_C] <= result[8];
			 flags[FLAG_Z] <= result[7:0] == 0;
			 flags[FLAG_N] <= result[7];
			 if (affects_v) flags[FLAG_V] <= temp[7] == (source[7] ^ is_sub) && result[7] != temp[7];

          state <= STATE_WRITEBACK_MEM_0;
        end
		  
      STATE_WRITEBACK_MEM_0:
        begin
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          mem_address <= ea + wb_count;

          case (wb_count)
            0: mem_write <= result[7:0];
//            1: mem_write <= result[15:8];
          endcase

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
          if (bbb == 3'b000)
            // OP_BRA, OP_BRL.
            do_branch <= 1;
          else
            // BPL, BMI, BVC, BVS, BCC, BCS, BNE, BEQ.
            case (aaa[2:1])
              2'b00: do_branch <= flag_n == aaa[0];
              2'b01: do_branch <= flag_v == aaa[0];
              2'b10: do_branch <= flag_c == aaa[0];
              2'b11: do_branch <= flag_z == aaa[0];
            endcase

          pc <= pc + 1;
          mem_address <= pc;
          mem_bus_enable <= 1;
          state <= STATE_BRANCH_1;
        end
		  
      STATE_BRANCH_1:
        begin
          mem_bus_enable <= 0;
          immediate_count <= immediate_count + 1;

          if (do_branch) 
				pc[15:0] <= $signed(pc[15:0]) + $signed(mem_read);
          state <= STATE_FETCH_OP_0;
        end
		  
      STATE_SET_FLAGS_0:
        begin
          mem_address <= pc;
          mem_bus_enable <= 1;
          pc <= pc + 1;
          state <= STATE_SET_FLAGS_1;
        end
		  
      STATE_SET_FLAGS_1:
        begin
          mem_bus_enable <= 0;
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
          mem_address <= {8'b00000001,sp};

          case (push_count)
            1: mem_write <= result[7:0];
            2: mem_write <= result[15:8];
          endcase

          push_count <= push_count - 1;
          sp <= sp - 1;
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
          sp <= sp + 1;
          mem_address <= {8'b00000001,sp};
          mem_bus_enable <= 1;
          pop_count <= pop_count + 1;
          state <= STATE_POP_1;
        end
		  
      STATE_POP_1:
        begin
          mem_bus_enable <= 0;

          case (pop_count)
            1: source[7:0]   <= mem_read;
            2: source[15:8]  <= mem_read;
          endcase

          if (pop_count == size_imm)
            state <= STATE_POP_WB;
          else
            state <= STATE_POP_0;
        end
		  
      STATE_POP_WB:
        begin
          case (cc)
            2'b00:
              case (bbb)
                3'b000:
                  case (aaa)
                    OP_RTS: 
							pc[15:0] <= source[15:0];
                  endcase
                3'b010:
                  case (aaa)
                    OP_PLP: 
							flags[7:0] <= source[7:0];
                    OP_PLA:
							reg_a[7:0]  <= source[7:0];
                  endcase
              endcase
          endcase

          state <= STATE_FETCH_OP_0;
        end
		  
      STATE_RTI_0:
        begin
          sp <= sp + 1;
          mem_address <= {8'b00000001,sp};
          mem_bus_enable <= 1;
          immediate_count <= immediate_count + 1;
          state <= STATE_RTI_1;
        end
		  
      STATE_RTI_1:
        begin
          mem_bus_enable <= 0;

          case (immediate_count)
            1: flags    <= mem_read;
            2: pc[7:0]  <= mem_read;
            3: pc[15:8] <= mem_read;
          endcase

          if (immediate_count == size_imm)
            state <= STATE_FETCH_OP_0;
          else
            state <= STATE_RTI_0;
        end
		  
/*      STATE_STZ:
        begin
          result <= 0;
          state <= STATE_WRITEBACK_MEM_0;
        end*/
		  
      STATE_TEST_BITS:
        begin
			 flags[FLAG_Z] <= source[7:0]  & reg_a[7:0]  == 0;

			 if (bbb[2] == 0)
				result[7:0] <= source[7:0] |  reg_a[7:0];
			 else
				result[7:0] <= source[7:0] & ~reg_a[7:0];
          state <= STATE_WRITEBACK_MEM_0;
        end
		  
      STATE_JMP_ABS_0:
        begin
          mem_address <= pc;
          mem_bus_enable <= 1;
          pc <= pc + 1;
          state <= STATE_JMP_ABS_1;
        end
		  
      STATE_JMP_ABS_1:
        begin
          if (indirect_count == 0) begin
            ea_indirect[7:0] <= mem_read;
            state <= STATE_JMP_ABS_0;
          end else begin
            if (bbb == 3'b011) begin
              ea_indirect[15:8] <= mem_read;
              state <= STATE_JMP_ABS_2;
            end else begin
// non c'è                ea_indirect <= { mem_read, ea_indirect[7:0] } + reg_x[7:0];

              state <= STATE_JMP_ABS_2;
            end
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
            source[7:0] <= mem_read;
            state <= STATE_JMP_ABS_2;
          end else begin
            pc <= { mem_read, source[7:0] };

            if (aaa[2] == 1) begin
              // JSR.
              size_imm <= 2;
              result <= pc[15:0];
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
            flags[FLAG_B] <= 0;
          end else begin
            flags[FLAG_B] <= 1;
          end

          mem_bus_enable <= 0;
          mem_write_enable <= 0;
        end
		  
      STATE_IRQ_0:		// opp. unire con STATE_PUSH come in JSR
        begin
          mem_address <= {8'b00000001,sp};
          mem_bus_enable <= 1;
          mem_write_enable <= 1;
          immediate_count <= immediate_count + 1;
          case (immediate_count)
            1: mem_write <= pc[15:8];
            2: mem_write <= pc[7:0];
            3: mem_write <= flags;
          endcase

          sp <= sp - 1;
          state <= STATE_IRQ_1;
        end
		  
      STATE_IRQ_1:
        begin
          mem_bus_enable <= 0;
          mem_write_enable <= 0;

          if (immediate_count == size_imm) begin
            state <= STATE_FETCH_OP_0;
//				pc <= 16'hff50;
				
            pc <= 16'hfffe;
            mem_address <= 16'hfffe;
			 instruction <= 8'h4c;		// non 6c... strano
				state <= STATE_DECODE;
				end
          else
            state <= STATE_IRQ_0;
	  
        end
		  
    endcase
end
	

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
  .reset          (mem_bus_reset)
);

addressing_mode addressing_mode_0(
  .cc          (cc),
  .bbb         (bbb),
  .aaa         (aaa),
  .mode        (addressing_mode),
  .extra_bytes (extra_bytes)
);

reg_mode reg_mode_0(
  .x      (flag_b),
);

endmodule


