// =============================================================================
// File   : risc8_soc_pkg.sv
// Purpose: The UVM environment for the RISC-8 + Timer/ADC SoC. The DUT here
//          is an autonomous CPU that runs firmware out of its own on-chip
//          ROM once reset is released -- there is no external bus for a
//          sequence to drive data onto, so the one thing the environment
//          actively drives is reset (via a standard driver/sequencer/
//          sequence/agent stack); everything else is passively observed:
//          a bus monitor snoops the CPU<->peripheral bus for coverage, and
//          the scoreboard checks the firmware's final RAM contents against
//          the same golden expected-value table used by
//          sw/iss_model.py (the Python functional model run during
//          development -- see that file's header for why it exists).
// =============================================================================
package risc8_soc_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import risc8_pkg::*;

  // ===========================================================================
  // Reset sequence item / driver / sequencer / sequence / agent
  // ===========================================================================
  class risc8_reset_item extends uvm_sequence_item;
    `uvm_object_utils(risc8_reset_item)
    rand int unsigned reset_cycles;

    function new(string name = "risc8_reset_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("reset_cycles=%0d", reset_cycles);
    endfunction
  endclass : risc8_reset_item

  class risc8_reset_driver extends uvm_driver #(risc8_reset_item);
    `uvm_component_utils(risc8_reset_driver)
    virtual risc8_soc_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual risc8_soc_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "risc8_reset_driver: virtual interface not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      risc8_reset_item req;
      vif.rst <= 1'b1;   // start asserted so the DUT never sees an undefined reset level
      forever begin
        seq_item_port.get_next_item(req);
        `uvm_info("RESET_DRV", $sformatf("driving reset for %0d cycles", req.reset_cycles), UVM_MEDIUM)
        vif.rst <= 1'b1;
        repeat (req.reset_cycles) @(posedge vif.clk);
        vif.rst <= 1'b0;
        seq_item_port.item_done();
      end
    endtask
  endclass : risc8_reset_driver

  class risc8_reset_sequencer extends uvm_sequencer #(risc8_reset_item);
    `uvm_component_utils(risc8_reset_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass : risc8_reset_sequencer

  class risc8_reset_sequence extends uvm_sequence #(risc8_reset_item);
    `uvm_object_utils(risc8_reset_sequence)
    rand int unsigned reset_cycles = 5;

    function new(string name = "risc8_reset_sequence");
      super.new(name);
    endfunction

    task body();
      risc8_reset_item item;
      item = risc8_reset_item::type_id::create("item");
      start_item(item);
      if (!item.randomize() with { reset_cycles == local::reset_cycles; })
        `uvm_fatal("RANDFAIL", "risc8_reset_item randomize failed")
      finish_item(item);
    endtask
  endclass : risc8_reset_sequence

  class risc8_reset_agent extends uvm_agent;
    `uvm_component_utils(risc8_reset_agent)
    risc8_reset_driver     driver;
    risc8_reset_sequencer  sequencer;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer = risc8_reset_sequencer::type_id::create("sequencer", this);
      driver    = risc8_reset_driver::type_id::create("driver", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass : risc8_reset_agent


  // ===========================================================================
  // Passive bus monitor: one risc8_bus_item per CPU<->peripheral access
  // ===========================================================================
  class risc8_bus_item extends uvm_sequence_item;
    `uvm_object_utils(risc8_bus_item)
    bit       we;
    bit [3:0] addr;
    bit [7:0] wdata;
    bit [7:0] rdata;

    function new(string name = "risc8_bus_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("%s addr=0x%0h wdata=0x%0h rdata=0x%0h",
                        we ? "WR" : "RD", addr, wdata, rdata);
    endfunction
  endclass : risc8_bus_item

  class risc8_bus_monitor extends uvm_monitor;
    `uvm_component_utils(risc8_bus_monitor)
    virtual risc8_soc_if vif;
    uvm_analysis_port #(risc8_bus_item) ap;

    // Lightweight functional coverage: which register-within-page addresses
    // were exercised, crossed with read vs. write, over the course of the
    // firmware run.
    bit       cov_we;
    bit [3:0] cov_addr;
    covergroup cg_bus_access;
      option.per_instance = 1;
      cp_addr: coverpoint cov_addr {
        bins tmr_ctrl   = {REG_TMR_CTRL};
        bins tmr_presc  = {REG_TMR_PRESC};
        bins tmr_load   = {REG_TMR_LOAD};
        bins tmr_cmp    = {REG_TMR_CMP};
        bins tmr_cnt    = {REG_TMR_CNT};
        bins adc_ctrl   = {REG_ADC_CTRL};
        bins adc_smp    = {REG_ADC_SMP};
        bins adc_div    = {REG_ADC_DIV};
        bins adc_thr_lo = {REG_ADC_THR_LO};
        bins adc_thr_hi = {REG_ADC_THR_HI};
        bins adc_data   = {REG_ADC_DATA};
        bins adc_rch    = {REG_ADC_RCH};
        bins adc_stat   = {REG_ADC_STAT};
        bins irq_en     = {REG_IRQ_EN};
        bins irq_stat   = {REG_IRQ_STAT};
        bins id         = {REG_ID};
      }
      cp_we: coverpoint cov_we;
      cx_addr_we: cross cp_addr, cp_we;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
      cg_bus_access = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual risc8_soc_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "risc8_bus_monitor: virtual interface not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      risc8_bus_item item;
      forever begin
        @(posedge vif.clk);
        if (vif.io_cs) begin
          item        = risc8_bus_item::type_id::create("item");
          item.we     = vif.io_we;
          item.addr   = vif.io_addr;
          item.wdata  = vif.io_wdata;
          item.rdata  = vif.io_rdata;
          cov_we      = vif.io_we;
          cov_addr    = vif.io_addr;
          cg_bus_access.sample();
          ap.write(item);
        end
      end
    endtask
  endclass : risc8_bus_monitor


  // ===========================================================================
  // Scoreboard: counts bus traffic for a summary, and checks the firmware's
  // final RAM contents via a hierarchical backdoor read once the CPU halts.
  // ===========================================================================
  class risc8_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(risc8_scoreboard)
    uvm_analysis_imp #(risc8_bus_item, risc8_scoreboard) bus_export;
    virtual risc8_soc_if vif;

    int unsigned num_accesses;
    int unsigned num_reads;
    int unsigned num_writes;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      bus_export = new("bus_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual risc8_soc_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "risc8_scoreboard: virtual interface not set in config_db")
    endfunction

    function void write(risc8_bus_item t);
      num_accesses++;
      if (t.we) num_writes++; else num_reads++;
    endfunction

    // DPI-free RAM read: drive the address on the debug peek bus (see
    // risc8_soc_if.sv / tb_top.sv) and give the combinational hierarchical
    // read through the module tree a moment to settle before sampling it.
    // This replaces uvm_hdl_read(), which Vivado's bundled UVM library
    // fatals on by default ("DPI routines are compiled off").
    task automatic peek_ram(input byte unsigned addr, output byte unsigned data);
      vif.dbg_ram_addr = addr;
      #1;
      data = vif.dbg_ram_data;
    endtask

    // Golden expected-value table: identical in spirit to the guide's own
    // "PASS: MEM[xx] = yy" results table, and numerically identical to the
    // table self-checked by sw/iss_model.py against this same firmware.
    task check_results();
      // Written as plain declarations + individual element assignments
      // (rather than an array-literal '{...} initializer) on purpose: see
      // the matching comment in tb_top.sv for the Vivado xvlog parser
      // limitations that style was changed to avoid.
      byte unsigned exp_addr [11];
      byte unsigned exp_data [11];
      int unsigned errors = 0;
      byte unsigned got;

      exp_addr[0]  = 8'h80;  exp_data[0]  = 8'hA8;
      exp_addr[1]  = 8'h81;  exp_data[1]  = 8'h81;
      exp_addr[2]  = 8'h82;  exp_data[2]  = 8'h56;
      exp_addr[3]  = 8'h83;  exp_data[3]  = 8'h9B;
      exp_addr[4]  = 8'h84;  exp_data[4]  = 8'h9B;
      exp_addr[5]  = 8'h86;  exp_data[5]  = 8'h00;
      exp_addr[6]  = 8'h87;  exp_data[6]  = 8'h0C;
      exp_addr[7]  = 8'h88;  exp_data[7]  = 8'hE8;
      exp_addr[8]  = 8'h89;  exp_data[8]  = 8'h1F;
      exp_addr[9]  = 8'h8A;  exp_data[9]  = 8'h56;
      exp_addr[10] = 8'h8B;  exp_data[10] = 8'h10;

      `uvm_info("SCOREBOARD",
                $sformatf("bus traffic: %0d accesses (%0d reads, %0d writes)",
                          num_accesses, num_reads, num_writes), UVM_LOW)

      foreach (exp_addr[i]) begin
        peek_ram(exp_addr[i], got);
        if (got !== exp_data[i]) begin
          `uvm_error("MISMATCH",
                     $sformatf("RAM[0x%0h] = 0x%0h, expected 0x%0h", exp_addr[i], got, exp_data[i]))
          errors++;
        end else begin
          `uvm_info("MATCH", $sformatf("RAM[0x%0h] = 0x%0h (expected)", exp_addr[i], got), UVM_LOW)
        end
      end

      if (errors == 0)
        `uvm_info("SCOREBOARD", "*** ALL RAM CHECKS PASSED ***", UVM_NONE)
      else
        `uvm_error("SCOREBOARD", $sformatf("*** %0d RAM CHECK(S) FAILED ***", errors))
    endtask
  endclass : risc8_scoreboard


  // ===========================================================================
  // Environment
  // ===========================================================================
  class risc8_env extends uvm_env;
    `uvm_component_utils(risc8_env)
    risc8_reset_agent  reset_agent;
    risc8_bus_monitor  bus_monitor;
    risc8_scoreboard   scoreboard;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      reset_agent = risc8_reset_agent::type_id::create("reset_agent", this);
      bus_monitor = risc8_bus_monitor::type_id::create("bus_monitor", this);
      scoreboard  = risc8_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      bus_monitor.ap.connect(scoreboard.bus_export);
    endfunction
  endclass : risc8_env


  // ===========================================================================
  // Test
  // ===========================================================================
  class risc8_base_test extends uvm_test;
    `uvm_component_utils(risc8_base_test)
    risc8_env env;
    virtual risc8_soc_if vif;

    // Simulated-time safety net in clock cycles, in case firmware ever
    // fails to halt (e.g. a future firmware edit introduces a real bug).
    int unsigned halt_timeout_cycles = 20000;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = risc8_env::type_id::create("env", this);
      if (!uvm_config_db#(virtual risc8_soc_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "risc8_base_test: virtual interface not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      risc8_reset_sequence rst_seq;
      int unsigned waited;

      phase.raise_objection(this);

      rst_seq = risc8_reset_sequence::type_id::create("rst_seq");
      rst_seq.reset_cycles = 5;
      rst_seq.start(env.reset_agent.sequencer);

      // Wait for the firmware to run to completion (HLT retiring), or time
      // out and fail loudly rather than hang the simulation forever.
      waited = 0;
      while (!vif.halted && waited < halt_timeout_cycles) begin
        @(posedge vif.clk);
        waited++;
      end

      if (!vif.halted)
        `uvm_error("TIMEOUT", $sformatf("DUT did not halt within %0d cycles", halt_timeout_cycles))
      else
        `uvm_info("BASE_TEST", $sformatf("DUT halted after %0d cycles (pc=0x%0h)", waited, vif.pc_out), UVM_LOW)

      // A couple of extra cycles so the PWM/timer pins the guide's own
      // chapter 9 checks also look at have settled before we score.
      repeat (10) @(posedge vif.clk);

      env.scoreboard.check_results();

      phase.drop_objection(this);
    endtask
  endclass : risc8_base_test

endpackage : risc8_soc_pkg
