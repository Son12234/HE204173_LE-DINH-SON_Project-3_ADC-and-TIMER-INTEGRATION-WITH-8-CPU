// =============================================================================
// File   : apb_regs8.sv
// Purpose: The bus-facing half of the peripheral: decodes the 4-bit
//          register-within-page address, holds every read/write register in
//          the memory map (guide chapter 2 table), and implements the two
//          special read/write side effects the guide calls out explicitly:
//            - ADC_DATA is "RO, pop": reading it also pops the FIFO.
//            - IRQ_STAT is "W1C": writing a 1 to a bit clears it; a fresh
//              event pulse arriving the same cycle still sets its bit (a
//              same-cycle clear of one bit never swallows a brand-new event
//              on another bit, or even on the same bit).
//          Single-cycle bus: cs/we/addr/wdata are already stable for one
//          whole clock (they come straight from the CPU core's EX/MEM
//          pipeline register), and rdata must come back combinationally
//          this same cycle -- exactly the timing the guide's own waveform
//          chapter shows.
// =============================================================================
import risc8_pkg::*;

module apb_regs8 (
  input  logic        clk,
  input  logic        rst_n,          // asynchronous, active-low

  // ---- CPU-facing bus (register-within-page address only; the page
  //      decode itself already happened in the CPU core) ----
  input  logic        cs,
  input  logic        we,
  input  logic [3:0]  addr,
  input  logic [7:0]  wdata,
  output logic [7:0]  rdata,

  // ---- timer8.sv interface ----
  output logic        tmr_ctrl_en,
  output logic        tmr_ctrl_oneshot,
  output logic [7:0]  tmr_presc,
  output logic [7:0]  tmr_load,
  output logic [7:0]  tmr_cmp,
  input  logic [7:0]  tmr_cnt_in,
  input  logic        tmr_ovf_pulse_in,
  input  logic        tmr_cmp_pulse_in,

  // ---- sar_adc_ctrl.sv interface ----
  output logic        adc_ctrl_en,
  output logic        adc_start_pulse,  // live value of the self-clearing START bit
  output logic [1:0]  adc_trig_sel,
  output logic [1:0]  adc_ch_sel,
  output logic [7:0]  adc_smp,
  output logic [7:0]  adc_div,
  input  logic        adc_busy_in,
  input  logic [7:0]  adc_result_code_in,
  input  logic        adc_result_valid_in,   // = sar_adc_ctrl.done_pulse

  // ---- sync_fifo.sv interface ----
  input  logic [9:0]  fifo_rd_data_in,       // {channel[1:0], code[7:0]} peek of the oldest entry
  output logic        fifo_rd_en_out,        // pulsed when ADC_DATA is read: pops the FIFO
  input  logic        fifo_empty_in,
  input  logic        fifo_full_in,
  input  logic [3:0]  fifo_level_in,

  // ---- IRQ pin to the top-level peripheral wrapper ----
  output logic         irq
);

  // ---------------------------------------------------------------------
  // RW register storage
  // ---------------------------------------------------------------------
  logic        tmr_ctrl_en_r, tmr_ctrl_oneshot_r;
  logic [7:0]  tmr_presc_r, tmr_load_r, tmr_cmp_r;

  logic        adc_ctrl_en_r;
  logic [1:0]  adc_trig_sel_r, adc_ch_sel_r;
  logic        adc_start_live_r;            // high for exactly 1 cycle after a qualifying START write
  logic [7:0]  adc_smp_r, adc_div_r, adc_thr_lo_r, adc_thr_hi_r;

  logic [3:0]  irq_en_r;
  logic [3:0]  irq_stat_r;

  // ---------------------------------------------------------------------
  // ADC watchdog: out-of-window detection against the stored thresholds.
  // Combinational, fed by the latest conversion result pulse.
  // ---------------------------------------------------------------------
  logic wd_event;
  assign wd_event = adc_result_valid_in &&
                     ((adc_result_code_in < adc_thr_lo_r) || (adc_result_code_in > adc_thr_hi_r));

  // Write-1-to-clear mask: only live the one cycle IRQ_STAT is actually written.
  logic [3:0] w1c_mask;
  assign w1c_mask = (cs && we && (addr == REG_IRQ_STAT)) ? wdata[3:0] : 4'b0000;

  // ---------------------------------------------------------------------
  // Register writes (and the IRQ_STAT sticky-set / W1C-clear logic)
  // ---------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tmr_ctrl_en_r    <= 1'b0;
      tmr_ctrl_oneshot_r <= 1'b0;
      tmr_presc_r      <= 8'h00;
      tmr_load_r       <= 8'h00;
      tmr_cmp_r        <= 8'h00;

      adc_ctrl_en_r    <= 1'b0;
      adc_trig_sel_r   <= 2'b00;
      adc_ch_sel_r     <= 2'b00;
      adc_start_live_r <= 1'b0;
      adc_smp_r        <= 8'h00;
      adc_div_r        <= 8'h00;
      adc_thr_lo_r     <= 8'h00;
      adc_thr_hi_r     <= 8'h00;

      irq_en_r         <= 4'h0;
      irq_stat_r       <= 4'h0;
    end else begin
      // START is a one-shot strobe: it reflects the write that just
      // happened and is gone again next cycle unless re-written.
      adc_start_live_r <= (cs && we && (addr == REG_ADC_CTRL)) ? wdata[ADC_CTRL_BIT_START] : 1'b0;

      if (cs && we) begin
        unique case (addr)
          REG_TMR_CTRL: begin
            tmr_ctrl_en_r      <= wdata[TMR_CTRL_BIT_EN];
            tmr_ctrl_oneshot_r <= wdata[TMR_CTRL_BIT_ONESHOT];
          end
          REG_TMR_PRESC: tmr_presc_r <= wdata;
          REG_TMR_LOAD:  tmr_load_r  <= wdata;
          REG_TMR_CMP:   tmr_cmp_r   <= wdata;
          // REG_TMR_CNT is read-only: write silently ignored.

          REG_ADC_CTRL: begin
            adc_ctrl_en_r  <= wdata[ADC_CTRL_BIT_EN];
            adc_trig_sel_r <= wdata[ADC_CTRL_TRIGSEL_HI:ADC_CTRL_TRIGSEL_LO];
            adc_ch_sel_r   <= wdata[ADC_CTRL_CH_HI:ADC_CTRL_CH_LO];
            // START itself is handled above (self-clearing strobe).
          end
          REG_ADC_SMP:    adc_smp_r    <= wdata;
          REG_ADC_DIV:    adc_div_r    <= wdata;
          REG_ADC_THR_LO: adc_thr_lo_r <= wdata;
          REG_ADC_THR_HI: adc_thr_hi_r <= wdata;
          // REG_ADC_DATA, REG_ADC_RCH, REG_ADC_STAT, REG_ID are read-only:
          // writes silently ignored. REG_IRQ_STAT is handled below.
          REG_IRQ_EN: irq_en_r <= wdata[3:0];
          default: ; // unmapped / read-only address: ignore the write
        endcase
      end

      // IRQ_STAT: each bit is independently sticky-set by its event pulse
      // and cleared by writing a 1 to it; a same-cycle event always wins
      // over a same-cycle clear so a brand-new event is never lost.
      irq_stat_r[IRQ_BIT_TMR_OVF] <= (irq_stat_r[IRQ_BIT_TMR_OVF] && !w1c_mask[IRQ_BIT_TMR_OVF]) || tmr_ovf_pulse_in;
      irq_stat_r[IRQ_BIT_TMR_CMP] <= (irq_stat_r[IRQ_BIT_TMR_CMP] && !w1c_mask[IRQ_BIT_TMR_CMP]) || tmr_cmp_pulse_in;
      irq_stat_r[IRQ_BIT_ADC_EOC] <= (irq_stat_r[IRQ_BIT_ADC_EOC] && !w1c_mask[IRQ_BIT_ADC_EOC]) || adc_result_valid_in;
      irq_stat_r[IRQ_BIT_ADC_WD]  <= (irq_stat_r[IRQ_BIT_ADC_WD]  && !w1c_mask[IRQ_BIT_ADC_WD])  || wd_event;
    end
  end

  // ---------------------------------------------------------------------
  // Register reads (combinational: single-cycle bus)
  // ---------------------------------------------------------------------
  always_comb begin
    unique case (addr)
      REG_TMR_CTRL:   rdata = {6'b0, tmr_ctrl_oneshot_r, tmr_ctrl_en_r};
      REG_TMR_PRESC:  rdata = tmr_presc_r;
      REG_TMR_LOAD:   rdata = tmr_load_r;
      REG_TMR_CMP:    rdata = tmr_cmp_r;
      REG_TMR_CNT:    rdata = tmr_cnt_in;
      REG_ADC_CTRL:   rdata = {2'b0, adc_ch_sel_r, adc_trig_sel_r, adc_start_live_r, adc_ctrl_en_r};
      REG_ADC_SMP:    rdata = adc_smp_r;
      REG_ADC_DIV:    rdata = adc_div_r;
      REG_ADC_THR_LO: rdata = adc_thr_lo_r;
      REG_ADC_THR_HI: rdata = adc_thr_hi_r;
      REG_ADC_DATA:   rdata = fifo_rd_data_in[7:0];                       // pop: code field
      REG_ADC_RCH:    rdata = {!fifo_empty_in, 5'b0, fifo_rd_data_in[9:8]}; // peek: VALID + channel
      REG_ADC_STAT:   rdata = {1'b0, adc_busy_in, fifo_full_in, fifo_empty_in, fifo_level_in};
      REG_IRQ_EN:     rdata = {4'b0, irq_en_r};
      REG_IRQ_STAT:   rdata = {4'b0, irq_stat_r};
      REG_ID:         rdata = PERIPH_ID_VALUE;
      default:        rdata = 8'h00;
    endcase
  end

  // A read of ADC_DATA (and only ADC_DATA) pops the FIFO this cycle.
  assign fifo_rd_en_out = cs && !we && (addr == REG_ADC_DATA);

  // ---------------------------------------------------------------------
  // Output port connections
  // ---------------------------------------------------------------------
  assign tmr_ctrl_en      = tmr_ctrl_en_r;
  assign tmr_ctrl_oneshot = tmr_ctrl_oneshot_r;
  assign tmr_presc        = tmr_presc_r;
  assign tmr_load         = tmr_load_r;
  assign tmr_cmp          = tmr_cmp_r;

  assign adc_ctrl_en     = adc_ctrl_en_r;
  assign adc_start_pulse = adc_start_live_r;
  assign adc_trig_sel    = adc_trig_sel_r;
  assign adc_ch_sel      = adc_ch_sel_r;
  assign adc_smp         = adc_smp_r;
  assign adc_div         = adc_div_r;

  assign irq = |(irq_stat_r & irq_en_r);

endmodule : apb_regs8
