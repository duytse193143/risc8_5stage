// ====
//  FILE        : rtl/imem.v
//  MODULE      : imem
//  PROJECT     : 8-bit RISC Processor Core with 5-Stage Pipeline
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Instruction Memory (program ROM): 256 words x 16 bits.
//    The PC is the address; the 16-bit instruction appears on 'instr'.
//    Separate instruction and data memories = HARVARD architecture, so
//    IF (Stage 1) and MEM (Stage 4) never fight over one memory.
//
//  WHO USES THIS FILE
//    -> Instantiated in rtl/risc8_5stage_core.v as
//         "imem #(.INIT_FILE(IMEM_FILE)) u_imem (...)"   (Stage 1, IF)
//
//  THIS FILE CALLS
//    -> $readmemh : built-in Verilog system task. Loads program.hex
//       (produced by sw/asm8.py) into the ROM array.
// =====================================================================

`timescale 1ns/1ps

module imem #(
    // File to load. risc8_5stage_core.v passes its IMEM_FILE value here.
    parameter INIT_FILE = "program.hex"
) (
    input  wire [7:0]  addr,    // = PC
    output wire [15:0] instr    // instruction at that address
);

    reg [15:0] rom [0:255];     // 256 instructions
    integer i;

    initial begin
        // Fill with NOP (0x0000) so unused locations are harmless.
        for (i = 0; i < 256; i = i + 1) rom[i] = 16'h0000;
        // Load the program (hex words, one per line, '//' = comment).
        $readmemh(INIT_FILE, rom);
    end

    // Asynchronous read: instruction available in the same cycle.
    assign instr = rom[addr];

endmodule
