// =============================================================================
// File   : regfile.sv
// Purpose: 8 general-purpose 8-bit registers (R0..R7), 2 combinational read
//          ports (used by ID) and 1 synchronous write port (used by WB).
//          Write-then-read in the same cycle forwards the new value out of
//          the read ports (standard register-file bypass), which keeps WB
//          writing back to a register that ID reads in the same cycle correct
//          without needing an extra forwarding path for that one case.
// =============================================================================
import risc8_pkg::*;

module regfile (
  input  logic                    clk,
  input  logic                    rst,          // synchronous, active-high (matches the core)
  // read port A
  input  logic [REG_SEL_W-1:0]    raddr_a,
  output logic [DATA_W-1:0]       rdata_a,
  // read port B
  input  logic [REG_SEL_W-1:0]    raddr_b,
  output logic [DATA_W-1:0]       rdata_b,
  // write port (from WB stage)
  input  logic                    we,
  input  logic [REG_SEL_W-1:0]    waddr,
  input  logic [DATA_W-1:0]       wdata
);

  logic [DATA_W-1:0] regs [NUM_REGS];   // the 8 architectural registers

  // Synchronous write: only WB ever writes, one register per clock.
  always_ff @(posedge clk) begin
    if (rst) begin
      // Reset every register to 0 so simulation starts from a known state
      // (firmware is also expected to explicitly init R0 = 0 before using
      // it as the "zero operand" idiom, e.g. ADD R4,R7,R0).
      for (int i = 0; i < NUM_REGS; i++) regs[i] <= '0;
    end else if (we) begin
      regs[waddr] <= wdata;
    end
  end

  // Combinational reads with same-cycle write-through: if the write port is
  // targeting the same register a read port is asking for this cycle, hand
  // out the new value instead of the stale one still sitting in 'regs'.
  always_comb begin
    rdata_a = (we && (waddr == raddr_a)) ? wdata : regs[raddr_a];
    rdata_b = (we && (waddr == raddr_b)) ? wdata : regs[raddr_b];
  end

endmodule : regfile
