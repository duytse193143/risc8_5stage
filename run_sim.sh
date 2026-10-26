#!/bin/sh
# ==================================================================
#  run_sim.sh  -  one-click simulation on Linux / macOS
#  Needs: python3 and Icarus Verilog (iverilog, vvp)
#  Steps: 1) assemble program  2) compile Verilog  3) run simulation
# ==================================================================
set -e
cd "$(dirname "$0")"

echo "[1/3] Assembling sw/program.s -> program.hex"
python3 sw/asm8.py sw/program.s program.hex

echo "[2/3] Compiling Verilog (file list in files.f)"
iverilog -g2005 -o sim.vvp -c files.f

echo "[3/3] Running simulation"
vvp sim.vvp
echo
echo "Waveform saved as risc8_5stage.vcd (open with: gtkwave risc8_5stage.vcd)"
