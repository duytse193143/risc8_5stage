// =================================================================
//  FILE        : rtl/alu.v
//  MODULE      : alu
//  PROJECT     : 8-bit RISC Processor Core with 5-Stage Pipeline
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    The ALU (Arithmetic Logic Unit) is the "calculator" of the CPU.
//    It takes two 8-bit numbers (a and b), performs the operation
//    selected by alu_op, and produces:
//        y  -> the 8-bit result
//        c  -> carry / borrow / shifted-out bit (goes to the C flag)
//        z  -> 1 when the result is zero      (goes to the Z flag)
//
//  WHO USES THIS FILE
//    -> Instantiated (called) in rtl/risc8_5stage_core.v as "alu u_alu (...)"
//       inside Stage 3 (EX) of the pipeline.
//    -> alu_op comes from module control_unit (rtl/control_unit.v), carried to EX through the ID/EX register.
//
//  THIS FILE CALLS : nothing (it is a leaf module, pure logic).
//
//  TYPE OF LOGIC   : purely combinational (no clock, no memory).
//                    The output changes as soon as an input changes.
// =====================================================================

// `timescale <time unit>/<precision>
// Used only by the simulator: "#5" in a testbench means 5 ns.
`timescale 1ns/1ps

module alu (
    input  wire [7:0] a,        // Operand A : from forwarding mux ex_opA (risc8_5stage_core.v)
    input  wire [7:0] b,        // Operand B : register value OR 8-bit immediate
    input  wire [2:0] alu_op,   // Operation select : from control_unit.v
    output reg  [7:0] y,        // 8-bit result
    output reg        c,        // Carry-out (ADD), borrow (SUB), shifted-out bit (SHL/SHR)
    output wire       z         // Zero flag : 1 when y == 0
);

    // -----------------------------------------------------------------
    // Operation codes (local constants, visible only in this module).
    // control_unit.v drives alu_op with these same numbers (0..7).
    // -----------------------------------------------------------------
    localparam ALU_ADD   = 3'd0,   // y = a + b
               ALU_SUB   = 3'd1,   // y = a - b
               ALU_AND   = 3'd2,   // y = a & b   (bitwise AND)
               ALU_OR    = 3'd3,   // y = a | b   (bitwise OR)
               ALU_XOR   = 3'd4,   // y = a ^ b   (bitwise XOR)
               ALU_SHL   = 3'd5,   // y = a << 1  (shift left by one)
               ALU_SHR   = 3'd6,   // y = a >> 1  (shift right by one)
               ALU_PASSB = 3'd7;   // y = b       (used by LDI: copy immediate)

    // -----------------------------------------------------------------
    // Main ALU logic
    // always @(*) = "re-evaluate whenever ANY input changes".
    // This describes combinational hardware (multiplexers + adders).
    // -----------------------------------------------------------------
    always @(*) begin
        // Default value for carry. Assigning a default first prevents the
        // synthesizer from creating an unwanted latch for 'c' in the
        // cases (AND, OR, XOR, PASSB) that do not set it.
        c = 1'b0;

        case (alu_op)
            // ADD: extend both operands to 9 bits ({1'b0, a}) so the 9th
            // bit of the sum captures the carry-out.
            // {c, y} is a 9-bit concatenation: c = bit 8, y = bits 7..0.
            ALU_ADD  : {c, y} = {1'b0, a} + {1'b0, b};

            // SUB: same idea. If a < b the subtraction "wraps around" and
            // bit 8 becomes 1, so c = 1 means a BORROW happened.
            ALU_SUB  : {c, y} = {1'b0, a} - {1'b0, b};

            // Bitwise logic operations. Carry is not affected (stays 0).
            ALU_AND  : y = a & b;
            ALU_OR   : y = a | b;
            ALU_XOR  : y = a ^ b;

            // SHL (logical shift left): append a 0 on the right.
            // {a, 1'b0} is 9 bits; its top bit (old a[7]) goes into c.
            ALU_SHL  : {c, y} = {a, 1'b0};

            // SHR (logical shift right): put a 0 on the left.
            // {1'b0, a} is 9 bits; its lowest bit (old a[0]) goes into c.
            ALU_SHR  : {y, c} = {1'b0, a};

            // PASS B: output operand b unchanged (LDI rd, imm8).
            ALU_PASSB: y = b;

            // Safety net for any undefined code.
            default  : y = 8'h00;
        endcase
    end

    // -----------------------------------------------------------------
    // Zero flag: continuous assignment (a simple comparator).
    // z = 1 whenever all 8 result bits are 0.
    // Used by risc8_core.v to update flag_z, which BZ / BNZ test.
    // -----------------------------------------------------------------
    assign z = (y == 8'h00);

endmodule
