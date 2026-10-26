// =====================================================================
//  FILE        : rtl/dmem.v
//  MODULE      : dmem
//  PROJECT     : 8-bit RISC Processor Core with 5-Stage Pipeline
// ---------------------------------------------------------------------
//  WHAT THIS FILE DOES
//    Data Memory (RAM): 256 bytes.
//      LD rd, [rs1] -> rd = MEM[R[rs1]]     (read)
//      ST rd, [rs1] -> MEM[R[rs1]] = R[rd]  (write)
//    Read  : asynchronous.  Write : synchronous (rising clock edge).
//
//  WHO USES THIS FILE
//    -> Instantiated in rtl/risc8_5stage_core.v as "dmem u_dmem (...)"
//       inside Stage 4 (MEM). Address and store data come from the
//       EX/MEM pipeline register.
//    -> tb/tb_risc8_5stage.v reads "dut.u_dmem.mem[...]" to check results.
//
//  THIS FILE CALLS : nothing (leaf module).
//
//  SYNTHESIS NOTE
//    Asynchronous read maps to distributed (LUT) RAM on Xilinx/Intel
//    FPGAs, or to flip-flops on FPGAs without LUT-RAM (e.g. iCE40).
// =====================================================================

`timescale 1ns/1ps

module dmem (
    input  wire       clk,
    input  wire       we,       // 1 = store this cycle
    input  wire [7:0] addr,     // byte address
    input  wire [7:0] wdata,    // data to store
    output wire [7:0] rdata     // data loaded
);

    reg [7:0] mem [0:255];
    integer i;

    // Clear memory at start of simulation / FPGA power-up.
    initial for (i = 0; i < 256; i = i + 1) mem[i] = 8'h00;

    // WRITE on the rising edge when we = 1.
    always @(posedge clk)
        if (we) mem[addr] <= wdata;

    // READ: combinational.
    assign rdata = mem[addr];

endmodule
