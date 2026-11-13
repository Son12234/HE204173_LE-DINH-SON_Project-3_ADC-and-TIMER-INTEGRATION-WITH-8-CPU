// =============================================================================
// File   : risc8_soc_if.sv
// Purpose: Pin-level interface between tb_top.sv and the UVM environment.
//          Carries the clock plus every top-level DUT signal the agents,
//          monitor and scoreboard need to observe or drive. Internal bus
//          signals (io_cs/io_we/io_addr/...) are also surfaced here by
//          hierarchical reference from tb_top, since the guide's own
//          waveform chapter (chapter 6) is written entirely in terms of
//          that internal bus and the UVM bus monitor reports on it the
//          same way.
// =============================================================================
interface risc8_soc_if (input logic clk);

  // ---- reset, driven by the UVM reset agent ----
  logic rst;

  // ---- top-level DUT pins (risc8_soc.sv) ----
  logic       halted;
  logic [7:0] pc_out;
  logic       irq;
  logic       pwm_out;
  logic       adc_sample;
  logic [1:0] adc_ch;
  logic [7:0] adc_dac;
  logic       adc_cmp;

  // ---- internal CPU<->peripheral bus, tapped for the passive bus monitor
  //      (tb_top.sv wires these up by hierarchical reference, since the
  //      bus itself is not a risc8_soc.sv top-level port) ----
  logic       io_cs;
  logic       io_we;
  logic [3:0] io_addr;
  logic [7:0] io_wdata;
  logic [7:0] io_rdata;

  // ---- plain, DPI-free debug "peek" bus into the CPU's data RAM ----
  // tb_top.sv drives dbg_ram_data combinationally from
  // dut.u_cpu.u_dmem.mem[dbg_ram_addr] by ordinary hierarchical reference
  // (no DPI, no uvm_hdl_read). The UVM scoreboard uses this instead of a
  // backdoor read, since Vivado's bundled UVM ships with HDL-backdoor DPI
  // compiled off by default (UVM_HDL_READ fatal: "DPI routines are
  // compiled off").
  logic [7:0] dbg_ram_addr;
  logic [7:0] dbg_ram_data;

endinterface : risc8_soc_if
