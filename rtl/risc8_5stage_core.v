// ========
//  FILE        : rtl/risc8_5stage_core.v
//  MODULE      : risc8_5stage_core   (TOP-LEVEL of the processor)
//  PROJECT     : 8-bit RISC Processor Core with 5-Stage Pipeline
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Connects every block into a classic 5-stage pipelined CPU:
//
//      Stage 1  IF  : fetch instruction at PC
//      Stage 2  ID  : decode, read registers
//      Stage 3  EX  : forwarding, ALU, flags, resolve branches
//      Stage 4  MEM : load / store to data memory
//      Stage 5  WB  : write result to register file
//
//    Pipeline registers between stages:
//      IF/ID  ->  ID/EX  ->  EX/MEM  ->  MEM/WB
//
//    HAZARD HANDLING
//      Data hazards    : forwarding EX/MEM->EX and MEM/WB->EX
//                        (rtl/hazard_unit.v) + write-through bypass
//                        in the register file (rtl/regfile.v)
//      Load-use hazard : 1-cycle stall (rtl/hazard_unit.v)
//      Control hazard  : branch resolved in EX; the 2 younger
//                        instructions (in IF/ID and ID/EX) are flushed
//                        -> 2-cycle penalty per taken branch
//      HLT             : when HLT reaches EX, fetching stops and the
//                        younger instructions are squashed; the older
//                        ones drain through MEM and WB, then 'halted'=1
//
//  MODULES CALLED (instantiated) IN THIS FILE
//    imem          from rtl/imem.v          -> u_imem    (Stage 1, IF)
//    control_unit  from rtl/control_unit.v  -> u_ctrl    (Stage 2, ID)
//    regfile       from rtl/regfile.v       -> u_rf      (read in ID, write in WB)
//    hazard_unit   from rtl/hazard_unit.v   -> u_hazard  (ID + EX)
//    alu           from rtl/alu.v           -> u_alu     (Stage 3, EX)
//    dmem          from rtl/dmem.v          -> u_dmem    (Stage 4, MEM)
//
//  WHO USES THIS FILE
//    -> tb/tb_risc8_5stage.v instantiates it as "dut".
//
//  NAMING CONVENTION
//    if_*   : signal belongs to Stage 1      ifid_*  : IF/ID register
//    id_*   : signal belongs to Stage 2      idex_*  : ID/EX register
//    ex_*   : signal belongs to Stage 3      exmem_* : EX/MEM register
//    mem_*  : signal belongs to Stage 4      memwb_* : MEM/WB register
//    wb_*   : signal belongs to Stage 5
// =====================================================================

`timescale 1ns/1ps

module risc8_5stage_core #(
    parameter IMEM_FILE = "program.hex"   // passed down to imem (rtl/imem.v)
) (
    input  wire       clk,      // system clock
    input  wire       rst,      // synchronous reset, active high
    output reg        halted,     // 1 after HLT has left the pipeline
    output wire [7:0] pc_out,     // current PC            (debug output)
    output wire [1:0] flags_out,  // {Z, C} status flags   (debug output)
    output wire       instr_done  // 1 when an instruction completes WB (debug output)
);

    // =================================================================
    //  STAGE 1 : INSTRUCTION FETCH (IF)
    // =================================================================
    reg  [7:0]  pc;           // program counter
    wire [15:0] if_instr;     // instruction fetched this cycle

    // ---- CALL: module imem from rtl/imem.v ----
    imem #(.INIT_FILE(IMEM_FILE)) u_imem (
        .addr  (pc),
        .instr (if_instr)
    );

    // ---- IF/ID pipeline register ----
    reg [15:0] ifid_instr;    // instruction waiting to be decoded
    reg        ifid_valid;    // 0 = bubble

    // =================================================================
    //  STAGE 2 : INSTRUCTION DECODE (ID)
    // =================================================================

    // ---- Instruction fields ----
    // [15:12] opcode | [11:9] rd | [8:6] rs1 | [5:3] rs2 | [7:0] imm8
    wire [3:0] id_opcode = ifid_instr[15:12];
    wire [2:0] id_rd     = ifid_instr[11:9];
    wire [2:0] id_rs1    = ifid_instr[8:6];
    wire [2:0] id_rs2    = ifid_instr[5:3];
    wire [7:0] id_imm8   = ifid_instr[7:0];

    // ---- Control signals from the decoder ----
    wire [2:0] id_alu_op;
    wire id_alu_src_imm, id_ra_is_rd, id_rb_is_rd, id_uses_a, id_uses_b,
         id_reg_we, id_mem_to_reg, id_mem_we, id_flag_we,
         id_jump, id_br_z, id_br_nz, id_halt;

    // ---- CALL: module control_unit from rtl/control_unit.v ----
    control_unit u_ctrl (
        .opcode      (id_opcode),
        .alu_op      (id_alu_op),
        .alu_src_imm (id_alu_src_imm),
        .ra_is_rd    (id_ra_is_rd),
        .rb_is_rd    (id_rb_is_rd),
        .uses_a      (id_uses_a),      // -> hazard_unit (load-use check)
        .uses_b      (id_uses_b),      // -> hazard_unit (load-use check)
        .reg_we      (id_reg_we),
        .mem_to_reg  (id_mem_to_reg),
        .mem_we      (id_mem_we),
        .flag_we     (id_flag_we),
        .jump        (id_jump),
        .br_z        (id_br_z),
        .br_nz       (id_br_nz),
        .halt        (id_halt)
    );

    // ---- Register read addresses ----
    // ADDI reads rd on port A; ST reads rd (store data) on port B.
    wire [2:0] id_ra_addr = id_ra_is_rd ? id_rd : id_rs1;
    wire [2:0] id_rb_addr = id_rb_is_rd ? id_rd : id_rs2;
    wire [7:0] id_ra_data, id_rb_data;

    // ---- MEM/WB register + write-back signals (declared early because
    //      the register file write port uses them) ----
    reg        memwb_valid;
    reg        memwb_reg_we;
    reg  [2:0] memwb_rd;
    reg  [7:0] memwb_data;
    reg        memwb_halt;
    wire [7:0] wb_data = memwb_data;   // Stage 5 result

    // ---- CALL: module regfile from rtl/regfile.v ----
    // Read in ID (Stage 2), written in WB (Stage 5).
    regfile u_rf (
        .clk     (clk),
        .rst     (rst),
        .ra_addr (id_ra_addr), .ra_data (id_ra_data),
        .rb_addr (id_rb_addr), .rb_data (id_rb_data),
        // ===== STAGE 5 : WRITE-BACK (WB) =====
        .we      (memwb_reg_we),
        .wr_addr (memwb_rd),
        .wr_data (wb_data)
    );

    // ---- ID/EX pipeline register ----
    reg        idex_valid;
    reg  [2:0] idex_alu_op;
    reg        idex_alu_src_imm, idex_uses_a, idex_uses_b;
    reg        idex_reg_we, idex_mem_to_reg, idex_mem_we, idex_flag_we;
    reg        idex_jump, idex_br_z, idex_br_nz, idex_halt;
    reg  [2:0] idex_rd, idex_ra_addr, idex_rb_addr;
    reg  [7:0] idex_ra_data, idex_rb_data, idex_imm;

    // ---- EX/MEM pipeline register (declared early: used by forwarding)
    reg        exmem_valid;
    reg        exmem_reg_we, exmem_mem_to_reg, exmem_mem_we, exmem_halt;
    reg  [2:0] exmem_rd;
    reg  [7:0] exmem_alu_y;       // ALU result
    reg  [7:0] exmem_addr;        // memory address (R[rs1]) for LD / ST
    reg  [7:0] exmem_store_data;  // data to store (R[rd]) for ST

    // =================================================================
    //  HAZARD UNIT (forwarding select + load-use stall)
    // =================================================================
    wire [1:0] fwd_a_sel, fwd_b_sel;
    wire       stall;

    // ---- CALL: module hazard_unit from rtl/hazard_unit.v ----
    hazard_unit u_hazard (
        // instruction in ID
        .id_valid       (ifid_valid),
        .id_ra_addr     (id_ra_addr),
        .id_rb_addr     (id_rb_addr),
        .id_uses_a      (id_uses_a),
        .id_uses_b      (id_uses_b),
        // instruction in EX
        .ex_valid       (idex_valid),
        .ex_mem_to_reg  (idex_mem_to_reg),
        .ex_rd          (idex_rd),
        .ex_ra_addr     (idex_ra_addr),
        .ex_rb_addr     (idex_rb_addr),
        .ex_uses_a      (idex_uses_a),
        .ex_uses_b      (idex_uses_b),
        // instruction in MEM
        .mem_reg_we     (exmem_reg_we),
        .mem_mem_to_reg (exmem_mem_to_reg),
        .mem_rd         (exmem_rd),
        // instruction in WB
        .wb_reg_we      (memwb_reg_we),
        .wb_rd          (memwb_rd),
        // results
        .fwd_a_sel      (fwd_a_sel),
        .fwd_b_sel      (fwd_b_sel),
        .stall          (stall)
    );

    // =================================================================
    //  STAGE 3 : EXECUTE (EX)
    // =================================================================

    // ---- Forwarding multiplexers (select codes from hazard_unit) ----
    //   2'b10 -> EX/MEM ALU result   (instruction 1 ahead)
    //   2'b01 -> MEM/WB result       (instruction 2 ahead)
    //   2'b00 -> value read in ID
    wire [7:0] ex_opA = (fwd_a_sel == 2'b10) ? exmem_alu_y :
                        (fwd_a_sel == 2'b01) ? wb_data     : idex_ra_data;
    wire [7:0] ex_opB = (fwd_b_sel == 2'b10) ? exmem_alu_y :
                        (fwd_b_sel == 2'b01) ? wb_data     : idex_rb_data;

    // ---- ALU operand B: immediate or register ----
    wire [7:0] ex_alu_b = idex_alu_src_imm ? idex_imm : ex_opB;
    wire [7:0] ex_alu_y;
    wire       ex_alu_c, ex_alu_z;

    // ---- CALL: module alu from rtl/alu.v ----
    alu u_alu (
        .a      (ex_opA),
        .b      (ex_alu_b),
        .alu_op (idex_alu_op),
        .y      (ex_alu_y),
        .c      (ex_alu_c),
        .z      (ex_alu_z)
    );

    // ---- Status flags (written at the end of EX) ----
    reg flag_z, flag_c;

    // ---- Branch resolution in EX ----
    // The flags were set by the previous instruction during its EX
    // cycle, so they are already correct here.
    wire take_branch = idex_valid &&
                       (idex_jump || (idex_br_z && flag_z) || (idex_br_nz && !flag_z));
    wire [7:0] branch_target = idex_imm;

    // HLT reached EX: stop fetching and squash younger instructions.
    wire ex_halt = idex_valid && idex_halt;
    reg  draining;                          // 1 = HLT seen, waiting for it to reach WB
    wire fetch_stop = draining || ex_halt;

    // =================================================================
    //  STAGE 4 : MEMORY ACCESS (MEM)
    // =================================================================
    wire [7:0] mem_rdata;
    wire       mem_we = exmem_mem_we && !halted;   // already gated by 'valid'

    // ---- CALL: module dmem from rtl/dmem.v ----
    dmem u_dmem (
        .clk   (clk),
        .we    (mem_we),
        .addr  (exmem_addr),
        .wdata (exmem_store_data),
        .rdata (mem_rdata)
    );

    // Result leaving MEM: loaded data for LD, ALU result otherwise.
    wire [7:0] mem_result = exmem_mem_to_reg ? mem_rdata : exmem_alu_y;

    // =================================================================
    //  SEQUENTIAL LOGIC : all pipeline registers, PC, flags, halt
    // =================================================================
    always @(posedge clk) begin
        if (rst) begin
            // ---------------- RESET ----------------
            pc          <= 8'h00;
            ifid_instr  <= 16'h0000;  ifid_valid  <= 1'b0;
            idex_valid  <= 1'b0;
            idex_alu_op <= 3'd0; idex_alu_src_imm <= 1'b0;
            idex_uses_a <= 1'b0; idex_uses_b <= 1'b0;
            idex_reg_we <= 1'b0; idex_mem_to_reg <= 1'b0; idex_mem_we <= 1'b0;
            idex_flag_we <= 1'b0; idex_jump <= 1'b0; idex_br_z <= 1'b0;
            idex_br_nz <= 1'b0; idex_halt <= 1'b0;
            idex_rd <= 3'd0; idex_ra_addr <= 3'd0; idex_rb_addr <= 3'd0;
            idex_ra_data <= 8'h00; idex_rb_data <= 8'h00; idex_imm <= 8'h00;
            exmem_valid <= 1'b0; exmem_reg_we <= 1'b0; exmem_mem_to_reg <= 1'b0;
            exmem_mem_we <= 1'b0; exmem_halt <= 1'b0; exmem_rd <= 3'd0;
            exmem_alu_y <= 8'h00; exmem_addr <= 8'h00; exmem_store_data <= 8'h00;
            memwb_valid <= 1'b0; memwb_reg_we <= 1'b0; memwb_rd <= 3'd0;
            memwb_data  <= 8'h00; memwb_halt <= 1'b0;
            flag_z <= 1'b0; flag_c <= 1'b0;
            draining <= 1'b0; halted <= 1'b0;

        end else if (!halted) begin

            // ======== PC and IF/ID register (Stage 1 -> 2) ========
            // Priority: branch flush > halt > load-use stall > normal
            if (take_branch) begin
                pc         <= branch_target;   // redirect fetch
                ifid_instr <= 16'h0000;        // flush wrong-path instr
                ifid_valid <= 1'b0;
            end else if (fetch_stop) begin
                ifid_instr <= 16'h0000;        // HLT: fetch nothing more
                ifid_valid <= 1'b0;            // (PC is frozen)
            end else if (stall) begin
                // load-use stall: keep PC and IF/ID unchanged
            end else begin
                pc         <= pc + 8'd1;       // normal sequential fetch
                ifid_instr <= if_instr;
                ifid_valid <= 1'b1;
            end

            // ======== ID/EX register (Stage 2 -> 3) ========
            if (take_branch || fetch_stop || stall) begin
                // Insert a bubble: the instruction in ID is either on the
                // wrong path (branch / HLT) or must wait (stall).
                idex_valid <= 1'b0;
            end else begin
                idex_valid       <= ifid_valid;
                idex_alu_op      <= id_alu_op;
                idex_alu_src_imm <= id_alu_src_imm;
                idex_uses_a      <= id_uses_a;
                idex_uses_b      <= id_uses_b;
                idex_reg_we      <= id_reg_we;
                idex_mem_to_reg  <= id_mem_to_reg;
                idex_mem_we      <= id_mem_we;
                idex_flag_we     <= id_flag_we;
                idex_jump        <= id_jump;
                idex_br_z        <= id_br_z;
                idex_br_nz       <= id_br_nz;
                idex_halt        <= id_halt;
                idex_rd          <= id_rd;
                idex_ra_addr     <= id_ra_addr;
                idex_rb_addr     <= id_rb_addr;
                idex_ra_data     <= id_ra_data;
                idex_rb_data     <= id_rb_data;
                idex_imm         <= id_imm8;
            end

            // ======== EX/MEM register (Stage 3 -> 4) ========
            // Control bits are ANDed with idex_valid so a bubble can
            // never write a register or memory.
            exmem_valid      <= idex_valid;
            exmem_reg_we     <= idex_valid && idex_reg_we;
            exmem_mem_to_reg <= idex_valid && idex_mem_to_reg;
            exmem_mem_we     <= idex_valid && idex_mem_we;
            exmem_halt       <= ex_halt;
            exmem_rd         <= idex_rd;
            exmem_alu_y      <= ex_alu_y;
            exmem_addr       <= ex_opA;    // address  = R[rs1] (forwarded)
            exmem_store_data <= ex_opB;    // ST data  = R[rd]  (forwarded)

            // Flags are updated at the end of EX.
            if (idex_valid && idex_flag_we) begin
                flag_z <= ex_alu_z;
                flag_c <= ex_alu_c;
            end

            // Remember that HLT has been seen.
            if (ex_halt) draining <= 1'b1;

            // ======== MEM/WB register (Stage 4 -> 5) ========
            memwb_valid  <= exmem_valid;
            memwb_reg_we <= exmem_reg_we;
            memwb_rd     <= exmem_rd;
            memwb_data   <= mem_result;
            memwb_halt   <= exmem_halt;

            // ======== HALT: HLT has reached WB, pipeline is empty ========
            if (memwb_halt) halted <= 1'b1;

        end else begin
            // ---------------- HALTED: freeze ----------------
            memwb_reg_we <= 1'b0;
        end
    end

    // Debug outputs (useful on an FPGA board: connect to LEDs)
    assign pc_out     = pc;
    assign flags_out  = {flag_z, flag_c};
    assign instr_done = memwb_valid;

endmodule
