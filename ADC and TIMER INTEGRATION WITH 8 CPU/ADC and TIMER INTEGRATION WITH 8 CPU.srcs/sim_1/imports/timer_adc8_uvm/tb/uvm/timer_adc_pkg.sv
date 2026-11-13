// =============================================================================
// File        : timer_adc_pkg.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : UVM Package File that imports uvm_pkg and `includes all 8
//               UVM verification files in strict dependency order
//               (Chapter 12 Diagram, Page 13).
//               Defines INSIDE_TIMER_ADC_PKG so all 10 files in tb/uvm/ can be
//               added directly to Vivado Simulation Sources without duplicate
//               compilation errors.
// =============================================================================

`timescale 1ns/1ps // Define simulation time unit (1ns) and precision (1ps)

package timer_adc_pkg; // Declare verification package imported by tb_top.sv

    import uvm_pkg::*;       // Import standard Accellera / Vivado UVM class library
    `include "uvm_macros.svh" // Include standard UVM preprocessor macros

    `define INSIDE_TIMER_ADC_PKG // Enable compilation of the 8 included UVM files below

    // -------------------------------------------------------------------------
    // Include All 8 UVM Files in Exact Dependency Order (Chapter 12, Page 13)
    // -------------------------------------------------------------------------
    `include "apb_agent.sv"            // 1. Talks on the 8-bit register bus
    `include "adc_agent.sv"            // 2. Drives voltages, watches analog/timer events
    `include "timer_adc_ral.sv"        // 3. Software copy (RAL) of the 16 registers
    `include "timer_adc_scoreboard.sv" // 4. Predicts and checks results & FIFO
    `include "timer_adc_coverage.sv"   // 5. Counts what was tested (5 covergroups)
    `include "timer_adc_env.sv"        // 6. Builds and connects all components above
    `include "timer_adc_seq_lib.sv"    // 7. Test scenarios (stimulus sequences)
    `include "timer_adc_tests.sv"      // 8. 10 runnable UVM tests

    `undef INSIDE_TIMER_ADC_PKG // Clear guard macro after package inclusion finishes

endpackage // End of timer_adc_pkg package
