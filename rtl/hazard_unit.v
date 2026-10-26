// =====================================================================
//  FILE        : rtl/hazard_unit.v
//  MODULE      : hazard_unit
//  PROJECT     : 8-bit RISC Processor Core with 5-Stage Pipeline
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Detects pipeline DATA hazards and decides how to fix them.
//    It has two jobs:
//
//    1) FORWARDING  (no time lost)
//       The instruction in EX needs a register that an OLDER
//       instruction has computed but not yet written back.
//         - Older instr is 1 ahead (in MEM) -> take value from EX/MEM
//         - Older instr is 2 ahead (in WB)  -> take value from MEM/WB
//         - Older instr is 3 ahead          -> handled by the write-
//                                              through bypass in
//                                              rtl/regfile.v
//       Select codes:  2'b00 = register value from ID/EX
//                      2'b10 = forward from EX/MEM (ALU result)
//                      2'b01 = forward from MEM/WB (final result)
//       EX/MEM has priority because it is the NEWER value.
//
//    2) LOAD-USE STALL  (1 cycle lost)
//       A load (LD) gets its data only at the END of MEM. If the very
//       next instruction needs that data in EX, it is too early even
//       with forwarding. So: freeze PC and IF/ID for one cycle and put
//       a bubble (NOP) into ID/EX. Next cycle the load is in WB and
//       forwarding from MEM/WB supplies the value.
//
//  WHO USES THIS FILE
//    -> Instantiated in rtl/risc8_5stage_core.v as
//       "hazard_unit u_hazard (...)".
//    -> Uses uses_a / uses_b produced by control_unit (rtl/control_unit.v).
//
//  THIS FILE CALLS : nothing (leaf module, purely combinational).
//
//  NOTE: CONTROL hazards (branches) are handled directly in
//        rtl/risc8_5stage_core.v by flushing IF/ID and ID/EX.
// =====================================================================

`timescale 1ns/1ps

module hazard_unit (
    // ---- Instruction in ID (Stage 2) : for load-use detection ----
    input  wire       id_valid,      // IF/ID holds a real instruction
    input  wire [2:0] id_ra_addr,    // register read on port A
    input  wire [2:0] id_rb_addr,    // register read on port B
    input  wire       id_uses_a,     // port A really used?
    input  wire       id_uses_b,     // port B really used?

    // ---- Instruction in EX (Stage 3) ----
    input  wire       ex_valid,      // ID/EX holds a real instruction
    input  wire       ex_mem_to_reg, // EX instruction is a load (LD)
    input  wire [2:0] ex_rd,         // its destination register
    input  wire [2:0] ex_ra_addr,    // registers it reads (for forwarding)
    input  wire [2:0] ex_rb_addr,
    input  wire       ex_uses_a,     // EX instruction really reads port A?
    input  wire       ex_uses_b,     // EX instruction really reads port B?

    // ---- Instruction in MEM (Stage 4) ----
    input  wire       mem_reg_we,    // will write a register
    input  wire       mem_mem_to_reg,// is a load (its data not ready in EX/MEM)
    input  wire [2:0] mem_rd,

    // ---- Instruction in WB (Stage 5) ----
    input  wire       wb_reg_we,
    input  wire [2:0] wb_rd,

    // ---- Outputs ----
    output reg  [1:0] fwd_a_sel,     // operand A source in EX
    output reg  [1:0] fwd_b_sel,     // operand B source in EX
    output wire       stall          // 1 = load-use stall this cycle
);

    // -----------------------------------------------------------------
    // 1) FORWARDING SELECT for operand A
    //    Forward only if the EX instruction really reads port A
    //    (ex_uses_a), so unused register fields never trigger it.
    // -----------------------------------------------------------------
    always @(*) begin
        if (ex_uses_a && mem_reg_we && !mem_mem_to_reg && (mem_rd == ex_ra_addr))
            fwd_a_sel = 2'b10;          // newest value: from EX/MEM
        else if (ex_uses_a && wb_reg_we && (wb_rd == ex_ra_addr))
            fwd_a_sel = 2'b01;          // older value: from MEM/WB
        else
            fwd_a_sel = 2'b00;          // no hazard: use register value
    end

    // -----------------------------------------------------------------
    // 1) FORWARDING SELECT for operand B (same rules)
    // -----------------------------------------------------------------
    always @(*) begin
        if (ex_uses_b && mem_reg_we && !mem_mem_to_reg && (mem_rd == ex_rb_addr))
            fwd_b_sel = 2'b10;
        else if (ex_uses_b && wb_reg_we && (wb_rd == ex_rb_addr))
            fwd_b_sel = 2'b01;
        else
            fwd_b_sel = 2'b00;
    end

    // -----------------------------------------------------------------
    // 2) LOAD-USE STALL
    //    LD is in EX AND the instruction in ID reads LD's destination.
    // -----------------------------------------------------------------
    assign stall = id_valid && ex_valid && ex_mem_to_reg &&
                   ((id_uses_a && (id_ra_addr == ex_rd)) ||
                    (id_uses_b && (id_rb_addr == ex_rd)));

endmodule
