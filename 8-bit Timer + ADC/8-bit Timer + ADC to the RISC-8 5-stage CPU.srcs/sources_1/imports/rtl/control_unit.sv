// =============================================================================
// File   : control_unit.sv
// Purpose: Pure combinational instruction decoder. Looks only at the 4-bit
//          opcode field (instruction fields are sliced by the core itself)
//          and produces the ctrl_t bundle that rides down the pipeline.
//          Having this in its own module keeps risc8_5stage_core.sv focused
//          on datapath wiring instead of a giant opcode case statement.
// =============================================================================
import risc8_pkg::*;

module control_unit (
  input  opcode_e op,     // instr[15:12], already cast to the opcode_e enum by the core
  output ctrl_t   ctrl    // decoded control bundle for this instruction
);

  always_comb begin
    // Safe default = behave like NOP (no writes, no branch, no flag update).
    // This guarantees no inferred latch and means any opcode we forgot to
    // list below is harmless instead of silently corrupting state.
    // (Written as individual field assignments rather than a single '{...}
    // aggregate-pattern assignment, purely for maximum compatibility with
    // stricter SystemVerilog parsers -- both forms are equivalent here.)
    ctrl.wb_sel         = WB_SEL_ALU;
    ctrl.reg_we         = 1'b0;
    ctrl.mem_we         = 1'b0;
    ctrl.mem_to_reg     = 1'b0;
    ctrl.use_rd_as_src2 = 1'b0;
    ctrl.is_branch      = 1'b0;
    ctrl.branch_on_zero = 1'b0;
    ctrl.is_jmp         = 1'b0;
    ctrl.is_hlt         = 1'b0;
    ctrl.flags_we       = 1'b0;
    ctrl.uses_rs1       = 1'b0;
    ctrl.uses_rs2       = 1'b0;

    unique case (op)
      OP_NOP: ; // defaults already describe NOP exactly

      OP_HLT: begin
        ctrl.is_hlt = 1'b1;
      end

      OP_LDI: begin
        ctrl.wb_sel = WB_SEL_IMM;
        ctrl.reg_we = 1'b1;
      end

      OP_LD: begin
        ctrl.wb_sel     = WB_SEL_MEM;
        ctrl.reg_we     = 1'b1;
        ctrl.mem_to_reg = 1'b1;   // tells MEM stage this is a load (gates io_cs together with mem_we)
        ctrl.uses_rs1   = 1'b1;   // rs field holds the address register
      end

      OP_ST: begin
        ctrl.mem_we         = 1'b1;
        ctrl.use_rd_as_src2 = 1'b1;  // the 'rd' field names the *source* register to store, per guide convention
        ctrl.uses_rs1        = 1'b1; // rs field holds the address register
        ctrl.uses_rs2        = 1'b1; // rd field (read through port B) holds the data to store
      end

      OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR: begin
        ctrl.reg_we   = 1'b1;
        ctrl.flags_we = 1'b1;       // these five ops legitimately update {Z,C}
        ctrl.uses_rs1 = 1'b1;
        ctrl.uses_rs2 = 1'b1;
      end

      OP_SHL, OP_SHR: begin
        ctrl.reg_we   = 1'b1;
        ctrl.flags_we = 1'b1;       // shifts also update {Z,C} (C = bit shifted out)
        ctrl.uses_rs1 = 1'b1;       // single-operand: only rs1 is read
      end

      OP_MOV: begin
        ctrl.reg_we   = 1'b1;       // plain register copy, flags untouched
        ctrl.uses_rs1 = 1'b1;
      end

      OP_BZ: begin
        ctrl.is_branch      = 1'b1;
        ctrl.branch_on_zero = 1'b1;  // take the branch when Z==1
      end

      OP_BNZ: begin
        ctrl.is_branch      = 1'b1;
        ctrl.branch_on_zero = 1'b0;  // take the branch when Z==0
      end

      OP_JMP: begin
        ctrl.is_jmp = 1'b1;          // always taken, no flag dependency
      end

      default: ; // unreachable: opcode_e only has the 16 values above
    endcase
  end

endmodule : control_unit
