#!/usr/bin/env python3
# =====================================================================
#  FILE     : sw/iss.py
#  PROJECT  : 8-bit RISC Processor Core with 5-Stage Pipeline
# ---------------------------------------------------------------------
#  WHAT THIS FILE DOES
#    Instruction Set Simulator (ISS) = a "golden reference model".
#    It executes the same 16-bit machine code as the hardware, one
#    instruction at a time, with NO pipeline. Because it has no
#    pipeline, it cannot have hazard bugs, so its final register /
#    memory / flag values are the "correct answer" that the Verilog
#    pipeline must match.
#
#  FUNCTIONS IN THIS FILE
#    run(words) -> executes a list of 16-bit instruction words
#                  and returns (regs, mem, z, c)
#
#  WHO CALLS THIS FILE
#    sw/random_test.py imports it:  from iss import run
#
#  The behaviour here must match rtl/alu.v, rtl/control_unit.v and
#  rtl/risc8_5stage_core.v exactly.
# =====================================================================


def run(words, max_steps=10000):
    """Execute machine code until HLT. Returns (regs, mem, z, c)."""
    regs = [0] * 8          # R0..R7
    mem = [0] * 256         # data memory
    z = c = 0               # flags
    pc = 0
    for _ in range(max_steps):
        w = words[pc] if pc < len(words) else 0   # unused memory = NOP
        op = (w >> 12) & 0xF                       # [15:12]
        rd = (w >> 9) & 7                          # [11:9]
        rs1 = (w >> 6) & 7                         # [8:6]
        rs2 = (w >> 3) & 7                         # [5:3]
        imm = w & 0xFF                             # [7:0]
        nxt = (pc + 1) & 0xFF
        a, b = regs[rs1], regs[rs2]

        if 1 <= op <= 7 or op == 9:                # ALU instructions
            if op == 1:   r = a + b;            c = r >> 8          # ADD
            elif op == 2: r = a - b;            c = 1 if r < 0 else 0  # SUB borrow
            elif op == 3: r = a & b;            c = 0
            elif op == 4: r = a | b;            c = 0
            elif op == 5: r = a ^ b;            c = 0
            elif op == 6: r = a << 1;           c = (a >> 7) & 1    # SHL
            elif op == 7: r = a >> 1;           c = a & 1           # SHR
            else:         r = regs[rd] + imm;   c = r >> 8          # ADDI
            r &= 0xFF
            z = 1 if r == 0 else 0
            regs[rd] = r
        elif op == 8:  regs[rd] = imm                    # LDI
        elif op == 0xA: regs[rd] = mem[a]                # LD
        elif op == 0xB: mem[a] = regs[rd]                # ST
        elif op == 0xC: nxt = imm                        # JMP
        elif op == 0xD and z: nxt = imm                  # BZ
        elif op == 0xE and not z: nxt = imm              # BNZ
        elif op == 0xF: return regs, mem, z, c           # HLT
        pc = nxt
    raise RuntimeError("program did not halt")
