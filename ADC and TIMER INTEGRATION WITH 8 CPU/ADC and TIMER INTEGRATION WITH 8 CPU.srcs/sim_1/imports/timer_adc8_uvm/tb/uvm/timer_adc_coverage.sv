`ifdef INSIDE_TIMER_ADC_PKG // Compile inside timer_adc_pkg package scope (safe when added to Vivado GUI)
`ifndef TIMER_ADC_COVERAGE_SV // Prevent duplicate inclusion of timer_adc_coverage.sv
`define TIMER_ADC_COVERAGE_SV // Mark timer_adc_coverage.sv as included

// =============================================================================
// File        : timer_adc_coverage.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : UVM Functional Coverage Collector with 5 Covergroups:
//               1) ADC Settings, 2) ADC Results, 3) FIFO States, 4) Timer,
//               and 5) Interrupts (Chapter 13, 14, 15).
// Note        : Bin names must NOT be Verilog reserved words (small, medium,
//               large, high0, high1, ...). "medium" was renamed to "med".
// =============================================================================

class timer_adc_coverage extends uvm_component; // Collects functional coverage across 5 groups

    `uvm_component_utils(timer_adc_coverage)    // Register collector with UVM factory

    // Analysis Imp Ports to Receive APB and Analog/Timer Transactions
    uvm_analysis_imp_apb #(apb_seq_item, timer_adc_coverage) apb_imp; // APB transaction port
    uvm_analysis_imp_adc #(adc_seq_item, timer_adc_coverage) adc_imp; // Analog event port

    // Sampled State Variables for Covergroups
    bit [1:0] cov_adc_ch;       // Sampled ADC channel (0..3)
    bit [1:0] cov_trig_sel;     // Sampled ADC trigger mode (0..3)
    bit [7:0] cov_adc_smp;      // Sampled ADC sample time (ADC_SMP)
    bit [7:0] cov_adc_div;      // Sampled ADC clock divider (ADC_DIV)
    bit [7:0] cov_adc_code;     // Sampled 8-bit ADC conversion result (0..255)
    bit [3:0] cov_fifo_lvl;     // Sampled FIFO occupancy level (0..8)
    bit       cov_fifo_empty;   // Sampled FIFO empty flag
    bit       cov_fifo_full;    // Sampled FIFO full flag
    bit       cov_tmr_en;       // Sampled Timer enable bit
    bit       cov_tmr_oneshot;  // Sampled Timer one-shot mode bit
    bit [7:0] cov_tmr_presc;    // Sampled Timer prescaler value
    bit [7:0] cov_tmr_load;     // Sampled Timer reload value
    bit [7:0] cov_tmr_cmp;      // Sampled Timer compare threshold
    bit [5:0] cov_irq_en;       // Sampled 6-bit interrupt enable mask
    bit [5:0] cov_irq_stat;     // Sampled 6-bit interrupt status flags

    // -------------------------------------------------------------------------
    // Covergroup 1: ADC Settings (Channels x Trigger Modes x Sample/Div)
    // -------------------------------------------------------------------------
    covergroup cg_adc_settings; // Tracks ADC configuration combinations
        option.per_instance = 1;// Track per-instance coverage in UVM report
        cp_ch:       coverpoint cov_adc_ch   { bins ch[]   = {[0:3]}; } // All 4 analog channels
        cp_trig:     coverpoint cov_trig_sel { bins trig[] = {[0:3]}; } // All 4 trigger sources
        cp_smp:      coverpoint cov_adc_smp  {                              // Define functional coverpoint or cross coverage
            bins fast   = {[0:1]};   // Short sample window (1..2 ticks)
            bins med    = {[2:8]};   // Medium sample window (3..9 ticks) - renamed from reserved word "medium"
            bins slow   = {[9:255]}; // Long sample window (>=10 ticks)
        }                                                                   // Execute statement per peripheral specification
        cp_div:      coverpoint cov_adc_div  {                              // Define functional coverpoint or cross coverage
            bins div0   = {0};       // Full-speed ADC clock (DIV=0)
            bins div_lo = {[1:3]};   // Divided ADC clock (DIV=1..3)
            bins div_hi = {[4:255]}; // Slow divided ADC clock (DIV>=4)
        }                                                                   // Execute statement per peripheral specification
        cx_ch_trig:  cross cp_ch, cp_trig;   // Every channel x trigger source combination
    endgroup // End of cg_adc_settings

    // -------------------------------------------------------------------------
    // Covergroup 2: ADC Results (Zero, Low, Mid, High, Full-Scale Corners)
    // -------------------------------------------------------------------------
    covergroup cg_adc_results;  // Tracks 8-bit conversion result ranges across channels
        option.per_instance = 1;// Track per-instance coverage
        cp_code:     coverpoint cov_adc_code {                              // Define functional coverpoint or cross coverage
            bins zero    = {8'h00};         // Zero-scale corner (0.0V -> 0)
            bins low_q   = {[8'h01:8'h3F]}; // First quarter (1..63)
            bins mid_lo  = {[8'h40:8'h7F]}; // Second quarter (64..127)
            bins mid_hi  = {[8'h80:8'hBF]}; // Third quarter (128..191)
            bins high_q  = {[8'hC0:8'hFE]}; // Fourth quarter (192..254)
            bins full_sc = {8'hFF};         // Full-scale corner (3.3V -> 255)
        }                                                                   // Execute statement per peripheral specification
        cp_res_ch:   coverpoint cov_adc_ch { bins ch[] = {[0:3]}; } // Converted channel
        cx_ch_code:  cross cp_res_ch, cp_code; // Channel x voltage range cross
    endgroup // End of cg_adc_results

    // -------------------------------------------------------------------------
    // Covergroup 3: Result FIFO Occupancy Levels (0 to 8), Empty, and Full
    // -------------------------------------------------------------------------
    covergroup cg_fifo_states;  // Tracks FIFO queue depth and boundary conditions
        option.per_instance = 1;// Track per-instance coverage
        cp_level:    coverpoint cov_fifo_lvl   { bins lvl[] = {[0:8]}; } // Every FIFO depth 0..8
        cp_empty:    coverpoint cov_fifo_empty { bins val[] = {0, 1};  } // Both empty=0 and empty=1
        cp_full:     coverpoint cov_fifo_full  { bins val[] = {0, 1};  } // Both full=0 and full=1
    endgroup // End of cg_fifo_states

    // -------------------------------------------------------------------------
    // Covergroup 4: Timer Settings (Periodic, One-Shot, Prescaler, Load, Compare)
    // -------------------------------------------------------------------------
    covergroup cg_timer_cfg;    // Tracks 8-bit timer modes and counter configurations
        option.per_instance = 1;// Track per-instance coverage
        cp_en:       coverpoint cov_tmr_en      { bins val[] = {0, 1}; } // Disabled and enabled
        cp_oneshot:  coverpoint cov_tmr_oneshot { bins val[] = {0, 1}; } // Periodic and one-shot
        cp_presc:    coverpoint cov_tmr_presc   {                           // Define functional coverpoint or cross coverage
            bins zero = {0};         // No prescaling (divide by 1)
            bins low  = {[1:7]};     // Small prescaler (divide by 2..8)
            bins high = {[8:255]};   // Large prescaler (divide by >=9)
        }                                                                   // Execute statement per peripheral specification
        cp_load:     coverpoint cov_tmr_load    {                           // Define functional coverpoint or cross coverage
            bins zero = {0};         // Minimum period (LOAD=0)
            bins sml  = {[1:15]};    // Short period (LOAD=1..15)
            bins med  = {[16:254]};  // Medium period
            bins max  = {255};       // Maximum period (LOAD=255)
        }                                                                   // Execute statement per peripheral specification
        cp_cmp:      coverpoint cov_tmr_cmp     {                           // Define functional coverpoint or cross coverage
            bins zero = {0};         // 0% PWM duty cycle
            bins mid  = {[1:254]};   // Intermediate duty cycle
            bins max  = {255};       // High compare threshold
        }                                                                   // Execute statement per peripheral specification
    endgroup // End of cg_timer_cfg

    // -------------------------------------------------------------------------
    // Covergroup 5: Interrupt Enables and All 6 Sticky Event Flags
    // -------------------------------------------------------------------------
    covergroup cg_interrupts;   // Tracks assertion and clearing of all 6 interrupt sources
        option.per_instance = 1;// Track per-instance coverage
        cp_tmr_ovf:   coverpoint cov_irq_stat[0] { bins seen[] = {0, 1}; } // Bit 0: TMR_OVF
        cp_tmr_cmp:   coverpoint cov_irq_stat[1] { bins seen[] = {0, 1}; } // Bit 1: TMR_CMP
        cp_adc_eoc:   coverpoint cov_irq_stat[2] { bins seen[] = {0, 1}; } // Bit 2: ADC_EOC
        cp_adc_wd:    coverpoint cov_irq_stat[3] { bins seen[] = {0, 1}; } // Bit 3: ADC_WD
        cp_fifo_ovr:  coverpoint cov_irq_stat[4] { bins seen[] = {0, 1}; } // Bit 4: FIFO_OVR
        cp_trig_miss: coverpoint cov_irq_stat[5] { bins seen[] = {0, 1}; } // Bit 5: TRIG_MISS
        cp_irq_en:    coverpoint cov_irq_en      {                          // Define functional coverpoint or cross coverage
            bins none = {6'h00};        // All interrupts masked
            bins some = {[6'h01:6'h3E]};// Partial interrupt masks
            bins all  = {6'h3F};        // All 6 interrupts enabled
        }                                                                   // Execute statement per peripheral specification
    endgroup // End of cg_interrupts

    // -------------------------------------------------------------------------
    // Constructor: Instantiate All 5 Covergroups and Analysis Ports
    // -------------------------------------------------------------------------
    function new(string name, uvm_component parent); // Constructor
        super.new(name, parent);        // Call base constructor
        apb_imp         = new("apb_imp", this); // Create APB analysis imp
        adc_imp         = new("adc_imp", this); // Create ADC analysis imp
        cg_adc_settings = new();        // Instantiate Covergroup 1
        cg_adc_results  = new();        // Instantiate Covergroup 2
        cg_fifo_states  = new();        // Instantiate Covergroup 3
        cg_timer_cfg    = new();        // Instantiate Covergroup 4
        cg_interrupts   = new();        // Instantiate Covergroup 5
    endfunction                         // End of constructor

    // -------------------------------------------------------------------------
    // Sample APB Bus Transactions
    // -------------------------------------------------------------------------
    virtual function void write_apb(apb_seq_item tr); // Callback from apb_monitor
        if (tr.pwrite) begin            // Sample configuration writes
            case (tr.paddr)             // Decode register address
                4'h0: begin             // TMR_CTRL write
                    cov_tmr_en      = tr.pwdata[0]; // Capture EN
                    cov_tmr_oneshot = tr.pwdata[1]; // Capture ONESHOT
                    cg_timer_cfg.sample();          // Sample timer covergroup
                end                                                         // Close block scope
                4'h1: begin cov_tmr_presc = tr.pwdata; cg_timer_cfg.sample(); end // TMR_PRESC
                4'h2: begin cov_tmr_load  = tr.pwdata; cg_timer_cfg.sample(); end // TMR_LOAD
                4'h3: begin cov_tmr_cmp   = tr.pwdata; cg_timer_cfg.sample(); end // TMR_CMP
                4'h5: begin             // ADC_CTRL write
                    cov_adc_ch   = tr.pwdata[5:4];  // Capture channel
                    cov_trig_sel = tr.pwdata[3:2];  // Capture trigger mode
                    cg_adc_settings.sample();       // Sample ADC settings covergroup
                end                                                         // Close block scope
                4'h6: begin cov_adc_smp = tr.pwdata; cg_adc_settings.sample(); end // ADC_SMP
                4'h7: begin cov_adc_div = tr.pwdata; cg_adc_settings.sample(); end // ADC_DIV
                4'hD: begin cov_irq_en  = tr.pwdata[5:0]; cg_interrupts.sample(); end // IRQ_EN
                default: begin end      // Other writes
            endcase                     // End of write decode
        end else begin                  // Sample status and interrupt reads
            if (tr.paddr == 4'hC) begin // ADC_STAT read
                cov_fifo_lvl   = tr.prdata[3:0]; // Extract LEVEL[3:0]
                cov_fifo_empty = tr.prdata[4];   // Extract EMPTY bit
                cov_fifo_full  = tr.prdata[5];   // Extract FULL bit
                cg_fifo_states.sample();         // Sample FIFO covergroup
            end else if (tr.paddr == 4'hE) begin // IRQ_STAT read
                cov_irq_stat = tr.prdata[5:0];   // Extract 6 sticky flags
                cg_interrupts.sample();          // Sample interrupt covergroup
            end                         // End of status/interrupt read check
        end                             // End of read/write check
    endfunction                         // End of write_apb

    // -------------------------------------------------------------------------
    // Sample Analog Conversion Events
    // -------------------------------------------------------------------------
    virtual function void write_adc(adc_seq_item ev); // Callback from adc_monitor
        if (ev.kind == adc_seq_item::ADC_EOC_EVENT) begin // On every completed conversion
            cov_adc_ch   = ev.conv_ch;     // Record converted channel
            cov_adc_code = ev.conv_result; // Record 8-bit result code
            cg_adc_settings.sample();      // Sample ADC settings
            cg_adc_results.sample();       // Sample ADC result code bins
        end                                // End of EOC event check
    endfunction                            // End of write_adc

    // -------------------------------------------------------------------------
    // UVM Report Phase: Print Coverage Percentages for All 5 Covergroups
    // -------------------------------------------------------------------------
    virtual function void report_phase(uvm_phase phase); // UVM report phase
        super.report_phase(phase);         // Call base report_phase
        `uvm_info("COVERAGE", $sformatf(                                    // Format and print simulation status message
            "Coverage Summary: ADC_Settings=%0.1f%%, ADC_Results=%0.1f%%, FIFO=%0.1f%%, Timer=%0.1f%%, IRQ=%0.1f%%", // Execute statement per peripheral specification
            cg_adc_settings.get_inst_coverage(),                            // Execute statement per peripheral specification
            cg_adc_results.get_inst_coverage(),                             // Execute statement per peripheral specification
            cg_fifo_states.get_inst_coverage(),                             // Execute statement per peripheral specification
            cg_timer_cfg.get_inst_coverage(),                               // Execute statement per peripheral specification
            cg_interrupts.get_inst_coverage()), UVM_LOW)                    // Execute statement per peripheral specification
    endfunction                            // End of report_phase

endclass // End of timer_adc_coverage class

`endif // End of TIMER_ADC_COVERAGE_SV include guard
`endif // End of INSIDE_TIMER_ADC_PKG package scope guard