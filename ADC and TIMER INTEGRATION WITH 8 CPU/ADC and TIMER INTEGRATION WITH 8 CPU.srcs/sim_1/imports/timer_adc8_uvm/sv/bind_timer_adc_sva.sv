// =============================================================================
// File        : bind_timer_adc_sva.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : Dedicated SystemVerilog Bind Wrapper Module that attaches the
//               30 assertions in timer_adc_sva into timer_adc8_top without
//               modifying the RTL (Chapter 12 Diagram, Page 13).
// =============================================================================

`timescale 1ns/1ps // Define simulation time unit (1ns) and precision (1ps)

`ifndef BIND_TIMER_ADC_SVA_SV // Guard against duplicate compilation if included multiple times
`define BIND_TIMER_ADC_SVA_SV // Mark bind_timer_adc_sva.sv as compiled

module bind_timer_adc_sva; // Declare helper module instantiated in tb_top, tb_directed, and tb_cpu_if

    bind timer_adc8_top timer_adc_sva u_sva ( // Bind timer_adc_sva checker into timer_adc8_top
        .clk            (clk),                // Bind system clock
        .rst_n          (rst_n),              // Bind active-low reset
        .psel           (psel),               // Bind APB peripheral select
        .penable        (penable),            // Bind APB enable phase
        .pwrite         (pwrite),             // Bind APB write control
        .paddr          (paddr),              // Bind APB 4-bit register address
        .pwdata         (pwdata),             // Bind APB 8-bit write data
        .prdata         (prdata),             // Bind APB 8-bit read data
        .pready         (pready),             // Bind APB ready status
        .pslverr        (pslverr),            // Bind APB slave error status
        .tmr_en         (tmr_en),             // Bind timer enable bit
        .tmr_oneshot    (tmr_oneshot),        // Bind timer one-shot mode bit
        .tmr_presc      (tmr_presc),          // Bind timer prescaler value
        .tmr_load       (tmr_load),           // Bind timer reload value
        .tmr_cmp        (tmr_cmp),            // Bind timer compare value
        .tmr_cnt        (tmr_cnt),            // Bind current timer count
        .tmr_ovf_pulse  (tmr_ovf_pulse),      // Bind timer overflow pulse
        .tmr_cmp_pulse  (tmr_cmp_pulse),      // Bind timer compare pulse
        .tmr_clr_en     (tmr_clr_en),         // Bind timer one-shot auto-clear pulse
        .pwm_out        (pwm_out),            // Bind timer PWM output pin
        .adc_en         (adc_en),             // Bind ADC enable bit
        .adc_cont       (adc_cont),           // Bind ADC continuous mode flag
        .adc_start_trig (adc_start_trig),     // Bind ADC start trigger pulse
        .adc_ch_sel     (adc_ch_sel),         // Bind ADC channel selection
        .adc_smp        (adc_smp),            // Bind ADC sample duration
        .adc_div        (adc_div),            // Bind ADC clock divider
        .adc_busy       (adc_busy),           // Bind ADC busy status flag
        .adc_eoc        (adc_eoc),            // Bind ADC End-Of-Conversion pulse
        .adc_result     (adc_result),         // Bind ADC 8-bit conversion result
        .adc_result_ch  (adc_result_ch),      // Bind ADC 2-bit channel tag
        .adc_trig_miss  (adc_trig_miss),      // Bind ADC trigger-missed pulse
        .adc_sample     (adc_sample),         // Bind AFE sample switch control
        .adc_ch         (adc_ch),             // Bind AFE analog mux select
        .adc_dac        (adc_dac),            // Bind AFE 8-bit DAC trial bus
        .adc_cmp        (adc_cmp),            // Bind AFE comparator output
        .fifo_dout      (fifo_dout),          // Bind oldest FIFO entry
        .fifo_empty     (fifo_empty),         // Bind FIFO empty status flag
        .fifo_full      (fifo_full),          // Bind FIFO full status flag
        .fifo_level     (fifo_level),         // Bind FIFO occupancy level
        .fifo_ovr_pulse (fifo_ovr_pulse),     // Bind FIFO overflow pulse
        .fifo_pop       (fifo_pop),           // Bind FIFO pop request pulse
        .irq_en         (u_regs.irq_en),      // Bind internal IRQ_EN register
        .irq_stat       (u_regs.irq_stat),    // Bind internal IRQ_STAT register
        .adc_thr_lo     (u_regs.adc_thr_lo),  // Bind internal ADC_THR_LO register
        .adc_thr_hi     (u_regs.adc_thr_hi),  // Bind internal ADC_THR_HI register
        .irq            (irq)                 // Bind external CPU interrupt wire
    ); // End of SystemVerilog bind statement

endmodule // End of bind_timer_adc_sva module

`endif // End of BIND_TIMER_ADC_SVA_SV include guard
