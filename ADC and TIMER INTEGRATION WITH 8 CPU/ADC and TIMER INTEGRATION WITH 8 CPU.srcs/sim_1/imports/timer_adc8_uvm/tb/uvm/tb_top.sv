// =============================================================================
// File        : tb_top.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : Root UVM Simulation Top Module instantiating Clock/Reset,
//               apb_if, adc_if, timer_adc8_top (DUT), sar_afe_model,
//               bind_timer_adc_sva, and launching UVM run_test() (Chapter 12).
// =============================================================================

`timescale 1ns/1ps // Define simulation time unit (1ns) and precision (1ps)

module tb_top; // Declare root UVM testbench module

    import uvm_pkg::*;       // Import standard UVM library
    `include "uvm_macros.svh" // Include UVM macros
    import timer_adc_pkg::*; // Import our timer_adc_pkg verification package

    // -------------------------------------------------------------------------
    // Clock and Asynchronous Active-Low Reset Generation
    // -------------------------------------------------------------------------
    logic clk   = 1'b0;      // System clock initialized to 0 (100 MHz -> 10ns period)
    logic rst_n = 1'b0;      // Active-low reset initialized to 0 (asserted)

    always #5 clk = ~clk;    // Toggle clock every 5ns (10ns period)

    initial begin            // Reset release sequence
        rst_n = 1'b0;        // Assert active-low reset at time 0
        repeat (5) @(posedge clk); // Hold reset low for 5 clock cycles
        rst_n = 1'b1;        // Deassert reset to begin operation
    end                      // End of reset generator

    // -------------------------------------------------------------------------
    // Instantiate Bus and Analog Interfaces
    // -------------------------------------------------------------------------
    apb_if apb ( .clk(clk), .rst_n(rst_n) ); // 8-bit APB bus interface instance
    adc_if afe ( .clk(clk), .rst_n(rst_n) ); // Analog front-end interface instance

    // -------------------------------------------------------------------------
    // Instantiate Design Under Test (timer_adc8_top)
    // -------------------------------------------------------------------------
    timer_adc8_top dut (                     // Instantiate peripheral top-level DUT
        .clk        (clk),                   // Connect system clock
        .rst_n      (rst_n),                 // Connect active-low reset
        .psel       (apb.psel),              // Connect APB peripheral select
        .penable    (apb.penable),           // Connect APB enable phase
        .pwrite     (apb.pwrite),            // Connect APB write direction
        .paddr      (apb.paddr),             // Connect APB 4-bit register address
        .pwdata     (apb.pwdata),            // Connect APB 8-bit write data
        .prdata     (apb.prdata),            // Connect APB 8-bit read data
        .pready     (apb.pready),            // Connect APB ready output
        .pslverr    (apb.pslverr),           // Connect APB slave error output
        .irq        (apb.irq),               // Connect CPU interrupt output
        .pwm_out    (afe.pwm_out),           // Connect timer PWM output pin
        .adc_sample (afe.adc_sample),        // Connect AFE sample switch control
        .adc_ch     (afe.adc_ch),            // Connect AFE 2-bit channel select
        .adc_dac    (afe.adc_dac),           // Connect AFE 8-bit DAC trial bus
        .adc_cmp    (afe.adc_cmp)            // Connect AFE comparator output
    ); // End of DUT instantiation

    // Connect white-box event monitoring hooks for adc_monitor
    assign afe.adc_eoc_mon       = dut.adc_eoc;       // Observe ADC EOC pulse
    assign afe.adc_result_mon    = dut.adc_result;    // Observe 8-bit ADC result
    assign afe.adc_result_ch_mon = dut.adc_result_ch; // Observe 2-bit channel tag
    assign afe.tmr_ovf_mon       = dut.tmr_ovf_pulse; // Observe Timer overflow pulse
    assign afe.tmr_cmp_mon       = dut.tmr_cmp_pulse; // Observe Timer compare pulse

    // -------------------------------------------------------------------------
    // Instantiate Behavioral Analog Front-End (sar_afe_model) and SVA Bind
    // -------------------------------------------------------------------------
    sar_afe_model u_afe (                    // Instantiate analog circuit model
        .clk        (clk),                   // Connect clock
        .rst_n      (rst_n),                 // Connect reset
        .afe        (afe)                    // Connect analog interface bundle
    ); // End of AFE model instantiation

    bind_timer_adc_sva u_bind_sva();         // Bind 30 SVA rules into timer_adc8_top

    // -------------------------------------------------------------------------
    // Pass Virtual Interfaces via uvm_config_db and Start UVM Phases
    // -------------------------------------------------------------------------
    initial begin                            // UVM startup and waveform dump block
        if ($test$plusargs("DUMP")) begin    // Check if +DUMP command-line flag was given
            $dumpfile("tb_top.vcd");         // Create VCD waveform file (Chapter 16, Page 17)
            $dumpvars(0, tb_top);            // Dump all signals under tb_top hierarchy
        end                                  // End of optional VCD dump check

        // Register virtual interface handles in uvm_config_db for agents
        uvm_config_db#(virtual apb_if)::set(null, "*.apb_agt.*", "vif", apb); // Pass apb_if
        uvm_config_db#(virtual adc_if)::set(null, "*.adc_agt.*", "vif", afe); // Pass adc_if

        // Launch UVM test specified by +UVM_TESTNAME=... (defaults to tadc_all_test)
        run_test("tadc_all_test");           // Execute build -> connect -> run -> check -> report
    end                                      // End of initial block

endmodule // End of tb_top module
