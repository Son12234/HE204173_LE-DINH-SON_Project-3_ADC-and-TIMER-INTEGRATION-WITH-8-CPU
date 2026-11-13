// =============================================================================
// File   : risc8_5stage_core.sv
// Purpose: The RISC-8 5-stage pipelined CPU: IF -> ID -> EX -> MEM -> WB.
//          This is an original implementation of the 8-bit, 16-opcode,
//          8-register architecture that the integration guide's examples
//          imply (instruction mnemonics, flags, memory map, pipeline
//          hazards); the base core was not supplied by the guide, which
//          only documents the *changes* needed to attach a peripheral to an
//          already-working core (its chapter 4). The MEM-stage I/O
//          integration below reproduces that chapter's logic signal-for-
//          signal (same names: exmem_addr, exmem_store_data, io_hit,
//          io_cs...) because that *is* the required interface contract;
//          everything else in this file (fetch, decode, hazards,
//          forwarding, branch resolution) is this project's own design.
//
//          Every signal this module uses is declared once, up front, in
//          the "Signal declarations" section below, strictly before any
//          module instantiation, assign, or always block that references
//          it. Plain simulators tolerate forward references inside a
//          module (all declarations elaborate before simulation starts,
//          order-independent), but Vivado's synthesis/lint elaborator
//          does not: it flags a signal used before its textual
//          declaration (Synth 8-6901) and, if a name is then also seen
//          again at its real declaration, "already implicitly declared"
//          (Synth 8-8895). Declaring everything first avoids both.
// =============================================================================
import risc8_pkg::*;

module risc8_5stage_core #(
  parameter string          IMEM_FILE  = "program.hex", // passed down to imem (rtl/imem.sv)
  parameter int             IO_ENABLE  = 0,              // 1 = map the I/O page to the io_* port
  parameter logic [3:0]     IO_PAGE    = IO_PAGE_DEFAULT  // I/O page = addresses {IO_PAGE,4'h0}..{IO_PAGE,4'hF}
) (
  input  logic              clk,         // system clock
  input  logic              rst,         // synchronous reset, active-high
  output logic              halted,      // 1 after HLT has left the pipeline (sticky until reset)
  output logic [ADDR_W-1:0] pc_out,      // current PC (debug output)
  output logic [1:0]        flags_out,   // {Z, C} status flags (debug output)
  output logic              instr_done,  // 1 when a real (non-bubble) instruction completes WB this cycle
  // ---- I/O port: memory-mapped peripherals, driven from Stage 4 (MEM) ----
  output logic              io_cs,       // 1 = a LD/ST to the I/O page is happening this clock
  output logic              io_we,       // 1 = store, 0 = load
  output logic [3:0]        io_addr,     // register number inside the 16-byte I/O page
  output logic [7:0]        io_wdata,    // store data
  input  logic [7:0]        io_rdata     // load data coming back from the peripheral
);

  // ===========================================================================
  // Signal declarations (grouped by pipeline stage/register for readability;
  // see the file header for why every declaration lives here, before use).
  // ===========================================================================

  // ---- IF ----
  logic [ADDR_W-1:0]  pc_reg;      // the architectural program counter
  logic [INSTR_W-1:0] instr_if;    // instruction read combinationally from imem this cycle

  // ---- IF/ID pipeline register ----
  logic [INSTR_W-1:0] ifid_instr;
  logic                ifid_valid;  // 0 = this slot is a bubble (squashed or post-reset), not a real instruction

  // ---- ID ----
  opcode_e id_op;
  logic [REG_SEL_W-1:0] id_rd_field, id_rs1_field, id_rs2_field;
  logic [DATA_W-1:0]    id_imm8;
  ctrl_t                id_ctrl;      // full control word straight from control_unit
  ex_ctrl_t             id_ctrl_ex;   // id_ctrl minus use_rd_as_src2 (only ID needs it) -> what ID/EX stores
  logic [REG_SEL_W-1:0] id_src2_addr;  // ST reads its store-data register via this (rd field, not rs2)
  logic [DATA_W-1:0]    id_rdata_a, id_rdata_b;

  // ---- ID/EX pipeline register ----
  opcode_e              idex_op;
  ex_ctrl_t             idex_ctrl;
  logic                 idex_valid;
  logic [REG_SEL_W-1:0] idex_rd_addr;
  logic [REG_SEL_W-1:0] idex_rs1_addr;  // = id_rs1_field at capture time (forwarding target for operand A)
  logic [REG_SEL_W-1:0] idex_rs2_addr;  // = id_src2_addr at capture time (forwarding target for operand B)
  logic [DATA_W-1:0]    idex_rdata_a;
  logic [DATA_W-1:0]    idex_rdata_b;
  logic [DATA_W-1:0]    idex_imm8;

  // ---- hazard detection / forwarding control (shared by ID and EX) ----
  logic     stall;
  fwd_sel_e fwd_a_sel, fwd_b_sel;
  logic     hlt_in_flight;
  logic     freeze;

  // ---- EX ----
  logic [DATA_W-1:0] exmem_fwd_value;          // see the comment at its assign, further down
  logic [DATA_W-1:0] ex_operand_a, ex_operand_b;
  logic [DATA_W-1:0] alu_y_comb;
  logic               z_flag_comb, c_flag_comb;
  logic [1:0]         flags_reg;        // {Z, C} -- bit assignment matches risc8_pkg FLAG_Z / FLAG_C
  logic [DATA_W-1:0]  branch_target;
  logic               branch_taken;

  // ---- EX/MEM pipeline register ----
  mem_ctrl_t            exmem_ctrl;
  logic                 exmem_valid;
  logic [REG_SEL_W-1:0] exmem_rd_addr;
  logic [DATA_W-1:0]    exmem_alu_y;       // ALU result (used for most write-backs)
  logic [DATA_W-1:0]    exmem_addr;        // LD/ST address (= the forwarded address-register value)
  logic [DATA_W-1:0]    exmem_store_data;  // ST's data to write (= the forwarded data-register value)
  logic [DATA_W-1:0]    exmem_imm8;        // carried through for LDI's write-back value

  // ---- MEM ----
  logic              io_hit;
  logic              dmem_we;
  logic [DATA_W-1:0] dmem_rdata;
  logic [DATA_W-1:0] ld_data;
  logic [DATA_W-1:0] mem_stage_result;

  // ---- MEM/WB pipeline register ----
  wb_ctrl_t             memwb_ctrl;
  logic                 memwb_valid;
  logic [REG_SEL_W-1:0] memwb_rd_addr;
  logic [DATA_W-1:0]    memwb_wdata;

  // ===========================================================================
  // Stage 1: IF (instruction fetch)
  // ===========================================================================
  imem #(.IMEM_FILE(IMEM_FILE)) u_imem (
    .addr  (pc_reg),
    .rdata (instr_if)
  );

  // ===========================================================================
  // Stage 2: ID (instruction decode / register read)
  // ===========================================================================
  assign id_op = opcode_e'(ifid_instr[15:12]);

  assign id_rd_field  = ifid_instr[FLD_RD_HI:FLD_RD_LO];
  assign id_rs1_field = ifid_instr[FLD_RS1_HI:FLD_RS1_LO];
  assign id_rs2_field = ifid_instr[FLD_RS2_HI:FLD_RS2_LO];

  assign id_imm8 = ifid_instr[7:0];   // I-type immediate and B-type branch target share the same bit field

  control_unit u_control_unit (
    .op   (id_op),
    .ctrl (id_ctrl)
  );

  // Trim the control word to what ID/EX really has to carry (see the stage
  // views in risc8_pkg.sv). Only use_rd_as_src2 is dropped: it is consumed
  // right here in ID (id_src2_addr below) and never needed later.
  always_comb begin
    id_ctrl_ex.wb_sel         = id_ctrl.wb_sel;
    id_ctrl_ex.reg_we         = id_ctrl.reg_we;
    id_ctrl_ex.mem_we         = id_ctrl.mem_we;
    id_ctrl_ex.mem_to_reg     = id_ctrl.mem_to_reg;
    id_ctrl_ex.is_branch      = id_ctrl.is_branch;
    id_ctrl_ex.branch_on_zero = id_ctrl.branch_on_zero;
    id_ctrl_ex.is_jmp         = id_ctrl.is_jmp;
    id_ctrl_ex.is_hlt         = id_ctrl.is_hlt;
    id_ctrl_ex.flags_we       = id_ctrl.flags_we;
    id_ctrl_ex.uses_rs1       = id_ctrl.uses_rs1;
    id_ctrl_ex.uses_rs2       = id_ctrl.uses_rs2;
  end

  // For a store, the architectural source register to write to memory is
  // encoded in the 'rd' field (guide convention: "ST Rd,[Rs]" stores Rd),
  // so read-port B must fetch that field instead of the usual rs2 field.
  assign id_src2_addr = id_ctrl.use_rd_as_src2 ? id_rd_field : id_rs2_field;

  regfile u_regfile (
    .clk     (clk),
    .rst     (rst),
    .raddr_a (id_rs1_field),
    .rdata_a (id_rdata_a),
    .raddr_b (id_src2_addr),
    .rdata_b (id_rdata_b),
    .we      (memwb_ctrl.reg_we),
    .waddr   (memwb_rd_addr),
    .wdata   (memwb_wdata)
  );

  // ===========================================================================
  // Hazard detection / forwarding control (shared by ID and EX)
  // ===========================================================================
  hazard_unit u_hazard_unit (
    .id_rs1_addr     (id_rs1_field),
    .id_uses_rs1     (id_ctrl.uses_rs1),
    .id_rs2_addr     (id_src2_addr),
    .id_uses_rs2     (id_ctrl.uses_rs2),
    .idex_rd_addr    (idex_rd_addr),
    .idex_mem_to_reg (idex_ctrl.mem_to_reg),
    .idex_rs1_addr   (idex_rs1_addr),
    .idex_uses_rs1   (idex_ctrl.uses_rs1),
    .idex_rs2_addr   (idex_rs2_addr),
    .idex_uses_rs2   (idex_ctrl.uses_rs2),
    .exmem_rd_addr   (exmem_rd_addr),
    .exmem_reg_we    (exmem_ctrl.reg_we),
    .memwb_rd_addr   (memwb_rd_addr),
    .memwb_reg_we    (memwb_ctrl.reg_we),
    .stall           (stall),
    .fwd_a_sel       (fwd_a_sel),
    .fwd_b_sel       (fwd_b_sel)
  );

  // HLT handling: once an HLT instruction has been captured into ID/EX (i.e.
  // it is in EX, MEM or WB), stop refilling the front of the pipeline. HLT
  // itself is deliberately *not* tested while still in ID, so the real HLT
  // decode gets captured into ID/EX exactly once before freezing begins.
  assign hlt_in_flight = idex_ctrl.is_hlt || exmem_ctrl.is_hlt || memwb_ctrl.is_hlt || halted;

  assign freeze = stall || hlt_in_flight;

  // ===========================================================================
  // Stage 3: EX (ALU execute, branch resolution)
  // ===========================================================================
  // EX/MEM forwarding value: NOT simply exmem_alu_y. For most instructions
  // the write-back value really is the ALU result, but LDI's write-back
  // value is the immediate field (WB_SEL_IMM) -- LDI never routes its
  // immediate through the ALU at all, so exmem_alu_y for an LDI holds a
  // meaningless pass-through instead of the loaded constant. Forwarding
  // the raw ALU result in that case silently hands the consumer the wrong
  // value one cycle after every "LDI Rx,imm" immediately followed by an
  // instruction that uses Rx (a very common pattern, e.g. "LDI R1,0x13"
  // then "ST R1,[R7]"). This mirrors exactly how mem_stage_result/
  // memwb_wdata already resolve wb_sel for MEM/WB forwarding -- EX/MEM
  // forwarding never needs the WB_SEL_MEM case (that dependency is always
  // handled by the load-use stall instead, see hazard_unit.sv), so only
  // ALU vs. IMM needs to be distinguished here.
  assign exmem_fwd_value = (exmem_ctrl.wb_sel == WB_SEL_IMM) ? exmem_imm8 : exmem_alu_y;

  // Forward-select values come from the shared fwd_sel_e enum in risc8_pkg.sv.
  always_comb begin
    unique case (fwd_a_sel)
      FWD_EXMEM: ex_operand_a = exmem_fwd_value; // one instruction ago (EX/MEM)
      FWD_MEMWB: ex_operand_a = memwb_wdata;     // two instructions ago (MEM/WB)
      default:   ex_operand_a = idex_rdata_a;    // no hazard: plain register-file value
    endcase
    unique case (fwd_b_sel)
      FWD_EXMEM: ex_operand_b = exmem_fwd_value;
      FWD_MEMWB: ex_operand_b = memwb_wdata;
      default:   ex_operand_b = idex_rdata_b;
    endcase
  end

  alu u_alu (
    .op     (idex_op),
    .a      (ex_operand_a),
    .b      (ex_operand_b),
    .y      (alu_y_comb),
    .z_flag (z_flag_comb),
    .c_flag (c_flag_comb)
  );

  // Architectural flags register: updated only by instructions that
  // legitimately produce flags (see control_unit.sv's flags_we), so a
  // branch several instructions later still sees the correct, most-recent
  // Z value without needing its own forwarding path.
  always_ff @(posedge clk) begin
    if (rst)
      flags_reg <= 2'b00;
    else if (idex_valid && idex_ctrl.flags_we)
      flags_reg <= {z_flag_comb, c_flag_comb};
  end

  // Branches and jumps resolve here in EX, exactly like the guide's note
  // that a future interrupt would be "taken like a branch, flushed in EX".
  // Static "predict not-taken" scheme: IF/ID and ID/EX are both squashed
  // only when a branch/jump is actually taken, giving a 2-cycle penalty.
  assign branch_target = idex_imm8;   // target8 shares the imm8 bit field

  assign branch_taken = idex_valid &&
                         ( idex_ctrl.is_jmp ||
                           (idex_ctrl.is_branch && (flags_reg[FLAG_Z] == idex_ctrl.branch_on_zero)) );

  // ===========================================================================
  // Stage 4: MEM (data RAM / memory-mapped I-O page)
  // This block is the integration point described in guide chapters 3-5.
  // ===========================================================================
  // io_hit: is this LD/ST address inside the 16-byte I-O page?
  // (exmem_mem_we / exmem_mem_to_reg are already 0 for a bubble, so a
  // squashed instruction can never select the peripheral -- same guarantee
  // the guide calls out for its own design.)
  assign io_hit = (IO_ENABLE != 0) && (exmem_addr[7:4] == IO_PAGE);

  assign io_cs    = io_hit && (exmem_ctrl.mem_we || exmem_ctrl.mem_to_reg) && !halted;
  assign io_we    = exmem_ctrl.mem_we;
  assign io_addr  = exmem_addr[3:0];
  assign io_wdata = exmem_store_data;

  // RAM write enable: a real ST, CPU not halted, and not aimed at the I-O
  // page (I-O-page writes are consumed by the peripheral instead).
  assign dmem_we = exmem_ctrl.mem_we && !halted && !io_hit;

  dmem u_dmem (
    .clk   (clk),
    .we    (dmem_we),
    .addr  (exmem_addr),
    .wdata (exmem_store_data),
    .rdata (dmem_rdata)
  );

  // Data returned by a LD: peripheral data for the I-O page, RAM otherwise.
  assign ld_data = io_hit ? io_rdata : dmem_rdata;

  // Final write-back value, resolved here in MEM so the MEM/WB register can
  // simply latch one already-correct value instead of re-muxing in WB.
  always_comb begin
    unique case (exmem_ctrl.wb_sel)
      WB_SEL_MEM: mem_stage_result = ld_data;      // LD
      WB_SEL_IMM: mem_stage_result = exmem_imm8;   // LDI
      default:    mem_stage_result = exmem_alu_y;  // ADD/SUB/AND/OR/XOR/SHL/SHR/MOV
    endcase
  end

  // ===========================================================================
  // Stage 5: WB (register write-back) -- the actual write happens inside
  // u_regfile above (synchronous write port driven by memwb_* signals).
  // ===========================================================================

  // ===========================================================================
  // Pipeline register updates (all synchronous, active-high reset)
  // ===========================================================================

  // ---- PC ----
  always_ff @(posedge clk) begin
    if (rst)
      pc_reg <= '0;
    else if (freeze)
      pc_reg <= pc_reg;                 // hold: stall or HLT draining
    else if (branch_taken)
      pc_reg <= branch_target;          // redirect
    else
      pc_reg <= pc_reg + 1'b1;          // sequential fetch
  end

  // ---- IF/ID ----
  always_ff @(posedge clk) begin
    if (rst) begin
      ifid_instr <= '0;
      ifid_valid <= 1'b0;
    end else if (freeze) begin
      ifid_instr <= ifid_instr;         // hold: do not advance fetch
      ifid_valid <= ifid_valid;
    end else if (branch_taken) begin
      ifid_instr <= '0;                 // squash: in-flight fetch was on the wrong path
      ifid_valid <= 1'b0;
    end else begin
      ifid_instr <= instr_if;
      ifid_valid <= 1'b1;
    end
  end

  // ---- ID/EX ----
  always_ff @(posedge clk) begin
    if (rst) begin
      idex_ctrl     <= '0;
      idex_valid    <= 1'b0;
      idex_op       <= OP_NOP;
      idex_rd_addr  <= '0;
      idex_rs1_addr <= '0;
      idex_rs2_addr <= '0;
      idex_rdata_a  <= '0;
      idex_rdata_b  <= '0;
      idex_imm8     <= '0;
    end else if (freeze || branch_taken) begin
      // stall -> bubble while IF/ID holds steady; branch squash -> bubble
      // the instruction that was decoded speculatively on the wrong path.
      idex_ctrl  <= '0;
      idex_valid <= 1'b0;
    end else begin
      idex_ctrl     <= id_ctrl_ex;
      idex_valid    <= ifid_valid;
      idex_op       <= id_op;
      idex_rd_addr  <= id_rd_field;
      idex_rs1_addr <= id_rs1_field;
      idex_rs2_addr <= id_src2_addr;
      idex_rdata_a  <= id_rdata_a;
      idex_rdata_b  <= id_rdata_b;
      idex_imm8     <= id_imm8;
    end
  end

  // ---- EX/MEM (always advances: downstream stages are never stalled) ----
  always_ff @(posedge clk) begin
    if (rst) begin
      exmem_ctrl       <= '0;
      exmem_valid      <= 1'b0;
      exmem_rd_addr    <= '0;
      exmem_alu_y      <= '0;
      exmem_addr       <= '0;
      exmem_store_data <= '0;
      exmem_imm8       <= '0;
    end else begin
      // EX/MEM keeps only what MEM, forwarding and WB still read
      exmem_ctrl.wb_sel     <= idex_ctrl.wb_sel;
      exmem_ctrl.reg_we     <= idex_ctrl.reg_we;
      exmem_ctrl.mem_we     <= idex_ctrl.mem_we;
      exmem_ctrl.mem_to_reg <= idex_ctrl.mem_to_reg;
      exmem_ctrl.is_hlt     <= idex_ctrl.is_hlt;
      exmem_valid      <= idex_valid;
      exmem_rd_addr    <= idex_rd_addr;
      exmem_alu_y      <= alu_y_comb;
      exmem_addr       <= ex_operand_a;    // address register value, post-forwarding
      exmem_store_data <= ex_operand_b;    // store data, post-forwarding
      exmem_imm8       <= idex_imm8;
    end
  end

  // ---- MEM/WB ----
  always_ff @(posedge clk) begin
    if (rst) begin
      memwb_ctrl    <= '0;
      memwb_valid   <= 1'b0;
      memwb_rd_addr <= '0;
      memwb_wdata   <= '0;
    end else begin
      // MEM/WB keeps only the register write enable and HLT retirement
      // (the write-back value was already selected in MEM: memwb_wdata)
      memwb_ctrl.reg_we <= exmem_ctrl.reg_we;
      memwb_ctrl.is_hlt <= exmem_ctrl.is_hlt;
      memwb_valid   <= exmem_valid;
      memwb_rd_addr <= exmem_rd_addr;
      memwb_wdata   <= mem_stage_result;
    end
  end

  // ---- sticky 'halted' flag: set once HLT retires (reaches WB), never cleared except by reset ----
  always_ff @(posedge clk) begin
    if (rst)
      halted <= 1'b0;
    else if (memwb_valid && memwb_ctrl.is_hlt)
      halted <= 1'b1;
  end

  // ===========================================================================
  // Debug / observability outputs
  // ===========================================================================
  assign pc_out     = pc_reg;
  assign flags_out  = flags_reg;
  assign instr_done = memwb_valid;   // pulses once per real (non-bubble) instruction retiring

endmodule : risc8_5stage_core
