// =====================================================================
//  FILE        : rtl/control_unit.v
//  MODULE      : control_unit
//  PROJECT     : 8-bit RISC Processor Core with 5-Stage Pipeline
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Instruction decoder. Converts the 4-bit opcode into control
//    signals. In the 5-stage pipeline these signals are produced in
//    Stage 2 (ID) and then CARRIED DOWN the pipeline registers
//    (ID/EX -> EX/MEM -> MEM/WB), each stage using the ones it needs:
//      EX  uses : alu_op, alu_src_imm, flag_we, jump, br_z, br_nz
//      MEM uses : mem_we, mem_to_reg
//      WB  uses : reg_we
//
//    NEW compared with the 3-stage design: uses_a / uses_b.
//    They tell the hazard unit (rtl/hazard_unit.v) which read ports
//    an instruction really needs, so it never stalls for a register
//    the instruction does not actually read.
//
//  WHO USES THIS FILE
//    -> Instantiated in rtl/risc8_5stage_core.v as
//       "control_unit u_ctrl (...)" in Stage 2 (ID).
//    -> alu_op is used later by module alu (rtl/alu.v) in EX.
//    -> uses_a / uses_b go to module hazard_unit (rtl/hazard_unit.v).
//
//  THIS FILE CALLS : nothing (leaf module, combinational).
// ---------------------------------------------------------------------
//  OPCODE MAP (must match sw/asm8.py)
//    0 NOP   1 ADD   2 SUB   3 AND   4 OR    5 XOR   6 SHL   7 SHR
//    8 LDI   9 ADDI  A LD    B ST    C JMP   D BZ    E BNZ   F HLT
// =====================================================================

`timescale 1ns/1ps

module control_unit (
    input  wire [3:0] opcode,       // instr[15:12] from IF/ID register
    output reg  [2:0] alu_op,       // ALU operation (rtl/alu.v)
    output reg        alu_src_imm,  // 1: ALU operand B = imm8
    output reg        ra_is_rd,     // 1: read port A uses rd (ADDI)
    output reg        rb_is_rd,     // 1: read port B uses rd (ST data)
    output reg        uses_a,       // 1: instruction reads port A
    output reg        uses_b,       // 1: instruction reads port B
    output reg        reg_we,       // 1: write a register in WB
    output reg        mem_to_reg,   // 1: WB data comes from memory (LD)
    output reg        mem_we,       // 1: write data memory in MEM (ST)
    output reg        flag_we,      // 1: update Z and C in EX
    output reg        jump,         // JMP
    output reg        br_z,         // BZ
    output reg        br_nz,        // BNZ
    output reg        halt          // HLT
);

    localparam NOP=4'h0, ADD=4'h1, SUB=4'h2, AND=4'h3, OR =4'h4, XOR=4'h5,
               SHL=4'h6, SHR=4'h7, LDI=4'h8, ADDI=4'h9, LD=4'hA, ST=4'hB,
               JMP=4'hC, BZ =4'hD, BNZ=4'hE, HLT=4'hF;

    always @(*) begin
        // ---- STEP 1: defaults = NOP (also prevents latches) ----
        alu_op = 3'd0; alu_src_imm = 0; ra_is_rd = 0; rb_is_rd = 0;
        uses_a = 0; uses_b = 0;
        reg_we = 0; mem_to_reg = 0; mem_we = 0; flag_we = 0;
        jump = 0; br_z = 0; br_nz = 0; halt = 0;

        // ---- STEP 2: enable what each instruction needs ----
        case (opcode)
            // rd = rs1 OP rs2 : reads A and B, writes rd, sets flags
            ADD : begin alu_op = 3'd0; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end
            SUB : begin alu_op = 3'd1; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end
            AND : begin alu_op = 3'd2; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end
            OR  : begin alu_op = 3'd3; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end
            XOR : begin alu_op = 3'd4; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end

            // rd = rs1 << 1 / >> 1 : reads A only
            SHL : begin alu_op = 3'd5; uses_a = 1; reg_we = 1; flag_we = 1; end
            SHR : begin alu_op = 3'd6; uses_a = 1; reg_we = 1; flag_we = 1; end

            // rd = imm8 : reads no register, flags unchanged
            LDI : begin alu_op = 3'd7; alu_src_imm = 1; reg_we = 1; end

            // rd = rd + imm8 : port A reads rd
            ADDI: begin alu_op = 3'd0; alu_src_imm = 1; ra_is_rd = 1; uses_a = 1;
                        reg_we = 1; flag_we = 1; end

            // rd = MEM[rs1] : port A gives the address
            LD  : begin uses_a = 1; reg_we = 1; mem_to_reg = 1; end

            // MEM[rs1] = rd : port A = address, port B = data (rd)
            ST  : begin uses_a = 1; uses_b = 1; rb_is_rd = 1; mem_we = 1; end

            // Control flow: target = imm8, no registers read
            JMP : jump  = 1;
            BZ  : br_z  = 1;
            BNZ : br_nz = 1;

            HLT : halt  = 1;
            NOP : ;      // NOP: keep all defaults (do nothing)
            default: ;   // (all 16 opcodes are listed, so never used)
        endcase
    end

endmodule
