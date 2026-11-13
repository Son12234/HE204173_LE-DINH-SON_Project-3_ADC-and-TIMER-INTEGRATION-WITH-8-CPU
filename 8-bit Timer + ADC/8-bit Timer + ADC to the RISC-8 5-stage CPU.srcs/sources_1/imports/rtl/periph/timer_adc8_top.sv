// =============================================================================
// File   : timer_adc8_top.sv
// Purpose: Composes the four peripheral building blocks (apb_regs8, timer8,
//          sar_adc_ctrl, sync_fifo) into the single "8-bit Timer + ADC"
//          peripheral shown in the guide's block diagram. Also owns the one
//          piece of behavior that genuinely spans more than one block: the
//          ADC trigger mux (ADC_CTRL.TRIG_SEL selects either a software
//          START write or the timer's overflow pulse) and pushing each
//          finished conversion into the FIFO.
// =============================================================================
import risc8_pkg::*;

module timer_adc8_top (
  input  logic       clk,
  input  logic       rst_n,        // asynchronous, active-low

  // ---- CPU-facing bus (register-within-page address) ----
  input  logic       cs,
  input  logic       we,
  input  logic [3:0] addr,
  input  logic [7:0] wdata,
  output logic [7:0] rdata,

  output logic       irq,

  // ---- analog front-end pins ----
  output logic       adc_sample,
  output logic [1:0] adc_ch,
  output logic [7:0] adc_dac,
  input  logic       adc_cmp,

  output logic       pwm_out
);

  // ---------------------------------------------------------------------
  // Wires between apb_regs8 and timer8
  // ---------------------------------------------------------------------
  logic       tmr_ctrl_en, tmr_ctrl_oneshot;
  logic [7:0] tmr_presc, tmr_load, tmr_cmp_val;
  logic [7:0] tmr_cnt;
  logic       tmr_ovf_pulse, tmr_cmp_pulse, tmr_trig_pulse;

  timer8 u_timer8 (
    .clk          (clk),
    .rst_n        (rst_n),
    .ctrl_en      (tmr_ctrl_en),
    .ctrl_oneshot (tmr_ctrl_oneshot),
    .presc        (tmr_presc),
    .load_val     (tmr_load),
    .cmp_val      (tmr_cmp_val),
    .cnt          (tmr_cnt),
    .pwm_out      (pwm_out),
    .ovf_pulse    (tmr_ovf_pulse),
    .cmp_pulse    (tmr_cmp_pulse),
    .trig_pulse   (tmr_trig_pulse)
  );

  // ---------------------------------------------------------------------
  // Wires between apb_regs8 and sar_adc_ctrl
  // ---------------------------------------------------------------------
  logic        adc_ctrl_en, adc_start_pulse;
  logic [1:0]  adc_trig_sel, adc_ch_sel;
  logic [7:0]  adc_smp, adc_div;
  logic        adc_busy, adc_done_pulse;
  logic [7:0]  adc_result_code;
  logic [1:0]  adc_result_ch;

  // Trigger mux: TRIG_SEL=0 -> immediate software START write,
  //              TRIG_SEL=1 -> fires automatically on every timer overflow.
  // (TRIG_SEL=2/3 are reserved for future trigger sources; they simply
  // never fire a conversion, which is safe, inert default behavior.)
  logic sw_trigger, hw_trigger, adc_start;
  assign sw_trigger = (adc_trig_sel == 2'b00) && adc_start_pulse;
  assign hw_trigger = (adc_trig_sel == 2'b01) && tmr_trig_pulse;
  assign adc_start  = adc_ctrl_en && (sw_trigger || hw_trigger);

  sar_adc_ctrl u_sar_adc_ctrl (
    .clk         (clk),
    .rst_n       (rst_n),
    .start       (adc_start),
    .channel_sel (adc_ch_sel),
    .smp_cycles  (adc_smp),
    .div_cycles  (adc_div),
    .adc_sample  (adc_sample),
    .adc_ch      (adc_ch),
    .adc_dac     (adc_dac),
    .adc_cmp     (adc_cmp),
    .busy        (adc_busy),
    .done_pulse  (adc_done_pulse),
    .result_code (adc_result_code),
    .result_ch   (adc_result_ch)
  );

  // ---------------------------------------------------------------------
  // FIFO: one entry per finished conversion, {channel, code}. A result
  // arriving while the FIFO is already full is dropped (software is
  // expected to watch ADC_STAT.FULL / poll promptly); EOC and watchdog
  // IRQs still fire so firmware finds out the conversion happened even if
  // its data could not be queued.
  // ---------------------------------------------------------------------
  logic       fifo_full, fifo_empty;
  logic [3:0] fifo_level;
  logic [9:0] fifo_rd_data;
  logic       fifo_rd_en;

  sync_fifo #(.WIDTH(10), .DEPTH(FIFO_DEPTH)) u_fifo (
    .clk     (clk),
    .rst_n   (rst_n),
    .wr_en   (adc_done_pulse && !fifo_full),
    .wr_data ({adc_result_ch, adc_result_code}),
    .rd_en   (fifo_rd_en),
    .rd_data (fifo_rd_data),
    .full    (fifo_full),
    .empty   (fifo_empty),
    .level   (fifo_level)
  );

  // ---------------------------------------------------------------------
  // The register file itself
  // ---------------------------------------------------------------------
  apb_regs8 u_apb_regs8 (
    .clk                 (clk),
    .rst_n               (rst_n),
    .cs                  (cs),
    .we                  (we),
    .addr                (addr),
    .wdata               (wdata),
    .rdata               (rdata),

    .tmr_ctrl_en         (tmr_ctrl_en),
    .tmr_ctrl_oneshot    (tmr_ctrl_oneshot),
    .tmr_presc           (tmr_presc),
    .tmr_load            (tmr_load),
    .tmr_cmp             (tmr_cmp_val),
    .tmr_cnt_in          (tmr_cnt),
    .tmr_ovf_pulse_in    (tmr_ovf_pulse),
    .tmr_cmp_pulse_in    (tmr_cmp_pulse),

    .adc_ctrl_en         (adc_ctrl_en),
    .adc_start_pulse     (adc_start_pulse),
    .adc_trig_sel        (adc_trig_sel),
    .adc_ch_sel          (adc_ch_sel),
    .adc_smp             (adc_smp),
    .adc_div             (adc_div),
    .adc_busy_in         (adc_busy),
    .adc_result_code_in  (adc_result_code),
    .adc_result_valid_in (adc_done_pulse),

    .fifo_rd_data_in     (fifo_rd_data),
    .fifo_rd_en_out      (fifo_rd_en),
    .fifo_empty_in       (fifo_empty),
    .fifo_full_in        (fifo_full),
    .fifo_level_in       (fifo_level),

    .irq                 (irq)
  );

endmodule : timer_adc8_top
