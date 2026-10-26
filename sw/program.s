; =====================================================================
;  FILE     : sw/program.s
;  PROJECT  : 8-bit RISC Processor Core with 5-Stage Pipeline
; ---------------------------------------------------------------------
;  WHAT THIS FILE DOES
;    The test program, written in this CPU's assembly language.
;    It is turned into machine code by sw/asm8.py:
;        python3 sw/asm8.py sw/program.s program.hex
;    program.hex is then loaded by rtl/imem.v, and the final results
;    are checked by tb/tb_risc8_5stage.v.
;
;  SYNTAX
;    ';' starts a comment     'name:' defines a label
;    Rn = register 0..7        [Rn] = memory address held in Rn
;
;  WHAT IT TESTS
;    Part 1 : logic, shifts, forwarding, a taken BZ with a flushed instr
;    Part 2 : a loop that adds 5+4+3+2+1 (BNZ taken 4 times)
;    Part 3 : store, load, load-use forwarding, carry, JMP and HLT
; =====================================================================

; ---------- Part 1 : ALU operations and forwarding ----------
        LDI  R1, 0x3C        ; R1 = 0x3C
        LDI  R2, 0x0F        ; R2 = 0x0F
        AND  R3, R1, R2      ; R3 = 0x0C  (R2 forwarded from WB)
        OR   R4, R1, R2      ; R4 = 0x3F
        XOR  R5, R3, R4      ; R5 = 0x33  (R4 forwarded)
        SHL  R6, R5          ; R6 = 0x66  (R5 forwarded)
        SHR  R7, R6          ; R7 = 0x33  (R6 forwarded)
        SUB  R7, R7, R5      ; R7 = 0x00 -> Z = 1
        BZ   skip1           ; Z = 1, so the branch is taken
        LDI  R7, 0xFF        ; wrong path: must be flushed (R7 stays 0)
skip1:

; ---------- Part 2 : loop, sum = 5+4+3+2+1 ----------
        LDI  R1, 5           ; loop counter
        LDI  R2, 0           ; sum
        LDI  R3, 1           ; constant 1
loop:
        ADD  R2, R2, R1      ; sum = sum + counter
        SUB  R1, R1, R3      ; counter = counter - 1 (sets Z at 0)
        BNZ  loop            ; repeat while counter != 0 -> sum = 15

; ---------- Part 3 : memory, carry, jump, halt ----------
        LDI  R4, 0x20        ; R4 = memory address 0x20
        ST   R2, [R4]        ; MEM[0x20] = 15
        LD   R5, [R4]        ; R5 = MEM[0x20] = 15
        ADDI R5, 0xF0        ; R5 = 15 + 240 = 0xFF (load result forwarded)
        ADDI R5, 1           ; R5 = 0x100 -> 0x00, so C = 1 and Z = 1
        JMP  done            ; unconditional jump
        LDI  R6, 0xEE        ; wrong path: must be flushed
done:
        HLT                  ; stop the processor
        LDI  R6, 0xAA        ; never executed
