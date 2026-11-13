// =============================================================================
// File        : timer_adc_sva.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : 30 SystemVerilog Assertions (SVA) verifying Timer, SAR ADC,
//               FIFO, Registers, and Interrupt rules on every clock edge.
//               Includes all 6 named bug-catching assertions from Chapter 15.
// =============================================================================

`timescale 1ns/1ps // Define simulation time unit (1ns) and precision (1ps)

module timer_adc_sva ( // Declare SVA checker module bound inside timer_adc8_top
    input logic       clk,            // System clock
    input logic       rst_n,          // Asynchronous active-low reset
    // APB Bus Signals
    input logic       psel,           // APB peripheral select
    input logic       penable,        // APB enable phase
    input logic       pwrite,         // APB write direction
    input logic [3:0] paddr,          // APB 4-bit register address
    input logic [7:0] pwdata,         // APB 8-bit write data
    input logic [7:0] prdata,         // APB 8-bit read data
    input logic       pready,         // APB ready output
    input logic       pslverr,        // APB slave error output
    // Timer Internal Signals
    input logic       tmr_en,         // Timer enable register bit
    input logic       tmr_oneshot,    // Timer one-shot mode bit
    input logic [7:0] tmr_presc,      // Timer prescaler setting
    input logic [7:0] tmr_load,       // Timer reload limit setting
    input logic [7:0] tmr_cmp,        // Timer compare threshold setting
    input logic [7:0] tmr_cnt,        // Current timer 8-bit count
    input logic       tmr_ovf_pulse,  // Timer overflow pulse
    input logic       tmr_cmp_pulse,  // Timer compare match pulse
    input logic       tmr_clr_en,     // One-shot auto-disable pulse
    input logic       pwm_out,        // Timer PWM output pin
    // SAR ADC Internal Signals
    input logic       adc_en,         // ADC enable register bit
    input logic       adc_cont,       // ADC continuous mode flag
    input logic       adc_start_trig, // ADC start trigger pulse
    input logic [1:0] adc_ch_sel,     // Configured ADC channel
    input logic [7:0] adc_smp,        // Configured sample duration
    input logic [7:0] adc_div,        // Configured clock divider
    input logic       adc_busy,       // ADC busy status flag
    input logic       adc_eoc,        // ADC end-of-conversion pulse
    input logic [7:0] adc_result,     // ADC 8-bit digital result
    input logic [1:0] adc_result_ch,  // ADC 2-bit channel tag
    input logic       adc_trig_miss,  // ADC trigger-missed pulse
    input logic       adc_sample,     // AFE sample switch control
    input logic [1:0] adc_ch,         // AFE mux channel select
    input logic [7:0] adc_dac,        // AFE 8-bit DAC trial code
    input logic       adc_cmp,        // AFE comparator input
    // FIFO & Interrupt Signals
    input logic [9:0] fifo_dout,      // Oldest FIFO entry
    input logic       fifo_empty,     // FIFO empty flag
    input logic       fifo_full,      // FIFO full flag
    input logic [3:0] fifo_level,     // FIFO occupancy count (0..8)
    input logic       fifo_ovr_pulse, // FIFO overflow pulse
    input logic       fifo_pop,       // FIFO pop pulse
    input logic [5:0] irq_en,         // 6-bit interrupt enable register
    input logic [5:0] irq_stat,       // 6-bit sticky interrupt status register
    input logic [7:0] adc_thr_lo,     // Window low threshold register
    input logic [7:0] adc_thr_hi,     // Window high threshold register
    input logic       irq             // External CPU interrupt output
); // End of port list

    // -------------------------------------------------------------------------
    // Helper Tracking Counters for Multi-Cycle SVA Verification
    // -------------------------------------------------------------------------
    int unsigned sample_clk_cnt;      // Counts clocks spent with adc_sample == 1
    int unsigned conv_clk_cnt;        // Counts total clocks spent in active conversion
    int unsigned exp_sample_clks;     // Expected sample phase clocks = (SMP + 1) * (DIV + 1)
    int unsigned exp_conv_clks;       // Expected total conversion clocks = (SMP + 1 + 8) * (DIV + 1)
    logic        load_changed;        // Tracks dynamic write to TMR_LOAD while timer is running

    always_ff @(posedge clk or negedge rst_n) begin // Track multi-cycle conversion timing
        if (!rst_n || !adc_en) begin                // Reset counters when reset or ADC disabled
            sample_clk_cnt  <= 0;                   // Clear sample phase clock counter
            conv_clk_cnt    <= 0;                   // Clear total conversion clock counter
            exp_sample_clks <= 5;                   // Default expected sample clocks (4+1)*1
            exp_conv_clks   <= 13;                  // Default expected total clocks (4+1+8)*1
        end else begin                              // ADC is enabled
            if (!adc_busy && (adc_start_trig || adc_cont)) begin // Conversion launch from IDLE
                sample_clk_cnt  <= 0;               // Reset sample clock counter
                conv_clk_cnt    <= 0;               // Reset conversion clock counter
                exp_sample_clks <= (int'(adc_smp) + 1) * (int'(adc_div) + 1);     // Latch expected sample width
                exp_conv_clks   <= (int'(adc_smp) + 1 + 8) * (int'(adc_div) + 1); // Latch expected total time
            end else if (adc_busy) begin            // Conversion is currently in progress
                if (adc_eoc && adc_cont) begin      // Continuous mode restart at EOC
                    sample_clk_cnt  <= 1;           // First sample clock of new continuous cycle
                    conv_clk_cnt    <= 1;           // First total clock of new continuous cycle
                    exp_sample_clks <= (int'(adc_smp) + 1) * (int'(adc_div) + 1);     // Refresh sample width
                    exp_conv_clks   <= (int'(adc_smp) + 1 + 8) * (int'(adc_div) + 1); // Refresh total time
                end else begin                      // Normal tick inside active conversion
                    conv_clk_cnt <= conv_clk_cnt + 1; // Increment total conversion clock count
                    if (adc_sample) begin           // If still in SAMPLE state
                        sample_clk_cnt <= sample_clk_cnt + 1; // Increment sample window clock count
                    end                             // End of adc_sample check
                end                                 // End of continuous restart check
            end                                     // End of adc_busy check
        end                                         // End of synchronous tracking
    end                                             // End of timing tracker block

    always_ff @(posedge clk or negedge rst_n) begin // Track dynamic updates to TMR_LOAD
        if (!rst_n || !tmr_en) begin                // Clear flag when timer is off
            load_changed <= 1'b0;                   // No dynamic load change pending
        end else if (psel && penable && pwrite && (paddr == 4'h2)) begin // Write to TMR_LOAD
            load_changed <= 1'b1;                   // Mark that software modified TMR_LOAD mid-run
        end else if (tmr_ovf_pulse) begin           // Clear flag once timer wraps cleanly
            load_changed <= 1'b0;                   // Counter is back in range [0..tmr_load]
        end                                         // End of load_changed tracker
    end                                             // End of always_ff block

    // =========================================================================
    // GROUP 1: The 6 Named Bug-Catching Assertions from Chapter 15 (Page 16)
    // =========================================================================

    // 1. a_cnt_le_load: Timer counter must never exceed TMR_LOAD (unless software just lowered LOAD)
    property p_cnt_le_load;                                                  // Declare SVA property p_cnt_le_load
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (tmr_en && !load_changed) |-> (tmr_cnt <= tmr_load);                 // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_cnt_le_load: assert property (p_cnt_le_load)                           // Assert property a_cnt_le_load on every clock
        else $error("[SVA a_cnt_le_load] Timer counter (%0d) exceeded LOAD (%0d)!", tmr_cnt, tmr_load); // Report assertion failure message

    // 2. a_conv_time: Total conversion time from start to EOC must equal (SMP + 1 + 8) * (DIV + 1)
    property p_conv_time;                                                    // Declare SVA property p_conv_time
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (adc_eoc && adc_en) |-> (conv_clk_cnt == exp_conv_clks);             // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_conv_time: assert property (p_conv_time)                               // Assert property a_conv_time on every clock
        else $error("[SVA a_conv_time] Conversion time (%0d) != expected (%0d)!", conv_clk_cnt, exp_conv_clks); // Report failure

    // 3. a_overflow_drop: When FIFO is full and EOC occurs without pop, level stays 8 and FIFO_OVR sets
    property p_overflow_drop;                                                // Declare SVA property p_overflow_drop
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (adc_eoc && fifo_full && !fifo_pop) |=> (fifo_level == 4'd8) && (irq_stat[4] == 1'b1); // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_overflow_drop: assert property (p_overflow_drop)                       // Assert property a_overflow_drop on every clock
        else $error("[SVA a_overflow_drop] FIFO accepted entry while full or failed to set FIFO_OVR!"); // Report failure

    // 4. a_oneshot_stop: In one-shot mode, timer overflow must stop the timer (clear tmr_en)
    property p_oneshot_stop;                                                 // Declare SVA property p_oneshot_stop
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (tmr_en && tmr_oneshot && tmr_ovf_pulse && !(psel && penable && pwrite && paddr == 4'h0)) // Trigger condition
        |=> (tmr_en == 1'b0) && (tmr_cnt == 8'h00);                          // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_oneshot_stop: assert property (p_oneshot_stop)                         // Assert property a_oneshot_stop on every clock
        else $error("[SVA a_oneshot_stop] One-shot mode did not stop timer after overflow!"); // Report failure

    // 5. a_sample_width: Sample window duration must equal exactly (SMP + 1) * (DIV + 1) clocks
    property p_sample_width;                                                 // Declare SVA property p_sample_width
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        ($fell(adc_sample) && adc_en && adc_busy) |-> (sample_clk_cnt == exp_sample_clks); // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_sample_width: assert property (p_sample_width)                         // Assert property a_sample_width on every clock
        else $error("[SVA a_sample_width] Sample window (%0d) != expected (%0d)!", sample_clk_cnt, exp_sample_clks); // Report failure

    // 6. a_cmp_match: Compare pulse must fire when counter was at TMR_CMP on the preceding tick
    property p_cmp_match;                                                    // Declare SVA property p_cmp_match
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        tmr_cmp_pulse |-> ($past(tmr_cnt) == $past(tmr_cmp)) && $past(tmr_en); // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_cmp_match: assert property (p_cmp_match)                               // Assert property a_cmp_match on every clock
        else $error("[SVA a_cmp_match] Compare pulse fired at wrong counter value!"); // Report failure

    // =========================================================================
    // GROUP 2: Timer & PWM Rules (Assertions 7 to 12)
    // =========================================================================

    // 7. Timer disabled state: counter and pulses must be zero when tmr_en == 0
    property p_tmr_off_zero;                                                 // Declare SVA property p_tmr_off_zero
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (!tmr_en && !$past(tmr_en)) |-> (tmr_cnt == 8'h00) && !tmr_ovf_pulse && !tmr_cmp_pulse; // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_tmr_off_zero: assert property (p_tmr_off_zero)                         // Assert property a_tmr_off_zero on every clock
        else $error("[SVA a_tmr_off_zero] Timer not zeroed while disabled!"); // Report failure

    // 8. PWM output low when timer disabled
    property p_pwm_low_when_disabled;                                        // Declare SVA property p_pwm_low_when_disabled
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (!tmr_en) |-> (pwm_out == 1'b0);                                     // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_pwm_low_when_disabled: assert property (p_pwm_low_when_disabled)       // Assert property a_pwm_low_when_disabled
        else $error("[SVA a_pwm_low_when_disabled] pwm_out high while timer disabled!"); // Report failure

    // 9. PWM output matches (tmr_cnt < tmr_cmp) when timer enabled
    property p_pwm_duty_rule;                                                // Declare SVA property p_pwm_duty_rule
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        tmr_en |-> (pwm_out == (tmr_cnt < tmr_cmp));                         // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_pwm_duty_rule: assert property (p_pwm_duty_rule)                       // Assert property a_pwm_duty_rule on every clock
        else $error("[SVA a_pwm_duty_rule] pwm_out does not match (cnt < cmp)!"); // Report failure

    // 10. Timer overflow pulse only fires when previous count reached LOAD
    property p_ovf_at_load;                                                  // Declare SVA property p_ovf_at_load
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        tmr_ovf_pulse |-> ($past(tmr_cnt) >= $past(tmr_load)) && (tmr_cnt == 8'h00); // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_ovf_at_load: assert property (p_ovf_at_load)                           // Assert property a_ovf_at_load on every clock
        else $error("[SVA a_ovf_at_load] Timer overflow did not wrap counter from LOAD to 0!"); // Report failure

    // 11. Timer overflow pulse is exactly 1 clock wide when PRESC > 0 or LOAD > 0
    property p_ovf_single_cycle;                                             // Declare SVA property p_ovf_single_cycle
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (tmr_ovf_pulse && ((tmr_presc > 8'h00) || (tmr_load > 8'h00))) |=> !tmr_ovf_pulse; // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_ovf_single_cycle: assert property (p_ovf_single_cycle)                 // Assert property a_ovf_single_cycle on every clock
        else $error("[SVA a_ovf_single_cycle] Timer overflow pulse stayed high for >1 cycle!"); // Report failure

    // 12. Timer compare pulse is 1 clock wide when PRESC > 0 or LOAD > 0
    property p_cmp_single_cycle;                                             // Declare SVA property p_cmp_single_cycle
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (tmr_cmp_pulse && ((tmr_presc > 8'h00) || (tmr_load > 8'h00))) |=> !tmr_cmp_pulse; // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_cmp_single_cycle: assert property (p_cmp_single_cycle)                 // Assert property a_cmp_single_cycle on every clock
        else $error("[SVA a_cmp_single_cycle] Timer compare pulse stayed high for >1 cycle!"); // Report failure

    // =========================================================================
    // GROUP 3: SAR ADC Controller Rules (Assertions 13 to 19)
    // =========================================================================

    // 13. Clearing ADC_CTRL.EN immediately aborts conversion on the next clock
    property p_adc_disable_abort;                                            // Declare SVA property p_adc_disable_abort
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (!adc_en) |=> (!adc_busy && !adc_sample && !adc_eoc && (adc_dac == 8'h00)); // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_adc_disable_abort: assert property (p_adc_disable_abort)               // Assert property a_adc_disable_abort
        else $error("[SVA a_adc_disable_abort] Clearing ADC_CTRL.EN failed to abort conversion!"); // Report failure

    // 14. adc_sample can only be asserted while adc_busy is high
    property p_sample_implies_busy;                                          // Declare SVA property p_sample_implies_busy
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        adc_sample |-> adc_busy;                                             // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_sample_implies_busy: assert property (p_sample_implies_busy)           // Assert property a_sample_implies_busy
        else $error("[SVA a_sample_implies_busy] adc_sample asserted while adc_busy is low!"); // Report failure

    // 15. DAC code is forced to 0x00 during the SAMPLE state
    property p_dac_zero_during_sample;                                       // Declare SVA property p_dac_zero_during_sample
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        adc_sample |-> (adc_dac == 8'h00);                                   // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_dac_zero_during_sample: assert property (p_dac_zero_during_sample)     // Assert property a_dac_zero_during_sample
        else $error("[SVA a_dac_zero_during_sample] adc_dac non-zero during sample phase!"); // Report failure

    // 16. First SAR guess on falling edge of adc_sample is always 0x80 (MSB = 128)
    property p_first_guess_msb;                                              // Declare SVA property p_first_guess_msb
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        ($fell(adc_sample) && adc_en && adc_busy) |-> (adc_dac == 8'h80);    // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_first_guess_msb: assert property (p_first_guess_msb)                   // Assert property a_first_guess_msb on every clock
        else $error("[SVA a_first_guess_msb] First SAR trial code was %02h instead of 0x80!", adc_dac); // Report failure

    // 17. EOC is always a single-cycle pulse
    property p_eoc_single_cycle;                                             // Declare SVA property p_eoc_single_cycle
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        adc_eoc |=> !adc_eoc;                                                // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_eoc_single_cycle: assert property (p_eoc_single_cycle)                 // Assert property a_eoc_single_cycle on every clock
        else $error("[SVA a_eoc_single_cycle] adc_eoc remained high for more than 1 clock!"); // Report failure

    // 18. Trigger arriving while ADC is busy must assert adc_trig_miss
    property p_trig_while_busy_miss;                                         // Declare SVA property p_trig_while_busy_miss
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (adc_en && adc_busy && adc_start_trig) |=> adc_trig_miss;            // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_trig_while_busy_miss: assert property (p_trig_while_busy_miss)         // Assert property a_trig_while_busy_miss
        else $error("[SVA a_trig_while_busy_miss] Trigger while busy did not pulse trig_miss!"); // Report failure

    // 19. Analog mux channel remains stable throughout the entire conversion
    property p_ch_stable_during_conv;                                        // Declare SVA property p_ch_stable_during_conv
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (adc_busy && $past(adc_busy) && !$past(adc_eoc)) |-> (adc_ch == $past(adc_ch)); // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_ch_stable_during_conv: assert property (p_ch_stable_during_conv)       // Assert property a_ch_stable_during_conv
        else $error("[SVA a_ch_stable_during_conv] Analog channel changed mid-conversion!"); // Report failure

    // =========================================================================
    // GROUP 4: Synchronous FIFO Rules (Assertions 20 to 24)
    // =========================================================================

    // 20. FIFO level never exceeds depth 8
    property p_fifo_level_range;                                             // Declare SVA property p_fifo_level_range
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (fifo_level <= 4'd8);                                                // Check FIFO occupancy <= 8
    endproperty                                                              // End of SVA property declaration
    a_fifo_level_range: assert property (p_fifo_level_range)                 // Assert property a_fifo_level_range on every clock
        else $error("[SVA a_fifo_level_range] FIFO level (%0d) exceeded maximum 8!", fifo_level); // Report failure

    // 21. FIFO empty flag matches (fifo_level == 0)
    property p_fifo_empty_flag;                                              // Declare SVA property p_fifo_empty_flag
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (fifo_empty == (fifo_level == 4'd0));                                // Verify empty flag consistency
    endproperty                                                              // End of SVA property declaration
    a_fifo_empty_flag: assert property (p_fifo_empty_flag)                   // Assert property a_fifo_empty_flag on every clock
        else $error("[SVA a_fifo_empty_flag] fifo_empty mismatch with fifo_level!"); // Report failure

    // 22. FIFO full flag matches (fifo_level == 8)
    property p_fifo_full_flag;                                               // Declare SVA property p_fifo_full_flag
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (fifo_full == (fifo_level == 4'd8));                                 // Verify full flag consistency
    endproperty                                                              // End of SVA property declaration
    a_fifo_full_flag: assert property (p_fifo_full_flag)                     // Assert property a_fifo_full_flag on every clock
        else $error("[SVA a_fifo_full_flag] fifo_full mismatch with fifo_level!"); // Report failure

    // 23. Push without pop when not full increments FIFO level by 1
    property p_fifo_push_inc;                                                // Declare SVA property p_fifo_push_inc
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (adc_eoc && !fifo_full && !(fifo_pop && !fifo_empty)) |=> (fifo_level == ($past(fifo_level) + 4'd1)); // Implication
    endproperty                                                              // End of SVA property declaration
    a_fifo_push_inc: assert property (p_fifo_push_inc)                       // Assert property a_fifo_push_inc on every clock
        else $error("[SVA a_fifo_push_inc] FIFO level did not increment on valid push!"); // Report failure

    // 24. Pop without push when not empty decrements FIFO level by 1
    property p_fifo_pop_dec;                                                 // Declare SVA property p_fifo_pop_dec
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (fifo_pop && !fifo_empty && !(adc_eoc && !fifo_full)) |=> (fifo_level == ($past(fifo_level) - 4'd1)); // Implication
    endproperty                                                              // End of SVA property declaration
    a_fifo_pop_dec: assert property (p_fifo_pop_dec)                         // Assert property a_fifo_pop_dec on every clock
        else $error("[SVA a_fifo_pop_dec] FIFO level did not decrement on valid pop!"); // Report failure

    // =========================================================================
    // GROUP 5: Register Map, Window Comparator & Interrupt Rules (Assertions 25 to 30)
    // =========================================================================

    // 25. Peripheral ID register (0xF) always reads back 0xA8
    property p_id_reg_constant;                                              // Declare SVA property p_id_reg_constant
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (psel && penable && !pwrite && (paddr == 4'hF)) |-> (prdata == 8'hA8); // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_id_reg_constant: assert property (p_id_reg_constant)                   // Assert property a_id_reg_constant on every clock
        else $error("[SVA a_id_reg_constant] ID register read %02h instead of 0xA8!", prdata); // Report failure

    // 26. ADC_CTRL.START bit (bit 1) always reads back as 0
    property p_start_reads_zero;                                             // Declare SVA property p_start_reads_zero
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (psel && penable && !pwrite && (paddr == 4'h5)) |-> (prdata[1] == 1'b0); // Implication condition
    endproperty                                                              // End of SVA property declaration
    a_start_reads_zero: assert property (p_start_reads_zero)                 // Assert property a_start_reads_zero on every clock
        else $error("[SVA a_start_reads_zero] ADC_CTRL.START read back as 1!"); // Report failure

    // 27. Reading ADC_RCH (0xB) never pops the FIFO
    property p_rch_read_no_pop;                                              // Declare SVA property p_rch_read_no_pop
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (psel && penable && !pwrite && (paddr == 4'hB)) |-> !fifo_pop;       // Implication condition for SVA property check
    endproperty                                                              // End of SVA property declaration
    a_rch_read_no_pop: assert property (p_rch_read_no_pop)                   // Assert property a_rch_read_no_pop on every clock
        else $error("[SVA a_rch_read_no_pop] Reading ADC_RCH erroneously popped the FIFO!"); // Report failure

    // 28. Window comparator sets IRQ_STAT[3] (ADC_WD) when result < THR_LO or result > THR_HI
    property p_window_watchdog_flag;                                         // Declare SVA property p_window_watchdog_flag
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (adc_eoc && ((adc_result < adc_thr_lo) || (adc_result > adc_thr_hi))) |=> (irq_stat[3] == 1'b1); // Implication
    endproperty                                                              // End of SVA property declaration
    a_window_watchdog_flag: assert property (p_window_watchdog_flag)         // Assert property a_window_watchdog_flag
        else $error("[SVA a_window_watchdog_flag] Out-of-window result failed to set ADC_WD flag!"); // Report failure

    // 29. Hardware event wins over simultaneous CPU W1C clear on IRQ_STAT
    property p_hw_priority_over_w1c;                                         // Declare SVA property p_hw_priority_over_w1c
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (adc_eoc && psel && penable && pwrite && (paddr == 4'hE) && pwdata[2]) |=> (irq_stat[2] == 1'b1); // Implication
    endproperty                                                              // End of SVA property declaration
    a_hw_priority_over_w1c: assert property (p_hw_priority_over_w1c)         // Assert property a_hw_priority_over_w1c
        else $error("[SVA a_hw_priority_over_w1c] CPU W1C clear overwrote simultaneous ADC_EOC event!"); // Report failure

    // 30. External irq wire equals OR-reduction of (irq_stat & irq_en)
    property p_irq_line_equation;                                            // Declare SVA property p_irq_line_equation
        @(posedge clk) disable iff (!rst_n)                                  // Sample on rising clock edge unless reset is active
        (irq == |(irq_stat & irq_en));                                       // Verify interrupt pin logic equation
    endproperty                                                              // End of SVA property declaration
    a_irq_line_equation: assert property (p_irq_line_equation)               // Assert property a_irq_line_equation on every clock
        else $error("[SVA a_irq_line_equation] irq output does not match |(irq_stat & irq_en)!"); // Report failure

endmodule // End of timer_adc_sva checker module
