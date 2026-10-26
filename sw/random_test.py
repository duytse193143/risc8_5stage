#!/usr/bin/env python3
# =====================================================================
#  FILE     : sw/random_test.py
#  PROJECT  : 8-bit RISC Processor Core with 5-Stage Pipeline
# ---------------------------------------------------------------------
#  WHAT THIS FILE DOES
#    Random regression test (also called "differential testing"):
#      1. Generates a random program (random instructions, random
#         registers, forward branches only so it always ends).
#      2. Runs it on the golden model           -> sw/iss.py : run()
#      3. Runs it on the Verilog 5-stage core   -> tb/tb_dump.v
#      4. Compares registers, flags and memory. Any difference = bug.
#    Random programs create many back-to-back dependencies, so they
#    exercise forwarding, load-use stalls and branch flushes far more
#    than a hand-written test.
#
#  HOW TO RUN (from the project folder)
#    python3 sw/random_test.py 300        # 300 random programs
#
#  FUNCTIONS IN THIS FILE (and who calls whom)
#    random_program() -> called by main(): builds a list of 16-bit words
#    run_rtl()        -> called by main(): writes program.hex, runs vvp,
#                        reads dump.txt
#    main()           -> calls random_program(), iss.run(), run_rtl()
#
#  OTHER FILES USED
#    sw/iss.py        : run()   (golden model)
#    tb/tb_dump.v     : testbench that writes dump.txt
#    rtl/*.v          : the processor
# =====================================================================

import random, subprocess, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from iss import run          # golden model from sw/iss.py


def random_program(n=40):
    """Return n random instructions followed by HLT (as 16-bit ints)."""
    words = []
    for pc in range(n):
        op = random.choice([1, 2, 3, 4, 5, 6, 7, 8, 8, 9, 0xA, 0xB, 0xC, 0xD, 0xE, 0])
        rd, rs1, rs2 = (random.randrange(8) for _ in range(3))
        if op in (0xC, 0xD, 0xE):
            # forward branch only: target between pc+1 and the HLT at n
            words.append(op << 12 | random.randint(pc + 1, n))
        elif op in (8, 9):
            words.append(op << 12 | rd << 9 | random.randrange(256))
        else:
            words.append(op << 12 | rd << 9 | rs1 << 6 | rs2 << 3)
    words.append(0xF000)     # HLT
    return words


def run_rtl(words):
    """Run the program on the Verilog core and return its final state."""
    with open("program.hex", "w") as f:
        words = words + [0] * (256 - len(words))      # pad ROM with NOPs
        f.write("\n".join(f"{w:04X}" for w in words) + "\n")
    if os.path.exists("dump.txt"):
        os.remove("dump.txt")
    subprocess.run(["vvp", "-n", "dump.vvp"], capture_output=True)
    v = open("dump.txt").read().split()
    regs = [int(x, 16) for x in v[0:8]]
    z, c = int(v[8]), int(v[9])
    mem = [int(x, 16) for x in v[10:266]]
    return regs, mem, z, c


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    # Compile the RTL + dump testbench once.
    subprocess.run(["iverilog", "-g2005", "-o", "dump.vvp",
                    "rtl/alu.v", "rtl/regfile.v", "rtl/imem.v", "rtl/dmem.v",
                    "rtl/control_unit.v", "rtl/hazard_unit.v",
                    "rtl/risc8_5stage_core.v", "tb/tb_dump.v"], check=True)
    random.seed(1)                       # repeatable test set
    for t in range(count):
        prog = random_program()
        expected = run(prog)             # golden model (sw/iss.py)
        got = run_rtl(prog)              # hardware model (Verilog)
        if expected != got:
            print(f"MISMATCH in program {t}")
            print("expected regs", expected[0], "Z,C", expected[2:])
            print("rtl      regs", got[0], "Z,C", got[2:])
            sys.exit(1)
    print(f"{count} random programs: RTL matches golden model in all cases")


if __name__ == "__main__":
    main()
