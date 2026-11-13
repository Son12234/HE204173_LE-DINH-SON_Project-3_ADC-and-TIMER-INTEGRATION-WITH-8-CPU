// =============================================================================
// File        : adc_if.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : Analog Front-End (AFE) and Peripheral Event SystemVerilog
//               Interface carrying real-valued sensor voltages (ch0..ch3),
//               analog impairment parameters (offset/noise), and monitor hooks.
// =============================================================================

`timescale 1ns/1ps // Define simulation time unit (1ns) and precision (1ps)

interface adc_if ( // Declare analog front-end and peripheral event interface
    input logic clk,   // System clock input
    input logic rst_n  // Active-low asynchronous reset input
); // End of interface port list

    // -------------------------------------------------------------------------
    // Real-Valued Analog Signals (Simulated Sensor Inputs & Reference)
    // -------------------------------------------------------------------------
    real        vin [0:3];   // 4 analog sensor input voltages in Volts (0.0V to 3.3V)
    real        vref;        // Full-scale ADC reference voltage (default 3.3V)
    real        offset_v;    // Injected analog DC offset error in Volts (default 0.0V)
    real        noise_amp_v; // Injected peak analog noise amplitude in Volts (default 0.0V)
    real        vhold;       // Voltage currently held on the sample-and-hold capacitor

    // -------------------------------------------------------------------------
    // Digital Control Signals Between SAR Controller and Analog Front-End
    // -------------------------------------------------------------------------
    logic       adc_sample;  // Sample switch control (1 = track vin[adc_ch], 0 = hold)
    logic [1:0] adc_ch;      // 2-bit multiplexer channel select (0 to 3)
    logic [7:0] adc_dac;     // 8-bit trial DAC code from SAR digital controller
    logic       adc_cmp;     // Comparator output from AFE to SAR controller (vhold >= vdac)
    logic       pwm_out;     // Timer PWM output signal observed by monitor

    // -------------------------------------------------------------------------
    // Observation Signals Connected for Scoreboard & Coverage Verification
    // -------------------------------------------------------------------------
    logic       adc_eoc_mon;       // Observed 1-clock End-Of-Conversion pulse
    logic [7:0] adc_result_mon;    // Observed 8-bit digital result code at EOC
    logic [1:0] adc_result_ch_mon; // Observed 2-bit channel tag at EOC
    logic       tmr_ovf_mon;       // Observed 1-clock timer overflow pulse
    logic       tmr_cmp_mon;       // Observed 1-clock timer compare pulse

    // -------------------------------------------------------------------------
    // Default Analog Initialization Block (Single Driver for vin/vref/offset/noise)
    // -------------------------------------------------------------------------
    initial begin            // Initialize analog environment at time 0
        vin[0]      = 0.0;   // Default channel 0 voltage = 0.0V
        vin[1]      = 0.0;   // Default channel 1 voltage = 0.0V
        vin[2]      = 0.0;   // Default channel 2 voltage = 0.0V
        vin[3]      = 0.0;   // Default channel 3 voltage = 0.0V
        vref        = 3.3;   // Standard 3.3V full-scale reference (1 LSB = 12.89 mV)
        offset_v    = 0.0;   // Zero analog offset by default
        noise_amp_v = 0.0;   // Zero analog noise by default
    end                      // End of initial block

    // -------------------------------------------------------------------------
    // Helper Functions & Tasks for Driving Voltages and Computing Expected Codes
    // -------------------------------------------------------------------------
    task automatic set_channel_voltage(input logic [1:0] ch, input real volts); // Set 1 channel
        vin[ch] = volts;     // Update specified analog input channel voltage
    endtask                  // End of set_channel_voltage task

    task automatic set_all_voltages(input real v0, input real v1, input real v2, input real v3); // Set all 4
        vin[0] = v0;         // Set channel 0 voltage in Volts
        vin[1] = v1;         // Set channel 1 voltage in Volts
        vin[2] = v2;         // Set channel 2 voltage in Volts
        vin[3] = v3;         // Set channel 3 voltage in Volts
    endtask                  // End of set_all_voltages task

    function automatic logic [7:0] voltage_to_code(input real v_in); // Ideal 8-bit SAR transfer function
        real    scaled;      // Normalized voltage in LSB units (0.0 to 256.0)
        integer code_int;    // Integer floor of scaled voltage
        if (v_in <= 0.0) begin                  // Clamp negative or zero inputs to code 0
            return 8'h00;                       // Minimum 8-bit code is 0
        end else if (v_in >= vref) begin        // Clamp inputs at or above Vref to 255
            return 8'hFF;                       // Maximum 8-bit code is 255 (0xFF)
        end else begin                          // Linear quantization inside (0, Vref)
            scaled   = (v_in / vref) * 256.0;   // Compute (Vin / Vref) * 256
            code_int = $rtoi(scaled);           // Truncate (round down) to integer code
            if (code_int > 255) code_int = 255; // Guard upper bound
            if (code_int < 0)   code_int = 0;   // Guard lower bound
            return code_int[7:0];               // Return 8-bit expected SAR result
        end                                     // End of quantization calculation
    endfunction                                 // End of voltage_to_code function

endinterface // End of adc_if interface
