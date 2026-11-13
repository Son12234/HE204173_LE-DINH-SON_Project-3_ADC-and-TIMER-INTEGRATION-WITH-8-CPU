// =============================================================================
// File   : tb_top.sv
// Purpose: UVM testbench top. Generates the clock, instantiates the DUT
//          (risc8_soc) and the behavioral analog front end (afe_model),
//          wires both to the risc8_soc_if virtual interface, publishes
//          that interface through uvm_config_db, and calls run_test().
//
//          Also includes a small, deliberately UVM-independent `initial`
//          block that waits for the DUT to halt and prints the same
//          "PASS: MEM[xx] = yy" style table the integration guide's own
//          chapter 9 shows. This is a portability safety net: uvm_hdl_read
//          (used by the UVM scoreboard for the same check) is a standard
//          part of UVM but its backdoor path resolution can be sensitive
//          to simulator settings, so this block gives an independent,
//          always-reliable confirmation in the transcript even if that
//          ever needs debugging on a particular tool. It never calls
//          $finish itself -- UVM's own run_test() owns ending the
//          simulation, once the scoreboard's official check completes.
// =============================================================================
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import risc8_soc_pkg::*;

  // ---- clock: 100 MHz (10 ns period) ----
  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---- UVM virtual interface instance ----
  risc8_soc_if risc8_vif (.clk(clk));

  // ---- DUT ----
  risc8_soc #(.IMEM_FILE("soc_demo.hex")) dut (
    .clk        (clk),
    .rst        (risc8_vif.rst),
    .halted     (risc8_vif.halted),
    .pc_out     (risc8_vif.pc_out),
    .irq        (risc8_vif.irq),
    .pwm_out    (risc8_vif.pwm_out),
    .adc_sample (risc8_vif.adc_sample),
    .adc_ch     (risc8_vif.adc_ch),
    .adc_dac    (risc8_vif.adc_dac),
    .adc_cmp    (risc8_vif.adc_cmp)
  );

  // ---- behavioral analog front end (simulation only) ----
  afe_model u_afe (
    .clk        (clk),
    .adc_sample (risc8_vif.adc_sample),
    .adc_ch     (risc8_vif.adc_ch),
    .adc_dac    (risc8_vif.adc_dac),
    .adc_cmp    (risc8_vif.adc_cmp)
  );

  // ---- internal CPU<->peripheral bus, tapped by hierarchical reference
  //      for the passive bus monitor (not top-level risc8_soc.sv ports) ----
  assign risc8_vif.io_cs    = dut.io_cs;
  assign risc8_vif.io_we    = dut.io_we;
  assign risc8_vif.io_addr  = dut.io_addr;
  assign risc8_vif.io_wdata = dut.io_wdata;
  assign risc8_vif.io_rdata = dut.io_rdata;

  // ---- DPI-free RAM peek for the UVM scoreboard (see risc8_soc_if.sv) ----
  assign risc8_vif.dbg_ram_data = dut.u_cpu.u_dmem.mem[risc8_vif.dbg_ram_addr];

  // ---- OPTIONAL debug tracing (bus trace / heartbeat / ADC probes) ----
  // Off by default so the normal log stays clean and fast. To turn it on,
  // add the define RISC8_TRACE to the simulation compile options
  // (Vivado: Settings > Simulation > Verilog options > add 'RISC8_TRACE').
`ifdef RISC8_TRACE
  // ---- diagnostic trace: prints every CPU<->peripheral bus access so a
  //      stuck polling loop (or any other dead-end) is visible directly in
  //      the simulation log, with no manual waveform navigation needed.
  //      Bounded so it stays readable: full detail for the first 60
  //      accesses (enough to see the whole startup sequence), then a
  //      lightweight "still here" line every 500 accesses after that. ----
  int unsigned io_trace_count = 0;
  always @(posedge clk) begin
    if (dut.io_cs) begin
      io_trace_count++;
      if (io_trace_count <= 60 || (io_trace_count % 500) == 0) begin
        $display("[io_trace #%0d] t=%0t pc=0x%0h %s io_addr=0xF%0h wdata=0x%0h rdata=0x%0h",
                  io_trace_count, $time, dut.pc_out, (dut.io_we ? "WR" : "RD"),
                  dut.io_addr, dut.io_wdata, dut.io_rdata);
      end
    end
  end

  // Coarse "is the CPU making progress at all" heartbeat, independent of
  // whether it is touching the I/O page: one line every 1000 clocks.
  always @(posedge clk) begin
    if (($time % 10000) == 0 && $time > 0) begin
      $display("[heartbeat] t=%0t pc=0x%0h halted=%0b rst=%0b io_cs=%0b io_we=%0b io_addr=0xF%0h",
                $time, dut.pc_out, dut.halted, dut.rst, dut.io_cs, dut.io_we, dut.io_addr);
    end
  end

  // Focused probe directly on the ADC trigger/completion events, to tell
  // apart "the ADC never even starts converting" from "it starts but
  // never finishes" from "it finishes but the status bits read wrong" --
  // the three distinct bug classes that would all otherwise look the same
  // from the CPU's side (an endless ADC_STAT poll).
  always @(posedge clk) begin
    if (dut.u_tadc.u_timer_adc8_top.adc_start)
      $display("[adc_trace] t=%0t ADC START pulsed, channel=%0d",
                $time, dut.u_tadc.u_timer_adc8_top.adc_ch_sel);
    if (dut.u_tadc.u_timer_adc8_top.adc_done_pulse)
      $display("[adc_trace] t=%0t ADC DONE  pulsed, code=0x%0h channel=%0d fifo_level_after=%0d",
                $time, dut.u_tadc.u_timer_adc8_top.adc_result_code,
                dut.u_tadc.u_timer_adc8_top.adc_result_ch,
                dut.u_tadc.u_timer_adc8_top.fifo_level);
  end
`endif // RISC8_TRACE

  // ---- hand the virtual interface to every UVM component that asks for it ----
  initial begin
    uvm_config_db#(virtual risc8_soc_if)::set(null, "*", "vif", risc8_vif);
  end

  // ---- start UVM ----
  initial begin
    run_test("risc8_base_test");
  end

  // ---- portability safety-net printout (see file header) ----
  // Written in the most tool-compatible style on purpose (plain element-by-
  // element assignment instead of an array-literal initializer, explicit
  // 'static' lifetime, a literal check count instead of a block-local
  // localparam/.size() call): earlier, more "idiomatic" versions of this
  // block hit two separate Vivado xvlog parser limitations (VRFC 10-2158
  // on .size() for a fixed-size array, and VRFC 10-2989/10-3824 on a
  // localparam declared and used inside the same initial block), even
  // though both were legal, ordinary SystemVerilog. This version avoids
  // all of that.
  initial begin
    static byte unsigned exp_addr [11];
    static byte unsigned exp_data [11];
    static int  unsigned fails;

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

    wait (dut.halted === 1'b1);
    #20;   // let a couple more clocks settle (matches the base test's own margin)

    fails = 0;
    $display("--------------------------------------------------");
    $display("[tb_top] DUT halted, pc_out=0x%0h", dut.pc_out);
    foreach (exp_addr[i]) begin
      static byte unsigned got;
      got = dut.u_cpu.u_dmem.mem[exp_addr[i]];
      if (got !== exp_data[i]) begin
        $display("FAIL: MEM[%0h] = %0h  (expected %0h)", exp_addr[i], got, exp_data[i]);
        fails++;
      end else begin
        $display("PASS: MEM[%0h] = %0h", exp_addr[i], got);
      end
    end
    if (fails == 0)
      $display("*** SOC TEST PASSED *** (11 checks)");
    else
      $display("*** SOC TEST FAILED *** (%0d of 11 checks failed)", fails);
    $display("--------------------------------------------------");
  end

endmodule : tb_top
