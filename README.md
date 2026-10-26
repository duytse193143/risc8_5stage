# 8-bit RISC Processor Core with a 5-Stage Pipeline (Verilog)

A synthesizable 8-bit RISC CPU written in Verilog-2001 with a classic five-stage pipeline
**IF → ID → EX → MEM → WB**, verified with a self-checking testbench in **AMD Vivado** and
synthesized for a **Xilinx Artix-7** FPGA.

> This is a custom 8-bit RISC instruction set, not RISC-V (RISC-V's smallest base is 32-bit).

![Full simulation waveform](docs/05_wave_full.jpg)

---

## Highlights

- 16-instruction custom ISA, fixed 16-bit instructions, 8 × 8-bit registers (R0–R7)
- Harvard architecture: 256 × 16 instruction ROM, 256 × 8 data RAM
- Full hazard handling:
  - **Forwarding** from EX/MEM and MEM/WB plus a write-through **register-file bypass**
  - **1-cycle load-use stall**
  - **2-cycle branch flush** (branches resolved in EX)
- Self-checking testbench with a per-cycle pipeline trace and automatic PASS/FAIL
- **All tests passed**: 34 instructions in 51 cycles, **CPI = 1.50**
- Post-synthesis on Artix-7: **238 LUTs, 187 flip-flops** (about 1 % of the device)

---

## Specification

| Item | Value |
|---|---|
| Data width | 8 bits |
| Instruction width | 16 bits, fixed |
| Registers | 8 × 8-bit (R0–R7) |
| Program counter | 8 bits (256 addresses) |
| Instruction memory | 256 × 16-bit ROM, loaded from `program.hex` with `$readmemh` |
| Data memory | 256 × 8-bit RAM (LD / ST) |
| Flags | Z (zero), C (carry / borrow / shifted-out bit) |
| Pipeline | IF, ID, EX, MEM, WB |
| Core ports | `clk`, `rst` → `halted`, `pc_out[7:0]`, `flags_out[1:0]`, `instr_done` |

## Instruction Set

| Opcode | Instruction | Operation | Flags |
|---|---|---|---|
| 0 | `NOP` | no operation | – |
| 1 | `ADD rd, rs1, rs2` | rd = rs1 + rs2 | Z, C |
| 2 | `SUB rd, rs1, rs2` | rd = rs1 − rs2 | Z, C (borrow) |
| 3 | `AND rd, rs1, rs2` | rd = rs1 & rs2 | Z |
| 4 | `OR  rd, rs1, rs2` | rd = rs1 \| rs2 | Z |
| 5 | `XOR rd, rs1, rs2` | rd = rs1 ^ rs2 | Z |
| 6 | `SHL rd, rs1` | rd = rs1 << 1 | Z, C = old bit 7 |
| 7 | `SHR rd, rs1` | rd = rs1 >> 1 | Z, C = old bit 0 |
| 8 | `LDI rd, imm8` | rd = imm8 | – |
| 9 | `ADDI rd, imm8` | rd = rd + imm8 | Z, C |
| A | `LD rd, [rs1]` | rd = MEM[rs1] | – |
| B | `ST rd, [rs1]` | MEM[rs1] = rd | – |
| C | `JMP addr8` | PC = addr8 | – |
| D | `BZ addr8` | if Z = 1: PC = addr8 | – |
| E | `BNZ addr8` | if Z = 0: PC = addr8 | – |
| F | `HLT` | stop the processor | – |

**Instruction formats** (opcode is always bits [15:12]):

```
R-type : [15:12] opcode | [11:9] rd | [8:6] rs1 | [5:3] rs2 | [2:0] 000
R1-type: [15:12] opcode | [11:9] rd | [8:6] rs1 | [5:0] 000000
I-type : [15:12] opcode | [11:9] rd | [8] 0     | [7:0] imm8
J-type : [15:12] opcode | [11:8] 0000           | [7:0] addr8
```

Example: `LDI R1, 0x3C` → `1000 001 0 0011 1100` → `0x823C`.

---

## Architecture

```
        IF/ID          ID/EX           EX/MEM          MEM/WB
  IF ────┃──── ID ──────┃──── EX ───────┃──── MEM ──────┃──── WB
 PC,imem    control_unit     forward mux     dmem            rd <- result
            regfile read     ALU, flags      LD / ST
            (+ bypass)       branch decision
                      ▲            ▲     │                      │
                      │      hazard_unit (fwd_a/b_sel, stall)   │
                      └──────────── write-back / forwarding ────┘
```

| File | Kind | Role |
|---|---|---|
| `rtl/risc8_5stage_core.v` | top level | PC, 4 pipeline registers, flags, branch/halt logic, connects all modules |
| `rtl/imem.v` | ROM | program memory (`$readmemh("program.hex")`) |
| `rtl/control_unit.v` | combinational | opcode → control signals |
| `rtl/regfile.v` | sequential | 8 × 8-bit, 2 read / 1 write ports, write-through bypass |
| `rtl/hazard_unit.v` | combinational | forwarding selects and load-use stall |
| `rtl/alu.v` | combinational | 8 operations, Z and C flags |
| `rtl/dmem.v` | RAM | 256-byte data memory |
| `tb/tb_risc8_5stage.v` | testbench | clock/reset, per-cycle monitor, automatic PASS/FAIL |

### Hazard handling

| Hazard | Solution | Cost |
|---|---|---|
| Structural | Separate instruction and data memories | 0 |
| Data (RAW) | Forward from EX/MEM (`sel = 10`) or MEM/WB (`sel = 01`); register-file bypass for distance 3 | 0 |
| Load-use | Stall 1 cycle (hold PC and IF/ID, bubble into ID/EX), then forward from MEM/WB | 1 cycle |
| Control | Branch decided in EX; flush the 2 younger instructions | 2 cycles per taken branch |

---

## Verification

The directed test program (`sw/program.s`) covers every instruction class:

1. **Part 1** – ALU operations with back-to-back dependencies, `SUB` → Z = 1, a taken `BZ` over a wrong-path `LDI R7, 0xFF`
2. **Part 2** – a loop computing 5 + 4 + 3 + 2 + 1 = 15 with `BNZ`
3. **Part 3** – `ST`/`LD` at address 0x20, a load-use pair, 0xFF + 1 overflow (C = 1), `JMP` and `HLT`

### Result

```
PASS  R1 = 00      PASS  R5 = 00
PASS  R2 = 0f      PASS  R6 = 66
PASS  R3 = 01      PASS  R7 = 00
PASS  R4 = 20      PASS  MEM[20] = 0F
PASS  flags Z=1 C=1

cycles=51  instructions=34  CPI=1.50  load-use stalls=1  taken branches=6  forwards=12
*** ALL TESTS PASSED ***
```

**Cycle breakdown:** 34 (instructions) + 4 (pipeline fill) + 12 (6 taken branches × 2) + 1 (load-use stall) = **51 cycles**.

### Waveforms

| Forwarding | Branch flush |
|---|---|
| ![Forwarding](docs/06_wave_forwarding.jpg) | ![Branch flush](docs/07_wave_branch.jpg) |

| Load-use stall | Halt |
|---|---|
| ![Load-use stall](docs/08_wave_stall.jpg) | ![Halt](docs/09_wave_halt.jpg) |

---

## Synthesis (Vivado, Artix-7 xc7a35tcpg236-1)

| Resource | Used | Available | Utilization |
|---|---|---|---|
| Slice LUTs | 238 | 20,800 | 1.14 % |
| Flip-flops | 187 | 41,600 | 0.45 % |
| Bonded IOB | 14 | 106 | 13.21 % |

- The ALU uses 0 flip-flops (purely combinational).
- The register file uses exactly 64 flip-flops (8 × 8 bits).
- The 256-byte data memory is mapped to distributed LUT-RAM.

These are post-synthesis numbers.

---

## Repository Structure

```
risc8_5stage/
├── rtl/        alu.v, regfile.v, imem.v, dmem.v, control_unit.v,
│               hazard_unit.v, risc8_5stage_core.v
├── tb/         tb_risc8_5stage.v (directed self-checking test)
│               tb_dump.v (state dump for random regression)
├── sw/         program.s (test program), asm8.py (assembler),
│               iss.py (reference model), random_test.py
├── docs/       screenshots (simulation, synthesis)
├── program.hex machine code loaded by imem.v
└── README.md
```

---

## How to Run

### Vivado (behavioral simulation)

1. Create an **RTL Project** (part `xc7a35tcpg236-1` or any Artix-7).
2. Add the 7 files in `rtl/` as **design sources** and `tb/tb_risc8_5stage.v` as a **simulation source**.
3. Add `program.hex` to the project and set its file type to **Memory File**, so Vivado copies it into the simulation and synthesis run directories:
   ```tcl
   set_property file_type {Memory File} [get_files program.hex]
   ```
4. Set `tb_risc8_5stage` as the simulation top and `risc8_5stage_core` as the design top.
5. **Run Simulation → Run Behavioral Simulation**. The test stops by itself at 545 ns and prints `*** ALL TESTS PASSED ***` in the Tcl Console.
6. **Run Synthesis → Report Utilization** to see the resource usage.

### Changing the program

Edit `sw/program.s`, then assemble it:

```bash
python3 sw/asm8.py sw/program.s program.hex
```

If the program changes, update the expected values in `tb/tb_risc8_5stage.v` (`check_reg(...)`).

---

## Acknowledgements

Project specification and reference material provided by **GUVI × HCLTech** as part of the
**Semiconductor & VLSI Industry Readiness Program** (instructor: Mr Shivashish Pal).

## Author

**Tran Duy** (SE193143)
