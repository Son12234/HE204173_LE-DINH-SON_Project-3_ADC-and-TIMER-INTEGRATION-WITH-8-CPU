// =============================================================================
// File   : risc8_pkg.sv
// Project: RISC-8 5-stage CPU + 8-bit Timer/ADC integration
// Purpose: Single shared definition of the RISC-8 instruction set so that the
//          core, the control unit, the peripheral register map and the UVM
//          testbench all agree on opcode values, field positions and the
//          memory-mapped I/O page. Keeping this in one package avoids the
//          classic bug where RTL and testbench quietly drift apart.
// =============================================================================
package risc8_pkg;

  // ---------------------------------------------------------------------
  // Datapath widths
  // ---------------------------------------------------------------------
  localparam int DATA_W   = 8;                 // register / ALU / memory data width
  localparam int ADDR_W   = 8;                 // PC width and data-memory address width
  localparam int INSTR_W  = 16;                // instruction word width
  localparam int REG_SEL_W = 3;                // 3-bit register select -> 8 registers R0..R7
  localparam int NUM_REGS = 8;

  // ---------------------------------------------------------------------
  // Opcode field: instr[15:12]. All 16 encodings are used (see guide
  // chapter 1: "no free opcode for a return-from-interrupt instruction").
  // ---------------------------------------------------------------------
  typedef enum logic [3:0] {
    OP_NOP  = 4'h0,  // no operation; spare operand bits reserved for a future EI/DI/RETI encoding
    OP_HLT  = 4'h1,  // halt: freeze the pipeline, assert 'halted'
    OP_LDI  = 4'h2,  // Rd <= imm8                         (I-type)
    OP_LD   = 4'h3,  // Rd <= MEM[Rs]  (or I/O if Rs is in the I/O page) (M-type)
    OP_ST   = 4'h4,  // MEM[Rs] <= Rd  (or I/O)                          (M-type, Rd = data src)
    OP_ADD  = 4'h5,  // Rd <= Rs1 + Rs2 ; updates Z,C                    (R-type)
    OP_SUB  = 4'h6,  // Rd <= Rs1 - Rs2 ; updates Z,C (C = NOT borrow)   (R-type)
    OP_AND  = 4'h7,  // Rd <= Rs1 & Rs2 ; updates Z, clears C            (R-type)
    OP_OR   = 4'h8,  // Rd <= Rs1 | Rs2 ; updates Z, clears C            (R-type)
    OP_XOR  = 4'h9,  // Rd <= Rs1 ^ Rs2 ; updates Z, clears C            (R-type)
    OP_SHL  = 4'hA,  // Rd <= Rs1 << 1  ; C = bit7 shifted out           (M-type)
    OP_SHR  = 4'hB,  // Rd <= Rs1 >> 1  ; C = bit0 shifted out           (M-type)
    OP_MOV  = 4'hC,  // Rd <= Rs1       ; flags unchanged                (M-type)
    OP_BZ   = 4'hD,  // if (Z)  PC <= target8                            (B-type)
    OP_BNZ  = 4'hE,  // if (!Z) PC <= target8                            (B-type)
    OP_JMP  = 4'hF   // PC <= target8  (unconditional)                   (B-type)
  } opcode_e;

  // ---------------------------------------------------------------------
  // Instruction field positions (fixed regardless of instruction type, so
  // decode never needs to know the type before slicing bits).
  //   R-type : [15:12]=op [11:9]=rd  [8:6]=rs1 [5:3]=rs2 [2:0]=unused
  //   M-type : [15:12]=op [11:9]=rd  [8:6]=rs  [5:0]=unused
  //            (for ST, the 'rd' field names the *source* register, not a
  //             destination -- see the guide's "ST Rd,[Rs]" convention)
  //   I-type : [15:12]=op [11:9]=rd  [8]=unused [7:0]=imm8
  //   B-type : [15:12]=op [11:8]=unused [7:0]=target8
  // ---------------------------------------------------------------------
  localparam int FLD_RD_HI  = 11;
  localparam int FLD_RD_LO  = 9;
  localparam int FLD_RS1_HI = 8;
  localparam int FLD_RS1_LO = 6;
  localparam int FLD_RS2_HI = 5;
  localparam int FLD_RS2_LO = 3;

  // ---------------------------------------------------------------------
  // Flags: flags_out[1:0] = {Z, C}, exactly as named in the integration
  // guide's core port list.
  // ---------------------------------------------------------------------
  localparam int FLAG_Z = 1;
  localparam int FLAG_C = 0;

  // ---------------------------------------------------------------------
  // Memory-mapped I/O page (guide chapter 2). Default page = 4'hF, i.e.
  // addresses 8'hF0-8'hFF; RAM underneath stays addressable 8'h00-8'hEF.
  // ---------------------------------------------------------------------
  localparam logic [3:0] IO_PAGE_DEFAULT = 4'hF;

  // Register offsets inside the 16-byte I/O page (low nibble of the address)
  localparam logic [3:0] REG_TMR_CTRL   = 4'h0;
  localparam logic [3:0] REG_TMR_PRESC  = 4'h1;
  localparam logic [3:0] REG_TMR_LOAD   = 4'h2;
  localparam logic [3:0] REG_TMR_CMP    = 4'h3;
  localparam logic [3:0] REG_TMR_CNT    = 4'h4;
  localparam logic [3:0] REG_ADC_CTRL   = 4'h5;
  localparam logic [3:0] REG_ADC_SMP    = 4'h6;
  localparam logic [3:0] REG_ADC_DIV    = 4'h7;
  localparam logic [3:0] REG_ADC_THR_LO = 4'h8;
  localparam logic [3:0] REG_ADC_THR_HI = 4'h9;
  localparam logic [3:0] REG_ADC_DATA   = 4'hA;
  localparam logic [3:0] REG_ADC_RCH    = 4'hB;
  localparam logic [3:0] REG_ADC_STAT   = 4'hC;
  localparam logic [3:0] REG_IRQ_EN     = 4'hD;
  localparam logic [3:0] REG_IRQ_STAT   = 4'hE;
  localparam logic [3:0] REG_ID         = 4'hF;

  // Fixed silicon-ID value returned by a read of REG_ID (0xFF)
  localparam logic [7:0] PERIPH_ID_VALUE = 8'hA8;

  // IRQ_STAT / IRQ_EN bit map (cross-checked against every worked hex
  // example in the integration guide: 0x07=OVF|CMP|EOC, 0x0C=EOC|WD,
  // 0x04=EOC alone)
  localparam int IRQ_BIT_TMR_OVF = 0;
  localparam int IRQ_BIT_TMR_CMP = 1;
  localparam int IRQ_BIT_ADC_EOC = 2;
  localparam int IRQ_BIT_ADC_WD  = 3;

  // ADC_CTRL bit map
  localparam int ADC_CTRL_BIT_EN    = 0;
  localparam int ADC_CTRL_BIT_START = 1;
  // TRIG_SEL = ADC_CTRL[3:2] : 0=software START only, 1=timer-overflow trigger
  localparam int ADC_CTRL_TRIGSEL_LO = 2;
  localparam int ADC_CTRL_TRIGSEL_HI = 3;
  // CH = ADC_CTRL[5:4] : selects one of 4 analog input channels
  localparam int ADC_CTRL_CH_LO = 4;
  localparam int ADC_CTRL_CH_HI = 5;

  // ADC_STAT bit map
  localparam int ADC_STAT_LEVEL_LO = 0;   // [3:0] = FIFO fill level
  localparam int ADC_STAT_LEVEL_HI = 3;
  localparam int ADC_STAT_BIT_EMPTY = 4;
  localparam int ADC_STAT_BIT_FULL  = 5;
  localparam int ADC_STAT_BIT_BUSY  = 6;

  // ADC_RCH bit map
  localparam int ADC_RCH_CH_LO    = 0;    // [1:0] channel of the oldest FIFO entry
  localparam int ADC_RCH_CH_HI    = 1;
  localparam int ADC_RCH_BIT_VALID = 7;

  // TMR_CTRL bit map
  localparam int TMR_CTRL_BIT_EN      = 0;
  localparam int TMR_CTRL_BIT_ONESHOT = 1;

  // FIFO depth (guide: "8-entry FIFO")
  localparam int FIFO_DEPTH = 8;

  // ---------------------------------------------------------------------
  // Forward-select encoding, shared by hazard_unit.sv (which produces it)
  // and risc8_5stage_core.sv (which consumes it in the EX operand muxes).
  // Keeping it here instead of as separate localparams in each file means
  // the two can never silently drift out of sync.
  //   NONE  = no forwarding, use the plain register-file read value
  //   EXMEM = forward from EX/MEM (result produced one instruction ago)
  //   MEMWB = forward from MEM/WB (result produced two instructions ago)
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    FWD_NONE  = 2'b00,
    FWD_EXMEM = 2'b01,
    FWD_MEMWB = 2'b10
  } fwd_sel_e;

  // ---------------------------------------------------------------------
  // Control-unit output: everything the ID stage decides about an
  // instruction, bundled into one packed struct so it can ride down the
  // pipeline registers as a single field instead of a dozen loose wires.
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {
    WB_SEL_ALU,   // write-back value = ALU result               (most instructions)
    WB_SEL_MEM,   // write-back value = data/I-O read result      (LD only)
    WB_SEL_IMM    // write-back value = the immediate field       (LDI only)
  } wb_sel_e;

  typedef struct packed {
    wb_sel_e wb_sel;         // selects what gets written back to rd
    logic    reg_we;         // 1 = this instruction writes a destination register
    logic    mem_we;         // 1 = ST (store to data memory / I-O page)
    logic    mem_to_reg;     // 1 = LD (identical meaning to the guide's exmem_mem_to_reg)
    logic    use_rd_as_src2; // 1 = ST, so read-port B must fetch the *rd* field (store data), not rs2
    logic    is_branch;      // 1 = BZ or BNZ (conditional branch)
    logic    branch_on_zero; // meaningful only when is_branch: 1=BZ, 0=BNZ
    logic    is_jmp;         // 1 = JMP (unconditional)
    logic    is_hlt;         // 1 = HLT
    logic    flags_we;       // 1 = this opcode legitimately updates flags_reg {Z,C}
    logic    uses_rs1;       // 1 = this opcode actually reads register-file port A (rs1 / address reg)
    logic    uses_rs2;       // 1 = this opcode actually reads register-file port B (rs2, or ST's store-data via rd field)
  } ctrl_t;

  // ---------------------------------------------------------------------
  // Stage-specific views of the control word. A pipeline register should only
  // carry the bits that a LATER stage still reads; carrying the full ctrl_t all
  // the way down made Vivado synthesis remove the unread flops ("Synth 8-6014
  // unused sequential element") and the linter flag them ("ASSIGN-6 assigned
  // but not read").
  //   ex_ctrl_t  : ID/EX  register  (everything except use_rd_as_src2, which is
  //                only needed in ID to pick the read-port-B register)
  //   mem_ctrl_t : EX/MEM register  (what MEM, forwarding and WB still need)
  //   wb_ctrl_t  : MEM/WB register  (register write enable + HLT retirement)
  // ---------------------------------------------------------------------
  typedef struct packed {
    wb_sel_e wb_sel;
    logic    reg_we;
    logic    mem_we;
    logic    mem_to_reg;
    logic    is_branch;
    logic    branch_on_zero;
    logic    is_jmp;
    logic    is_hlt;
    logic    flags_we;
    logic    uses_rs1;
    logic    uses_rs2;
  } ex_ctrl_t;

  typedef struct packed {
    wb_sel_e wb_sel;
    logic    reg_we;
    logic    mem_we;
    logic    mem_to_reg;
    logic    is_hlt;
  } mem_ctrl_t;

  typedef struct packed {
    logic    reg_we;
    logic    is_hlt;
  } wb_ctrl_t;

endpackage : risc8_pkg
