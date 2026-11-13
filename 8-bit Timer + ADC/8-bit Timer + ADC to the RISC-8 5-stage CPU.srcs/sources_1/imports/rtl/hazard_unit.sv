// =============================================================================
// File   : hazard_unit.sv
// Purpose: Two independent jobs, both purely combinational:
//   1) Load-use stall: if the instruction now sitting in EX is a LD and the
//      instruction now in ID needs that load's result, freeze IF/ID for one
//      cycle and insert a bubble into EX. This is the *only* hazard that
//      needs a stall -- it matches the guide's statement that "a load-use
//      stall freezes IF and ID, not MEM" (chapter 1 key insight). The data
//      genuinely is not ready yet even with forwarding (it only appears at
//      the end of MEM), so this case cannot be solved by forwarding alone.
//   2) Operand forwarding select for the EX stage's two ALU operand muxes:
//      the instruction *currently in EX* is compared against the
//      instruction one stage ahead (now in MEM / EX-MEM register) and two
//      stages ahead (now in WB / MEM-WB register); the freshest match wins.
//      This lets back-to-back dependent ALU ops run with zero stall cycles,
//      and is the forwarding the integration guide says "just works" once
//      the peripheral is wired in.
// =============================================================================
import risc8_pkg::*;

module hazard_unit (
  // ---- instruction currently in ID (about to be latched into ID/EX): used for the stall check only ----
  input  logic [REG_SEL_W-1:0] id_rs1_addr,
  input  logic                 id_uses_rs1,
  input  logic [REG_SEL_W-1:0] id_rs2_addr,
  input  logic                 id_uses_rs2,

  // ---- instruction currently in EX (the ID/EX pipeline register): drives both checks ----
  input  logic [REG_SEL_W-1:0] idex_rd_addr,
  input  logic                 idex_mem_to_reg,  // 1 = the instruction in EX is a LD (for the stall check)
  input  logic [REG_SEL_W-1:0] idex_rs1_addr,    // this instruction's own source regs (for the forwarding check)
  input  logic                 idex_uses_rs1,
  input  logic [REG_SEL_W-1:0] idex_rs2_addr,
  input  logic                 idex_uses_rs2,

  // ---- instruction currently in MEM (the EX/MEM pipeline register): one-ago forwarding source ----
  input  logic [REG_SEL_W-1:0] exmem_rd_addr,
  input  logic                 exmem_reg_we,

  // ---- instruction currently in WB (the MEM/WB pipeline register): two-ago forwarding source ----
  input  logic [REG_SEL_W-1:0] memwb_rd_addr,
  input  logic                 memwb_reg_we,

  // ---- outputs ----
  output logic       stall,          // 1 = hold PC/IF-ID, inject a bubble into ID/EX
  output fwd_sel_e    fwd_a_sel,     // EX operand-A forward select (applies to idex_rs1); see risc8_pkg.fwd_sel_e
  output fwd_sel_e    fwd_b_sel      // EX operand-B forward select (applies to idex_rs2)
);

  // ---------------------------------------------------------------------
  // 1) Load-use stall: compares the ID-stage instruction's own source
  //    registers against the destination of the LD one stage ahead of it.
  // ---------------------------------------------------------------------
  always_comb begin
    stall = idex_mem_to_reg &&
            ( (id_uses_rs1 && (id_rs1_addr == idex_rd_addr)) ||
              (id_uses_rs2 && (id_rs2_addr == idex_rd_addr)) );
  end

  // ---------------------------------------------------------------------
  // 2) Operand forwarding for EX. EX/MEM (newer) wins over MEM/WB (older)
  //    when both would otherwise match, since EX/MEM holds the more
  //    recently produced value. Compares the EX-stage instruction's own
  //    source registers against the two pipeline stages ahead of it.
  // ---------------------------------------------------------------------
  always_comb begin
    // Operand A (rs1 / address register of the instruction now in EX)
    if (idex_uses_rs1 && exmem_reg_we && (exmem_rd_addr == idex_rs1_addr))
      fwd_a_sel = FWD_EXMEM;
    else if (idex_uses_rs1 && memwb_reg_we && (memwb_rd_addr == idex_rs1_addr))
      fwd_a_sel = FWD_MEMWB;
    else
      fwd_a_sel = FWD_NONE;

    // Operand B (rs2, or ST's store-data register read via the rd field)
    if (idex_uses_rs2 && exmem_reg_we && (exmem_rd_addr == idex_rs2_addr))
      fwd_b_sel = FWD_EXMEM;
    else if (idex_uses_rs2 && memwb_reg_we && (memwb_rd_addr == idex_rs2_addr))
      fwd_b_sel = FWD_MEMWB;
    else
      fwd_b_sel = FWD_NONE;
  end

endmodule : hazard_unit
