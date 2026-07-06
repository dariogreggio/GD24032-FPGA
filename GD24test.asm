BEEP_SL RECORD	BEEP_S:5=5, BEEP_L: 3



  dd 0x06000000            ; Initial Status (Supervisor
  dd 0x00000500 ,           ; Initial PC
  dd 0x00000000            ; Initial WP (relativo a inizio RAM!
  dd 0x00101000            ; Initial SP

startup equ 0x0004
;extrn bucodic


;	dseg 0x00100000			; RAM_START
cursor_x equ 0x100100 
cursor_y equ 0x100101
scratchpad equ 0x100104


;0010
  dd defaultException,0x00000000            ; Bus error
  dd defaultException,0x00000000            ; Address error
  dd defaultException,0x00000000            ; Illegal opcode
  dd defaultException,0x00000000            ; Divide by 0
  dd defaultException,0x00000000            ; CHK Instruction
  dd defaultException,0x00000000            ; Privilege Violation
  dd defaultException,0x00000000            ; TRAPV Instruction
	dd defaultException,0x00000000            ; Trace
;0050
  dd defaultException,0x00000000  ; Reserved
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; 
	dd defaultException,0x00000000  ; #30
;0100
  dd defaultException,0x00000000  ; Trap utente #0
  dd defaultException,0x00000000  ; Trap utente #1
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd TRAP_4,0x00000000  ; #4=Gestione Video
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
;0180
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; Trap #31
;0200
  dd defaultException,0x00000000  ; Trap utente #32
  dd defaultException,0x00000000  ;
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
;0280  
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; 
  dd defaultException,0x00000000  ; Trap #32
;0300
  dd defaultInterrupt,0x00000000  ; IRQ #0
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
;0380  
	dd defaultInterrupt,0x00000000  ; IRQ #16
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ; 
  dd defaultInterrupt,0x00000000  ;
  dd defaultInterrupt,0x00000000  ; 
;0400
		; Reserved area
;	dseg ends
		
;	cseg 0x500
		org 0x500
;  MOV.b [R3!],30
 ; MOV.b [--R3],3
 ; MOV.b [R2++],3
	LDIM 3<<2

	LDWP 0x00010800
	LDWP 0x00104000
	LDSP 1,0x101000
	LDSP 0,0x102000
	STST R0
	STSP R2
	STWP R1
	LDST 0x00000000			; passo a USER mode


;	DAA R0
;	CPUID R1
;	XLAT R0,R2
;	XLATB R0,R2
;	SWAPR R1
;	TRAPV
;	TEST.b R0,100
;	AND.b R0,100
;	BSFR R7,R11,1


;	CALL ls,delay
	MOV.q R0,400005612001			; 00000534: 04c40000 223141E1 0000005D 
	MOV.q R3,R4	; 00000540:	04C43220 
	NOP	; 00000544: 00000000 

	STM.w [R2--],{R0-R3}		; 00000548

	MOV.d.f R4,400
	MOV.b R1,100
	MOV.b R1,R4

	MOV.d [0x100010],0x554003
	MOV.w [0x100014],0x4103
	MOV.d R5,0x100018
	MOV.d [R5],R1
	CALL testcall1
;	CALL R4
	JMP testjmp
testjmp2:
	BEQ testjmp
	CALL testcall1
	BL testcall2
	NOP
	ADD.b R1,100
	ADD.b [R5++],92
  OR.b R2,0x40
  INC.b R0
;	OR.b [--R5],0x71
  NEG.d R2
;  NEG.d (R2--)
  SLA.d R2,2

;		TRAP #7
	CLR.d R0
	PUSH.b 65
	POP.b R0
	CALL 0x800		; delay! prova numero

	MOV.b R8,VIDEO_INIT		;(init)
	MOV.b R1,7		;(colore bordo)
	MOV.b R0,8		;(enabled; modo=text)
	TRAP VIDEO_SVC
	MOV.b R8,VIDEO_CLS	;(cls)
	MOV.b R0,15		;(colore)
	TRAP VIDEO_SVC
	MOV.b R8,VIDEO_SETXY	;(setXY)
	MOV.b R0,2		;(X)
	MOV.b R1,1		;(Y)
	TRAP VIDEO_SVC
	MOV.b R8,VIDEO_PRINT		;(print)
	LEA R9,stringa	;(stringa)
	mov.b R10,3		;(colore testo)
; prova					0x0B820188,0x00000000, 			; LEA R0,R2
	TRAP VIDEO_SVC

call prove_numeri
	CALL  putcharLF

	CPUID.d R9
;	SWAPR.d R9
	MOV.B R0,R9
	MOV.b R8,VIDEO_CHAR
	MOV.b R1,1
	TRAP VIDEO_SVC
	RR.d  R9,8
	MOV.B R0,R9
	MOV.b R8,VIDEO_CHAR
	MOV.b R1,1
	TRAP VIDEO_SVC
	RR.d  R9,8
	MOV.B R0,R9
	MOV.b R8,VIDEO_CHAR
	MOV.b R1,1
	TRAP VIDEO_SVC
	RR.d  R9,8
	MOV.B R0,R9
	MOV.b R8,VIDEO_CHAR
	MOV.b R1,1
	TRAP VIDEO_SVC



	MOV.b R4,2
idle:
;	MOV.d R0,8192  ; ~25000uS IN EFFETTI sono circa 10-12mS su hardware... meglio :)
	MOV.d R0,20000 ; ~25000uS 
	CALL delay
	INC.b.f [0xb8000+32*2]
	INC.b.f z, [0xb8000+32*2+1]

	XOR.b R4,1
	OUT.b 0x61,R4

	IN  R0,0x6f
	TB  R0,0
	BEQ idle
	div r0,0			; prova eccezione!

	JR idle			;(idle+inc video char)

testjmp:
	nop
	jr testjmp2



testcall1:
	RET ;(da CALL)
testcall2:
	RETU ;(da BL)


stringa:
	string "CPU GD24032 - v0.11\n_\nprova testo a capo "		;OCCHIO LST... si incasina e rimane "fuori sincro" se ci sono byte non multipli di 4!
stringa_excep:
	string "Exception: "
	db 0aah

	align 4
	dq 1234567890h
;	db 30h
froci BEEP_SL <3,1>


;	align 4		;// FORZARE Automaticamente? mah...




		org 0x800

public	delay
delay:
	RDTS.d R1          ; dato 1uS circa per istruzione, il ritardo vale circa 3uS*R0
	ADD.d R0,R1
delay_:
	RDTS R1
	CMP.d.f R1,R0
	BC  delay_
	RET    ; test R9, 7			;(da CALL)

provareg PROC PUBLIC USES A,X
	LOCAL xyz:WORD ,xy3:BYTE
	MOV.w R0,xyz
	CMP.b R2,xy3
provareg ENDP


	org 0x0c00
defaultException:
	MOV.b R8,VIDEO_SETXY		;(setXY)
	MOV.b R0,4		;(X)
	MOV.b R1,10		;(Y)
	TRAP VIDEO_SVC
	MOV.b R8,VIDEO_PRINT		;(print)
	LEA R9,stringa_excep
	MOV.b R10,15		;(colore testo)
	TRAP VIDEO_SVC

;	LDSP R1
	STEX R0,0			; PC eccezione
;	MOV.d R0,[R1+4]		; PC eccezione
	MOV.b R1,15		;(colore testo)
	CALL print_hex_address
	MOV.B R0,' '
	CALL putchar
	STEX R0,2			; SP all'eccezione
;	STEX R2,4			; Status eccezione
;	MOV.d R0,[R1+0]		; Status eccezione
	MOV.b R1,15
	CALL print_hex_address
	MOV.B R0,' '
	CALL putchar
	STEX R0,5			; codice eccezione in LSB
	MOV.b R1,4
	CALL print_hex_byte

	JR $
	RETI
	
; OCCHIO A SFORARE!!!

	org 0xd00
defaultInterrupt:
	RETI


	org 0x1000
TRAP_4:
;1000 trap gestione video: entra R8=servizio 
VIDEO_SVC EQU 4
VIDEO_INIT EQU 0		;	0=reset/init schermo R0=modo
VIDEO_CLS EQU 1			;	1=CLS R0=colore
VIDEO_CHAR EQU 2		;	2=PutChar R0=char R1=colore
VIDEO_SETXY EQU 3		;	3=SetXY R0=x R1=y
VIDEO_PRINT EQU 4		;	4=Print 0-term R9=string address R10=colore
VIDEO_SVC_MAX EQU 5

	CMP.b.f R8,VIDEO_SVC_MAX
	BNC trap4_err

;	SLA.b r8,2			; MAX 64 :)
	AND.d r8,255
	JMP (r8+trap4_table)

;	CMP.b.f R8,0
;	BEQ trap4_0
;	CMP.b.f R8,1
;	BEQ trap4_1
;	CMP.b.f R8,2
;	BEQ trap4_2
;	CMP.b.f R8,3
;	BEQ trap4_3
;	CMP.b.f R8,4
;	BEQ trap4_4

trap4_err:
	CLR.b.f R0
	RETI

trap4_table:
	dd trap4_0,trap4_1,trap4_2,trap4_3,trap4_4

trap4_0:
	MOV.d R2,0x0b8000			;(CGA base)
	MOV.d R3,0x03d8				;(CGA register #0)
	OUT.b R3,R0						;(enable)  [ | 1 (80x25) ]
	INC.d R3						;(CGA register #1)
	OUT.b R3,R1 ;(colore sfondo)
;	INS.b (R1++),R0

	JR endTrap4

trap4_1:
	MOV.d R2,0x0b8000			;(CGA base)
	MOV.d R1,80*25				;(80x25 cmq)
	SLA.d R0,8
	OR. b R0,' '				;(spazio + colore)
	MOV.w [R2++],R0
	DJNZ.d R1,$-4
;	MOVS.w [R2++],R0,R1			; 0x06542201
	; MOVS.w(R1) [R2++],0x0020 ma non qua perché voglio il colore da R0

	CLR.b [cursor_x]		; CLR.w insieme!
	CLR.b [cursor_y]
	JR endTrap4

trap4_2:
	CALL putchar
	JR endTrap4

trap4_3:
	MOV.b [cursor_x],R0			;(X)
	MOV.b [cursor_y],R1			;(Y)
	CALL calc_vidpos	 ; prova
	JR endTrap4


public calc_vidpos
calc_vidpos:
	CLR.d R2
	MOV.b R2,[cursor_y]
	MUL.d R2,40*2		; *2, char + colore
	ADD.d R2,0x0b8000		;(CGA base)
	CLR.d R8
	MOV.b R8,[cursor_x]
	ADD.d R2,R8
	ADD.d R2,R8			; *2, char + colore
	RET

hex2asc:			; entra R0=digit
	AND.b R0,0xf
	ADD.b R0,'0'
	CMP.b R0,'9'
	RET c
 	ADD.b R0,'A'-('9'+1)
	RET
print_dec_number:	; entra R0=numero (<100000)
	ENTER R10,16
	CLR.B [R10--]			; marker...
	TB.d  R0,31
	NEG  nz,R0
	PUSH.d R0
	MOV.b R0,'-'
	CALL nz,putchar
	POP.d  R0
print_dec_number3:
	DIV.d  R0,10
	PUSH.d R0
	MOV.d.f R0,R0		; se resto e quoziente=0
	BEQ print_dec_number2
	SWAP.d R0		; recupero il resto
	ADD.b R0,'0'
	MOV.B [R10--],R0
	POP.d  R0
	AND.d R0,0xffff
	JR  print_dec_number3
print_dec_number2:
	MOV.B.f R0,[++R10]
	BEQ print_dec_number4
	CALL putchar
	JR  print_dec_number2
print_dec_number4:
	LEAVE R10
	RET
print_dec_numberL:	; entra R0=numero 
	ENTER R10,16
	PUSH.d R1		; salvo colore
	CLR.B [R10--]			; marker...
	TB.d  R0,31
	NEG  nz,R0
	PUSH.d R0
	MOV.b R0,'-'
	CALL nz,putchar
	POP.d  R0
print_dec_numberL3:
	CLR.d  R1
	DIV.q  R0,10
	MOV.q.f R0,R0		; se resto e quoziente=0
	BEQ print_dec_numberL2
	ADD.b R1,'0'			; qui il resto
	MOV.B [R10--],R1
	JR  print_dec_numberL3
print_dec_numberL2:
	POP.d R1		; recupero il colore
print_dec_numberL2_:
	MOV.B.f R0,[++R10]
	BEQ print_dec_numberL4
	CALL putchar
	JR  print_dec_numberL2_
print_dec_numberL4:
	LEAVE R10
	RET
print_hex_address:	;entra R0=DWORD
	RL.d  R0,8
	PUSH R0
	CALL print_hex_byte
	POP R0
	RL  R0,8
	PUSH R0
	CALL print_hex_byte
	POP R0
	RL  R0,8
	PUSH R0
	CALL print_hex_byte
	POP R0
	RL  R0,8
;	RET		Prosegue!
print_hex_byte:		; entra R0=byte
	MOV.b R9,R0
	SRL.b R0,4
	CALL hex2asc
	CALL putchar
	MOV.b R0,R9
	CALL hex2asc
;	CALL putchar	:)
;	RET		Prosegue!
putchar:			; entra R0=byte,R1=colore
	CALL calc_vidpos
	CMP.B R0,'\n'
	BEQ putchar2

	MOV.b [R2++],R0
	MOV.b [R2++],R1			; colore

	INC.b [cursor_x]
	CMP.b [cursor_x],40
	RET c

putchar2:
	CLR.b [cursor_x]
	INC.b [cursor_y]

	CMP.b [cursor_y],24
	DEC.b nc,[cursor_y]
	CALL nc, scroll
	RET

putcharLF:
	MOV.b R0,'\n'
	JR  putchar

scroll:
	MOV.d R2,0x0b8000			;(CGA base)
	MOV.d R8,40*2
	ADD.d R2,R8
	MOV.D R1,40*(25-1)*2
	MOVS.w [R2++],[R8++],R1
	RET


warning VAFFANCULO merde!
trap4_4:
	MOV.b.f R0,[R9++]
	BEQ endTrap4_
	MOV.B R1,R10
	CALL putchar
;	CALL calc_vidpos
;	ADD.d R2,R8
;	MOV.b.f [R2++],[R0++]
;	MOV.b [R2++],R1				;(colore)
	JR  trap4_4

	
endTrap4_:


;stsp r10
;mov.b r0,(r10+r1)



endTrap4:
	MOV.b.f R0,1  
	RETI


prove_numeri:
	MOV  R0,R2
	MOV.b R1,14
	call print_hex_address
	MOV.b R0,';'
	CALL putchar
	MOV.b R0,' '
	CALL.d putchar
	PUSH.d R9
	MOV.w R0,R9
	SRL.w R0,8
	MOV.b R1,8
	CALL.d print_hex_byte
	POP.d R0
	MOV.b R1,8
	CALL.d print_hex_byte

	CALL.d putcharLF
	MOV  R0,R2
	MOV.b R1,5
	CALL.d print_dec_numberL


	CALL.d putcharLF
	mov.d r0,1234
	MOV.b R1,7
	CALL.d print_dec_number

	CALL.d putcharLF
	mov.d r0,-1235
	MOV.b R1,7
	CALL.d print_dec_number
	RET

;	cseg ends

