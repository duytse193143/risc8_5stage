// =====================================================================
//  FILE        : rtl/regfile.v
//  MODULE      : regfile
//  PROJECT     : 8-bit RISC Processor Core with 5-Stage Pipeline
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Holds the 8 general-purpose registers R0..R7 (8 bits each).
//      * 2 READ ports (A, B)  -> read in Stage 2 (ID)
//      * 1 WRITE port         -> written by Stage 5 (WB)
//
//    WRITE-THROUGH BYPASS (new compared with the 3-stage design)
//      In a 5-stage pipeline an instruction in ID can read a register
//      in the SAME cycle that an older instruction in WB is writing it.
//      Without help, ID would read the old value. So each read port
//      checks: "is WB writing the register I am reading right now?"
//      If yes, it outputs wr_data directly instead of the stored value.
//      This removes the 3-instruction-apart data hazard.
//
//  WHO USES THIS FILE
//    -> Instantiated in rtl/risc8_5stage_core.v as "regfile u_rf (...)".
//    -> tb/tb_risc8_5stage.v reads "dut.u_rf.r[...]" to check results.
//
//  THIS FILE CALLS : nothing (leaf module).
// =====================================================================

`timescale 1ns/1ps

module regfile (
    input  wire       clk,      // System clock
    input  wire       rst,      // Synchronous reset, active high
    // ---- Read port A (Stage 2, ID) ----
    input  wire [2:0] ra_addr,
    output wire [7:0] ra_data,
    // ---- Read port B (Stage 2, ID) ----
    input  wire [2:0] rb_addr,
    output wire [7:0] rb_data,
    // ---- Write port (Stage 5, WB) ----
    input  wire       we,       // write enable
    input  wire [2:0] wr_addr,  // destination register
    input  wire [7:0] wr_data   // value to write
);

    // 8 registers x 8 bits: r[0] = R0 ... r[7] = R7
    reg [7:0] r [0:7];
    integer i;

    // -----------------------------------------------------------------
    // WRITE: synchronous, on the rising clock edge
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            for (i = 0; i < 8; i = i + 1) r[i] <= 8'h00;   // clear all
        else if (we)
            r[wr_addr] <= wr_data;
    end

    // -----------------------------------------------------------------
    // READ with write-through bypass (combinational)
    //   If WB is writing the same register this cycle -> give the NEW
    //   value (wr_data). Otherwise give the stored value.
    // -----------------------------------------------------------------
    assign ra_data = (we && (wr_addr == ra_addr)) ? wr_data : r[ra_addr];
    assign rb_data = (we && (wr_addr == rb_addr)) ? wr_data : r[rb_addr];

endmodule
