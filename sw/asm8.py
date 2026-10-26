#!/usr/bin/env python3
# =====================================================================
#  FILE     : sw/asm8.py
#  PROJECT  : 8-bit RISC Processor Core with 5-Stage Pipeline
# ---------------------------------------------------------------------
#  WHAT THIS FILE DOES
#    A tiny ASSEMBLER. It converts human-readable assembly code
#    (sw/program.s) into 16-bit machine code in hexadecimal
#    (program.hex), which the processor's instruction memory loads.
#
#  HOW TO RUN
#    python3 sw/asm8.py sw/program.s program.hex
#
#  OUTPUT IS USED BY
#    rtl/imem.v -> $readmemh("program.hex", rom)
#    (the file name is passed down from tb/tb_risc8_5stage.v through
#     rtl/risc8_5stage_core.v as the parameter IMEM_FILE)
#
#  FUNCTIONS IN THIS FILE (and who calls whom)
#    reg()       -> called by assemble()   : "R5" -> 5
#    num()       -> called by assemble()   : "0x3C" / label -> number
#    assemble()  -> called by the __main__ block at the bottom
#
#  INSTRUCTION ENCODING (16 bits, must match rtl/control_unit.v)
#    R-type : [15:12] op | [11:9] rd | [8:6] rs1 | [5:3] rs2 | [2:0] 000
#    I-type : [15:12] op | [11:9] rd | [8] 0     | [7:0] imm8
#    J-type : [15:12] op | [11:8] 0000           | [7:0] address
# =====================================================================

import sys   # command-line arguments (sys.argv)
import re    # regular expressions, used to split operands on commas

# ---------------------------------------------------------------------
# Opcode table: mnemonic -> 4-bit opcode.
# These numbers MUST be the same as the localparams in
# rtl/control_unit.v, otherwise the CPU decodes the wrong instruction.
# ---------------------------------------------------------------------
OPS = {"NOP":0x0, "ADD":0x1, "SUB":0x2, "AND":0x3, "OR":0x4,  "XOR":0x5,
       "SHL":0x6, "SHR":0x7, "LDI":0x8, "ADDI":0x9, "LD":0xA, "ST":0xB,
       "JMP":0xC, "BZ":0xD,  "BNZ":0xE, "HLT":0xF}


def reg(t):
    """Convert a register operand to its number.
    Examples: 'R5' -> 5, '[R4]' -> 4 (brackets used by LD / ST).
    Called by: assemble()
    """
    return int(t.strip("[] ").upper().lstrip("R"))


def num(t, labels):
    """Convert an immediate or address operand to an integer.
    Accepts a label name ('loop'), hex ('0x3C') or decimal ('5').
    int(t, 0) understands the 0x prefix automatically.
    Called by: assemble()
    """
    t = t.strip()
    return labels[t] if t in labels else int(t, 0)


def assemble(lines):
    """Two-pass assembler.
    PASS 1: remove comments, record the address of every label.
    PASS 2: encode each instruction into a 16-bit word.
    Returns a list of (machine_word, source_text).
    Calls: reg(), num()
    Called by: the __main__ block below.
    """
    # ---------------- PASS 1 : labels ----------------
    src, labels = [], {}
    for ln in lines:
        ln = ln.split(";")[0].strip()        # drop comment after ';'
        if not ln:
            continue                          # skip empty lines
        if ln.endswith(":"):                  # 'loop:' is a label
            labels[ln[:-1]] = len(src)        # = address of next instruction
            continue
        src.append(ln)                        # a real instruction

    # ---------------- PASS 2 : encoding ----------------
    out = []
    for ln in src:
        # Split "ADD R2, R2, R1" -> mnemonic 'ADD', operands 'R2, R2, R1'
        m, *rest = ln.split(None, 1)
        m = m.upper()
        a = [x for x in re.split(r"\s*,\s*", rest[0])] if rest else []

        op = OPS[m] << 12                     # opcode into bits [15:12]

        if m in ("ADD", "SUB", "AND", "OR", "XOR"):
            # R-type: rd, rs1, rs2
            w = op | reg(a[0]) << 9 | reg(a[1]) << 6 | reg(a[2]) << 3
        elif m in ("SHL", "SHR", "LD", "ST"):
            # Two registers: rd, rs1   (LD/ST: rs1 holds the address)
            w = op | reg(a[0]) << 9 | reg(a[1]) << 6
        elif m in ("LDI", "ADDI"):
            # I-type: rd, imm8   (& 0xFF keeps only 8 bits)
            w = op | reg(a[0]) << 9 | (num(a[1], labels) & 0xFF)
        elif m in ("JMP", "BZ", "BNZ"):
            # J-type: 8-bit absolute target address
            w = op | (num(a[0], labels) & 0xFF)
        else:
            # NOP, HLT: opcode only
            w = op
        out.append((w, ln))
    return out


# ---------------------------------------------------------------------
# MAIN: runs only when the file is executed directly.
#   sys.argv[1] = input .s file, sys.argv[2] = output .hex file
# ---------------------------------------------------------------------
if __name__ == "__main__":
    prog = assemble(open(sys.argv[1]).read().splitlines())   # calls assemble()

    # Write program.hex: one 4-digit hex word per line + a comment.
    # $readmemh in rtl/imem.v ignores the '// ...' part.
    with open(sys.argv[2], "w") as f:
        for i, (w, ln) in enumerate(prog):
            f.write(f"{w:04X}  // {i:02d}: {ln}\n")
        # Pad the rest of the 256-word ROM with NOP (0000) so that
        # $readmemh in rtl/imem.v gets exactly 256 words (no warning).
        for i in range(len(prog), 256):
            f.write("0000\n")

    # Also print a listing on the screen: address, hex, source.
    for i, (w, ln) in enumerate(prog):
        print(f"{i:02d}  {w:04X}  {ln}")
