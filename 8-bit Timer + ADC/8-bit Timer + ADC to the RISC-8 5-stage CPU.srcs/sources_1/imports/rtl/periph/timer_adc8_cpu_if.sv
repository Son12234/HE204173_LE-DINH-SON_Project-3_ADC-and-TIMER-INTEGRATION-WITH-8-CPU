// =============================================================================
// File   : timer_adc8_cpu_if.sv
// Purpose: The module risc8_soc.sv actually instantiates (guide chapter 5,
//          "u_tadc"). Kept as a thin, separate wrapper around
//          timer_adc8_top.sv on purpose: it is the one file whose port list
//          is a fixed contract with the CPU core's io_* port, so the
//          internal composition of the peripheral (apb_regs8 / timer8 /
//          sar_adc_ctrl / sync_fifo, all inside timer_adc8_top.sv) can be
//          revised later without touching risc8_soc.sv at all.
// =============================================================================
module timer_adc8_cpu_if (
  input  logic       clk,
  input  logic       rst_n,       // asynchronous, active-low

  input  logic       cs,
  input  logic       we,
  input  logic [3:0] addr,
  input  logic [7:0] wdata,
  output logic [7:0] rdata,

  output logic       irq,

  // ---- analog front-end pins, passed straight through ----
  output logic       adc_sample,
  output logic [1:0] adc_ch,
  output logic [7:0] adc_dac,
  input  logic       adc_cmp,

  output logic       pwm_out
);

  // This wrapper intentionally does no logic of its own: it exists purely
  // as the stable interface boundary described above.
  timer_adc8_top u_timer_adc8_top (
    .clk        (clk),
    .rst_n      (rst_n),
    .cs         (cs),
    .we         (we),
    .addr       (addr),
    .wdata      (wdata),
    .rdata      (rdata),
    .irq        (irq),
    .adc_sample (adc_sample),
    .adc_ch     (adc_ch),
    .adc_dac    (adc_dac),
    .adc_cmp    (adc_cmp),
    .pwm_out    (pwm_out)
  );

endmodule : timer_adc8_cpu_if
