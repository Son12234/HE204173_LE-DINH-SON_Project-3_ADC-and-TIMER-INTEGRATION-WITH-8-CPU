// =============================================================================
// File   : sar_adc_ctrl.sv
// Purpose: Drives a classic successive-approximation conversion over the
//          block diagram's analog pins (adc_sample / adc_ch / adc_dac /
//          adc_cmp). This module only decides *when* and *which channel* to
//          convert; the top-level timer_adc8_top.sv decides *what triggers*
//          a conversion (software START vs. timer-overflow trigger) and
//          wires 'start' accordingly.
//
//          Sequence for one conversion:
//            TRACK : hold adc_sample=1 for (smp_cycles+1) SAR-clock ticks so
//                    the external analog front end can settle on the input
//                    (guide register ADC_SMP = "sample window - 1").
//            SEARCH: 8 bit-serial steps, MSB first. Each step tries setting
//                    the next-lower bit, waits one SAR-clock tick for the
//                    comparator to respond, and keeps the bit only if
//                    adc_cmp says the DAC guess did not overshoot the held
//                    sample (adc_cmp = 1 means "DAC code too high").
//          The whole state machine runs on a divided "SAR clock" derived
//          from div_cycles (guide register ADC_DIV), so ADC_SMP/ADC_DIV
//          directly control conversion time exactly as the guide describes.
// =============================================================================
module sar_adc_ctrl (
  input  logic       clk,
  input  logic       rst_n,         // asynchronous, active-low

  // ---- trigger interface (from timer_adc8_top.sv) ----
  input  logic       start,         // 1-clock pulse: begin one conversion
  input  logic [1:0] channel_sel,   // which of the 4 analog channels to sample, latched at 'start'

  // ---- register-file inputs (ADC_SMP / ADC_DIV) ----
  input  logic [7:0] smp_cycles,    // track-phase length - 1, in SAR-clock ticks
  input  logic [7:0] div_cycles,    // SAR-clock divider: one tick every (div_cycles+1) system clocks

  // ---- analog front-end pins (block diagram: adc_sample/ch/dac/cmp) ----
  output logic       adc_sample,    // 1 while tracking: tells the AFE to sample/hold the input
  output logic [1:0] adc_ch,        // channel mux select to the AFE
  output logic [7:0] adc_dac,       // current DAC trial code, compared against the held sample
  input  logic       adc_cmp,       // 1 = DAC code is higher than the held sample ("too high")

  // ---- status / result ----
  output logic       busy,
  output logic        done_pulse,   // 1 clock wide: result_code/result_ch are valid this cycle
  output logic [7:0]   result_code,
  output logic [1:0]    result_ch
);

  typedef enum logic [1:0] { ST_IDLE, ST_TRACK, ST_SEARCH, ST_DONE } state_e;
  state_e state;

  // ---- SAR-clock divider: produces 'sar_tick' every (div_cycles+1) clocks ----
  logic [7:0] div_cnt;
  logic       sar_tick;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_cnt  <= '0;
      sar_tick <= 1'b0;
    end else if (state == ST_IDLE) begin
      div_cnt  <= '0;              // keep the divider parked at 0 while idle
      sar_tick <= 1'b0;
    end else if (div_cnt == div_cycles) begin
      div_cnt  <= '0;
      sar_tick <= 1'b1;
    end else begin
      div_cnt  <= div_cnt + 1'b1;
      sar_tick <= 1'b0;
    end
  end

  logic [7:0] track_cnt;    // counts elapsed SAR-clock ticks during TRACK
  logic [3:0] bit_idx;      // 7 downto 0 during SEARCH, one step per sar_tick
  logic [7:0] dac_reg;      // the DAC trial code being refined bit by bit
  logic [1:0] ch_latched;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= ST_IDLE;
      track_cnt   <= '0;
      bit_idx     <= '0;
      dac_reg     <= '0;
      ch_latched  <= '0;
      result_code <= '0;
      result_ch   <= '0;
      done_pulse  <= 1'b0;
    end else begin
      done_pulse <= 1'b0;   // default: only pulsed for exactly one cycle below

      unique case (state)

        ST_IDLE: begin
          if (start) begin
            state      <= ST_TRACK;
            ch_latched <= channel_sel;
            track_cnt  <= '0;
          end
        end

        ST_TRACK: begin
          if (sar_tick) begin
            if (track_cnt == smp_cycles) begin
              // Sampling window complete: start the search at the MSB,
              // trying it set (classic SAR first guess = 1000_0000).
              state     <= ST_SEARCH;
              bit_idx   <= 4'd7;
              dac_reg   <= 8'b1000_0000;
            end else begin
              track_cnt <= track_cnt + 1'b1;
            end
          end
        end

        ST_SEARCH: begin
          if (sar_tick) begin
            // Resolve the bit we guessed last step: adc_cmp=1 means the
            // trial DAC code overshot the held sample, so clear that bit;
            // otherwise keep it set (it was a correct guess).
            if (adc_cmp)
              dac_reg[bit_idx] <= 1'b0;

            if (bit_idx == 4'd0) begin
              state <= ST_DONE;
            end else begin
              bit_idx          <= bit_idx - 4'd1;
              dac_reg[bit_idx-4'd1] <= 1'b1;   // next trial guess
            end
          end
        end

        ST_DONE: begin
          result_code <= dac_reg;
          result_ch   <= ch_latched;
          done_pulse  <= 1'b1;
          state       <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  assign busy       = (state != ST_IDLE);
  assign adc_sample = (state == ST_TRACK);
  assign adc_ch      = (state == ST_IDLE) ? channel_sel : ch_latched;
  assign adc_dac      = dac_reg;

endmodule : sar_adc_ctrl
