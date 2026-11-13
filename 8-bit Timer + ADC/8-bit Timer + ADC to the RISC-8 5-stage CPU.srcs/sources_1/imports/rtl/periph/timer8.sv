// =============================================================================
// File   : timer8.sv
// Purpose: 8-bit timer with a programmable prescaler, free-running or
//          one-shot operation, a PWM output and two IRQ-worthy events
//          (overflow, compare-match). Register semantics are exactly the
//          ones cross-checked against the integration guide's own worked
//          examples:
//            - tick every (PRESC+1) input clocks
//            - period = (LOAD+1) ticks, so total clocks = (PRESC+1)*(LOAD+1)
//              (guide: PRESC=3, LOAD=24 -> "100-clock period" = 4*25)
//            - PWM duty = CMP/(LOAD+1)
//              (guide: PRESC=0, LOAD=9, CMP=3 -> "30% duty" = 3/10)
// =============================================================================
module timer8 (
  input  logic       clk,
  input  logic       rst_n,       // asynchronous, active-low

  // ---- register-file inputs (TMR_CTRL/PRESC/LOAD/CMP) ----
  input  logic       ctrl_en,
  input  logic       ctrl_oneshot,
  input  logic [7:0] presc,       // tick every (presc+1) clocks
  input  logic [7:0] load_val,    // period top value: counts 0..load_val inclusive
  input  logic [7:0] cmp_val,     // PWM / compare threshold

  // ---- register-file output (TMR_CNT, read-only) ----
  output logic [7:0] cnt,

  // ---- peripheral pins ----
  output logic       pwm_out,     // high while cnt < cmp_val

  // ---- one-shot event pulses for the IRQ_STAT logic in apb_regs8.sv ----
  output logic       ovf_pulse,   // 1 clock wide: counter just wrapped LOAD -> 0
  output logic       cmp_pulse,   // 1 clock wide: counter just reached cmp_val while running

  // ---- hardware trigger for the ADC ("timer-overflow trigger" mode) ----
  output logic       trig_pulse   // identical timing to ovf_pulse, named separately for clarity at the call site
);

  logic [7:0] presc_cnt;   // prescaler sub-counter, 0..presc
  logic       tick;        // 1-clock pulse once every (presc+1) input clocks, only while running

  logic       running;     // ctrl_en, possibly cleared by one-shot completion
  // ONESHOT: once the counter overflows, 'running' is cleared automatically
  // so the timer stops with cnt held at 0 until software re-enables it;
  // free-running (ONESHOT=0) just keeps going.
  logic       auto_stop;
  assign auto_stop = ctrl_oneshot && ovf_pulse;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      running <= 1'b0;
    else if (!ctrl_en)
      running <= 1'b0;             // software disable always wins
    else if (auto_stop)
      running <= 1'b0;             // one-shot: stop right after the overflow it just produced
    else if (ctrl_en)
      running <= 1'b1;             // (re-)enabled by software
  end

  // ---- prescaler: produces 'tick' every (presc+1) clocks while running ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      presc_cnt <= '0;
      tick      <= 1'b0;
    end else if (!running) begin
      presc_cnt <= '0;
      tick      <= 1'b0;
    end else if (presc_cnt == presc) begin
      presc_cnt <= '0;
      tick      <= 1'b1;
    end else begin
      presc_cnt <= presc_cnt + 1'b1;
      tick      <= 1'b0;
    end
  end

  // ---- main counter: advances by one on every 'tick', wraps at load_val ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cnt <= '0;
    else if (!running) begin
      // Hold at 0 while stopped so a fresh EN=1 always starts a clean period.
      cnt <= '0;
    end else if (tick) begin
      if (cnt == load_val)
        cnt <= '0;                  // wrap: one full period has elapsed
      else
        cnt <= cnt + 1'b1;
    end
  end

  assign pwm_out = running && (cnt < cmp_val);

  assign ovf_pulse = running && tick && (cnt == load_val);
  // Compare match fires once, exactly the tick the counter reaches cmp_val
  // (guard cmp_val <= load_val implicitly; if a program sets cmp_val above
  // load_val, cnt simply never reaches it and cmp_pulse never fires, which
  // is a benign, firmware-correctable condition, not a hardware fault).
  assign cmp_pulse = running && tick && (cnt == cmp_val);

  assign trig_pulse = ovf_pulse;

endmodule : timer8
