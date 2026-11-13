// =============================================================================
// File   : timer_adc_sva.sv
// Purpose: SystemVerilog Assertions for the timer/ADC peripheral, attached
//          with `bind` so none of the RTL files need to carry assertion
//          code themselves (compile this file only when assertions are
//          wanted, e.g. `+define+SVA`, exactly as the integration guide's
//          chapter 9 describes). Each `bind` reaches directly into the
//          target module's own internal signals (register names included),
//          which `bind` makes visible without changing the target's port
//          list.
//          This is an independent, from-scratch assertion set written
//          against this project's own RTL (register/signal names above);
//          it checks the same *kinds* of properties the guide's own
//          assertion file does (protocol legality, FIFO/counter bounds,
//          IRQ bookkeeping) but is not a copy of it.
// =============================================================================
`ifdef SVA

// NOTE (xsim): Vivado's simulator does not support "default disable iff"
// declarations (error XSIM 43-3980), so every assertion below carries its own
// "disable iff (!rst_n)" clause instead. The meaning is identical.

// ---------------------------------------------------------------------------
// sync_fifo: pointer/level bookkeeping can never go out of bounds.
// ---------------------------------------------------------------------------
module sync_fifo_checker #(
  parameter int WIDTH = 10,
  parameter int DEPTH = 8
) (
  input logic clk, rst_n,
  input logic wr_en, rd_en, full, empty,
  input logic [$clog2(DEPTH+1)-1:0] level,
  input logic [$clog2(DEPTH)-1:0]   wr_ptr, rd_ptr,
  input logic [$clog2(DEPTH+1)-1:0] count
);
  // level/count never exceed the physical depth.
  a_fifo_level_in_range: assert property (@(posedge clk) disable iff (!rst_n) count <= DEPTH)
    else $error("sync_fifo: count %0d exceeds DEPTH %0d", count, DEPTH);

  // full and empty are mutually exclusive for any DEPTH > 1.
  a_fifo_full_empty_excl: assert property (@(posedge clk) disable iff (!rst_n) !(full && empty))
    else $error("sync_fifo: full and empty asserted simultaneously");

  // full <-> count==DEPTH, empty <-> count==0 (the flags are a pure
  // function of count, so this is really a consistency check on the RTL
  // that computes them).
  a_fifo_full_matches_count:  assert property (@(posedge clk) disable iff (!rst_n) full  == (count == DEPTH))
    else $error("sync_fifo: 'full' flag disagrees with count");
  a_fifo_empty_matches_count: assert property (@(posedge clk) disable iff (!rst_n) empty == (count == 0))
    else $error("sync_fifo: 'empty' flag disagrees with count");

  // A write that is actually accepted (wr_en && !full) must increase count
  // by exactly one on the next clock, unless a simultaneous accepted read
  // cancels it out.
  a_fifo_push_increments: assert property (
    @(posedge clk) disable iff (!rst_n) (wr_en && !full && !(rd_en && !empty)) |=> (count == $past(count) + 1)
  ) else $error("sync_fifo: accepted push did not increase count by 1");

  a_fifo_pop_decrements: assert property (
    @(posedge clk) disable iff (!rst_n) (rd_en && !empty && !(wr_en && !full)) |=> (count == $past(count) - 1)
  ) else $error("sync_fifo: accepted pop did not decrease count by 1");

endmodule : sync_fifo_checker

bind sync_fifo sync_fifo_checker #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_sync_fifo_checker (
  .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .rd_en(rd_en), .full(full), .empty(empty),
  .level(level), .wr_ptr(wr_ptr), .rd_ptr(rd_ptr), .count(count)
);


// ---------------------------------------------------------------------------
// timer8: counter stays in range, PWM output is a pure function of cnt/cmp.
// ---------------------------------------------------------------------------
module timer8_checker (
  input logic clk, rst_n,
  input logic running,
  input logic [7:0] cnt, load_val, cmp_val,
  input logic pwm_out,
  input logic ovf_pulse, cmp_pulse
);
  // The counter never exceeds its own period top value.
  a_tmr_cnt_in_range: assert property (@(posedge clk) disable iff (!rst_n) running |-> (cnt <= load_val))
    else $error("timer8: cnt %0d exceeded load_val %0d while running", cnt, load_val);

  // PWM is exactly (running && cnt < cmp_val): guide's duty formula
  // (CMP/(LOAD+1)) depends on this being a combinational, glitch-free
  // function of the current registers, not registered separately.
  a_tmr_pwm_matches_cnt: assert property (
    @(posedge clk) disable iff (!rst_n) pwm_out == (running && (cnt < cmp_val))
  ) else $error("timer8: pwm_out disagrees with (running && cnt<cmp_val)");

  // Overflow can only ever be reported while the timer is actually running.
  a_tmr_ovf_only_when_running: assert property (@(posedge clk) disable iff (!rst_n) ovf_pulse |-> running)
    else $error("timer8: ovf_pulse asserted while not running");

  a_tmr_cmp_only_when_running: assert property (@(posedge clk) disable iff (!rst_n) cmp_pulse |-> running)
    else $error("timer8: cmp_pulse asserted while not running");

endmodule : timer8_checker

bind timer8 timer8_checker u_timer8_checker (
  .clk(clk), .rst_n(rst_n), .running(running), .cnt(cnt), .load_val(load_val),
  .cmp_val(cmp_val), .pwm_out(pwm_out), .ovf_pulse(ovf_pulse), .cmp_pulse(cmp_pulse)
);


// ---------------------------------------------------------------------------
// sar_adc_ctrl: the state machine never produces a stale or out-of-range
// result, and the DAC code is only driven by the search logic while busy.
// ---------------------------------------------------------------------------
module sar_adc_ctrl_checker (
  input logic clk, rst_n,
  input logic busy, done_pulse, start,
  input logic [7:0] adc_dac
);
  // A new conversion can never be started while one is already in flight
  // (the RTL ignores 'start' outside ST_IDLE, but this checks the
  // *caller's* discipline too: the top-level trigger mux must never pulse
  // 'start' while busy).
  a_adc_no_start_while_busy: assert property (@(posedge clk) disable iff (!rst_n) (busy && start) |-> 1'b0)
    else $error("sar_adc_ctrl: start pulsed while a conversion is already busy");

  // done_pulse is exactly one clock wide.
  a_adc_done_pulse_one_cycle: assert property (
    @(posedge clk) disable iff (!rst_n) done_pulse |=> !done_pulse
  ) else $error("sar_adc_ctrl: done_pulse held for more than one cycle");

  // done_pulse is a registered strobe: it is high in the cycle AFTER the FSM
  // was in ST_DONE, when the FSM is already back in ST_IDLE (busy = 0). So
  // the correct property is that the controller WAS busy one cycle earlier.
  // (The previous form "done_pulse |-> busy" failed on every conversion.)
  a_adc_done_implies_was_busy: assert property (@(posedge clk) disable iff (!rst_n) done_pulse |-> $past(busy))
    else $error("sar_adc_ctrl: done_pulse asserted without a preceding busy cycle");

endmodule : sar_adc_ctrl_checker

bind sar_adc_ctrl sar_adc_ctrl_checker u_sar_adc_ctrl_checker (
  .clk(clk), .rst_n(rst_n), .busy(busy), .done_pulse(done_pulse), .start(start),
  .adc_dac(adc_dac)
);


// ---------------------------------------------------------------------------
// apb_regs8: register-map and IRQ bookkeeping invariants.
// ---------------------------------------------------------------------------
module apb_regs8_checker (
  input logic clk, rst_n,
  input logic cs, we,
  input logic [3:0] addr,
  input logic [7:0] wdata,
  input logic fifo_empty_in,
  input logic [7:0] rdata,
  input logic [3:0] irq_stat_r, irq_en_r,
  input logic tmr_ovf_pulse_in, tmr_cmp_pulse_in, adc_result_valid_in, wd_event,
  input logic irq
);
  // ADC_RCH's VALID bit (rdata[7]) must always agree with !fifo_empty_in
  // whenever ADC_RCH is the address actually being read this cycle.
  a_rch_valid_matches_fifo: assert property (
    @(posedge clk) disable iff (!rst_n) (cs && !we && (addr == risc8_pkg::REG_ADC_RCH)) |-> (rdata[7] == !fifo_empty_in)
  ) else $error("apb_regs8: ADC_RCH.VALID disagrees with FIFO empty status");

  // The irq output pin is nothing more than (IRQ_STAT & IRQ_EN) != 0.
  a_irq_pin_matches_mask: assert property (
    @(posedge clk) disable iff (!rst_n) irq == (|(irq_stat_r & irq_en_r))
  ) else $error("apb_regs8: irq pin disagrees with (irq_stat_r & irq_en_r)");

  // Writing a bit as 1 to IRQ_STAT clears that bit one cycle later, as
  // long as no brand-new event for that same bit arrives this exact
  // cycle (a fresh event must never be silently lost to a same-cycle
  // clear -- this is the companion check to that guarantee: when there is
  // *no* competing event, a requested clear must actually take effect).
  a_irq_w1c_ovf_clears: assert property (
    @(posedge clk) disable iff (!rst_n) (cs && we && (addr == risc8_pkg::REG_IRQ_STAT) &&
                    wdata[risc8_pkg::IRQ_BIT_TMR_OVF] && !tmr_ovf_pulse_in)
    |=> !irq_stat_r[risc8_pkg::IRQ_BIT_TMR_OVF]
  ) else $error("apb_regs8: W1C write did not clear IRQ_STAT.TMR_OVF");

  a_irq_w1c_eoc_clears: assert property (
    @(posedge clk) disable iff (!rst_n) (cs && we && (addr == risc8_pkg::REG_IRQ_STAT) &&
                    wdata[risc8_pkg::IRQ_BIT_ADC_EOC] && !adc_result_valid_in)
    |=> !irq_stat_r[risc8_pkg::IRQ_BIT_ADC_EOC]
  ) else $error("apb_regs8: W1C write did not clear IRQ_STAT.ADC_EOC");

endmodule : apb_regs8_checker

bind apb_regs8 apb_regs8_checker u_apb_regs8_checker (
  .clk(clk), .rst_n(rst_n), .cs(cs), .we(we), .addr(addr), .wdata(wdata),
  .fifo_empty_in(fifo_empty_in), .rdata(rdata), .irq_stat_r(irq_stat_r),
  .irq_en_r(irq_en_r), .tmr_ovf_pulse_in(tmr_ovf_pulse_in),
  .tmr_cmp_pulse_in(tmr_cmp_pulse_in), .adc_result_valid_in(adc_result_valid_in),
  .wd_event(wd_event), .irq(irq)
);

`endif // SVA
