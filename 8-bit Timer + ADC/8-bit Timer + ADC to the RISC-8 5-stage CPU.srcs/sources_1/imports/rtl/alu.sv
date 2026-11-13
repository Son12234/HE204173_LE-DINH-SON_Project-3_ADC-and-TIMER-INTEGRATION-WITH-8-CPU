// =============================================================================
// File   : alu.sv
// Purpose: Combinational 8-bit ALU for the RISC-8 EX stage. Pure combinational
//          logic (always_comb) -> synthesizes to LUT logic, no clock involved.
// =============================================================================
import risc8_pkg::*;   // bring in opcode_e and the DATA_W constant

module alu (
  input  opcode_e         op,       // which operation to perform (also doubles as ALU-op select)
  input  logic [DATA_W-1:0] a,      // operand A (rs1, or the value being shifted/moved)
  input  logic [DATA_W-1:0] b,      // operand B (rs2; unused by single-operand ops)
  output logic [DATA_W-1:0] y,      // ALU result
  output logic              z_flag, // 1 when y == 0
  output logic              c_flag  // carry-out / borrow-not / shift-out bit
);

  // 9-bit intermediate so add/sub carry-out is just bit[8], no extra compare needed
  logic [DATA_W:0] add_ext, sub_ext;

  always_comb begin
    // Default so every branch of the case has a defined value (avoids an
    // inferred latch, which would fail synthesis/lint).
    y       = '0;
    c_flag  = 1'b0;
    add_ext = {1'b0, a} + {1'b0, b};
    sub_ext = {1'b0, a} - {1'b0, b};

    unique case (op)
      OP_ADD: begin
        y      = add_ext[DATA_W-1:0];
        c_flag = add_ext[DATA_W];        // carry out of bit 7
      end
      OP_SUB: begin
        y      = sub_ext[DATA_W-1:0];
        c_flag = ~sub_ext[DATA_W];       // C = 1 means "no borrow" (a >= b), standard convention
      end
      OP_AND: begin
        y      = a & b;
        c_flag = 1'b0;                    // logical ops always clear carry
      end
      OP_OR: begin
        y      = a | b;
        c_flag = 1'b0;
      end
      OP_XOR: begin
        y      = a ^ b;
        c_flag = 1'b0;
      end
      OP_SHL: begin
        y      = {a[DATA_W-2:0], 1'b0};   // shift left by one, fill LSB with 0
        c_flag = a[DATA_W-1];             // bit shifted out
      end
      OP_SHR: begin
        y      = {1'b0, a[DATA_W-1:1]};   // shift right by one, fill MSB with 0
        c_flag = a[0];                    // bit shifted out
      end
      // MOV / LD-address-passthrough / default: just forward operand A,
      // carry held at 0 (flags are not architecturally updated by these
      // ops anyway -- the core only latches flags_reg for flag-producing
      // opcodes, see risc8_5stage_core.sv).
      default: begin
        y      = a;
        c_flag = 1'b0;
      end
    endcase

    z_flag = (y == '0);
  end

endmodule : alu
