`ifdef INSIDE_TIMER_ADC_PKG // Compile inside timer_adc_pkg package scope (safe when added to Vivado GUI)
`ifndef TIMER_ADC_SCOREBOARD_SV // Prevent duplicate inclusion of timer_adc_scoreboard.sv
`define TIMER_ADC_SCOREBOARD_SV // Mark timer_adc_scoreboard.sv as included

// =============================================================================
// File        : timer_adc_scoreboard.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : UVM Reference Model and Scoreboard predicting SAR ADC codes,
//               8-deep FIFO queue contents, window comparator flags, register
//               readbacks, and timer events (Chapter 13, 14, 15).
// =============================================================================

`uvm_analysis_imp_decl(_apb) // Declare dedicated analysis port suffix for APB bus transactions
`uvm_analysis_imp_decl(_adc) // Declare dedicated analysis port suffix for Analog/Timer events

class timer_adc_scoreboard extends uvm_scoreboard; // Reference model and self-checking scoreboard

    `uvm_component_utils(timer_adc_scoreboard)     // Register scoreboard with UVM factory

    // -------------------------------------------------------------------------
    // Analysis Implementation Ports Receiving Transactions from Both Monitors
    // -------------------------------------------------------------------------
    uvm_analysis_imp_apb #(apb_seq_item, timer_adc_scoreboard) apb_imp; // Port from apb_monitor
    uvm_analysis_imp_adc #(adc_seq_item, timer_adc_scoreboard) adc_imp; // Port from adc_monitor

    // -------------------------------------------------------------------------
    // Reference Model State (Shadow Registers & Golden 8-Slot FIFO Queue)
    // -------------------------------------------------------------------------
    bit [7:0] ref_regs [0:15];    // Shadow array mirroring configuration registers
    bit [9:0] ref_fifo [$];       // Golden queue holding up to 8 {ch[1:0], data[7:0]} items
    bit       ref_fifo_ovr;       // Shadow sticky FIFO_OVR flag
    bit       ref_adc_wd;         // Shadow sticky ADC_WD window violation flag
    int       tolerance_lsb;      // Allowed LSB tolerance (0 for ideal, >=1 during noise tests)

    // -------------------------------------------------------------------------
    // Verification Statistics Counters (Matching Chapter 15 Summary Metrics)
    // -------------------------------------------------------------------------
    int unsigned conv_checked_cnt;   // Total SAR ADC conversions verified
    int unsigned reg_read_cnt;       // Total FIFO/status/register reads verified
    int unsigned timer_ev_cnt;       // Total timer overflow/compare events verified
    int unsigned error_cnt;          // Total mismatch errors detected (must stay 0)

    function new(string name, uvm_component parent); // Scoreboard constructor
        super.new(name, parent);     // Call base constructor
        apb_imp = new("apb_imp", this); // Instantiate APB analysis imp
        adc_imp = new("adc_imp", this); // Instantiate ADC analysis imp
    endfunction                      // End of constructor

    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);    // Call base build_phase
        reset_model();               // Initialize reference model to power-on reset values
    endfunction                      // End of build_phase

    // -------------------------------------------------------------------------
    // Reset Reference Model State to Match Hardware Reset Table (Chapter 8)
    // -------------------------------------------------------------------------
    virtual function void reset_model(); // Reset shadow registers and FIFO queue
        foreach (ref_regs[i]) ref_regs[i] = 8'h00; // Default all shadow registers to 0x00
        ref_regs[4'h2] = 8'hFF;      // TMR_LOAD   reset value = 0xFF
        ref_regs[4'h3] = 8'h80;      // TMR_CMP    reset value = 0x80
        ref_regs[4'h6] = 8'h04;      // ADC_SMP    reset value = 0x04
        ref_regs[4'h9] = 8'hFF;      // ADC_THR_HI reset value = 0xFF
        ref_regs[4'hC] = 8'h10;      // ADC_STAT   reset value = 0x10 (EMPTY = 1)
        ref_regs[4'hF] = 8'hA8;      // ID         reset value = 0xA8
        ref_fifo.delete();           // Clear golden FIFO queue
        ref_fifo_ovr  = 1'b0;        // Clear shadow FIFO overflow flag
        ref_adc_wd    = 1'b0;        // Clear shadow window watchdog flag
        tolerance_lsb = 0;           // Exact 0-LSB tolerance unless noise/offset is active
    endfunction                      // End of reset_model

    // -------------------------------------------------------------------------
    // Handle Analog & Timer Events from adc_monitor
    // -------------------------------------------------------------------------
    virtual function void write_adc(adc_seq_item ev); // Callback when adc_monitor emits event
        case (ev.kind)               // Branch on event kind
            adc_seq_item::ADC_EOC_EVENT: begin // SAR ADC finished a conversion
                int diff;            // Absolute code difference between DUT and ideal model
                int max_tol;         // Maximum allowed LSB difference for this conversion
                conv_checked_cnt++;  // Increment verified conversion count

                // Compute allowed tolerance based on active analog offset/noise
                if ((ev.offset_v != 0.0) || (ev.noise_amp_v > 0.0)) begin // Noise test active
                    max_tol = (tolerance_lsb > 0) ? tolerance_lsb : 6;    // Allow configured tolerance
                end else begin       // Ideal noise-free conversion
                    max_tol = 1;     // Allow at most 1 LSB boundary rounding difference
                end                  // End of tolerance calculation

                diff = (int'(ev.conv_result) > int'(ev.exp_ideal_code)) ?   // Execute statement per peripheral specification
                       (int'(ev.conv_result) - int'(ev.exp_ideal_code)) :   // Execute statement per peripheral specification
                       (int'(ev.exp_ideal_code) - int'(ev.conv_result)); // Compute |got - exp|

                if (diff > max_tol) begin // Check if conversion code is outside tolerance
                    error_cnt++;     // Increment scoreboard error counter
                    `uvm_error("SB_ADC_CODE", $sformatf(                    // Format and print simulation status message
                        "ADC result mismatch on CH%0d: got=0x%02h (%0d), exp=0x%02h (%0d), vhold=%0.4fV", // Execute statement per peripheral specification
                        ev.conv_ch, ev.conv_result, ev.conv_result,         // Execute statement per peripheral specification
                        ev.exp_ideal_code, ev.exp_ideal_code, ev.vhold_at_eoc)) // Execute statement per peripheral specification
                end                  // End of code accuracy check

                // Update Golden Window Watchdog Prediction (result < THR_LO or result > THR_HI)
                if ((ev.conv_result < ref_regs[4'h8]) || (ev.conv_result > ref_regs[4'h9])) begin // Execute statement per peripheral specification
                    ref_adc_wd       = 1'b1; // Set expected window watchdog flag
                    ref_regs[4'hE][3] = 1'b1;// Mirror bit 3 (ADC_WD) in shadow IRQ_STAT
                end                  // End of window check

                // Mirror bit 2 (ADC_EOC) in shadow IRQ_STAT
                ref_regs[4'hE][2] = 1'b1; // Every conversion sets ADC_EOC sticky flag

                // Update Golden 8-Deep FIFO Queue
                if (ref_fifo.size() < 8) begin // Space available in 8-entry FIFO
                    ref_fifo.push_back({ev.conv_ch, ev.conv_result}); // Push {ch, data} to tail
                end else begin       // FIFO already holds 8 entries -> new result is dropped!
                    ref_fifo_ovr      = 1'b1; // Set expected FIFO overflow flag
                    ref_regs[4'hE][4] = 1'b1; // Mirror bit 4 (FIFO_OVR) in shadow IRQ_STAT
                end                  // End of golden FIFO push
            end                      // End of ADC_EOC_EVENT branch

            adc_seq_item::TMR_OVF_EVENT: begin // Timer overflow pulse observed
                timer_ev_cnt++;      // Increment verified timer event counter
                ref_regs[4'hE][0] = 1'b1; // Set TMR_OVF sticky flag in shadow IRQ_STAT
                if (ref_regs[4'h0][1]) begin // If one-shot mode (ONESHOT == 1)
                    ref_regs[4'h0][0] = 1'b0; // Hardware auto-clears TMR_CTRL.EN
                end                  // End of one-shot check
            end                      // End of TMR_OVF_EVENT branch

            adc_seq_item::TMR_CMP_EVENT: begin // Timer compare pulse observed
                timer_ev_cnt++;      // Increment verified timer event counter
                ref_regs[4'hE][1] = 1'b1; // Set TMR_CMP sticky flag in shadow IRQ_STAT
            end                      // End of TMR_CMP_EVENT branch

            default: begin           // Ignore voltage-set command items
            end                      // End of default branch
        endcase                      // End of case statement
    endfunction                      // End of write_adc

    // -------------------------------------------------------------------------
    // Handle APB Bus Reads and Writes from apb_monitor
    // -------------------------------------------------------------------------
    virtual function void write_apb(apb_seq_item tr); // Callback on every APB transfer
        if (tr.pwrite) begin         // Process CPU/APB Register Write
            case (tr.paddr)          // Decode written register address
                4'h0: ref_regs[4'h0] = tr.pwdata & 8'h03; // TMR_CTRL: bits [1:0]
                4'h1: ref_regs[4'h1] = tr.pwdata;         // TMR_PRESC
                4'h2: ref_regs[4'h2] = tr.pwdata;         // TMR_LOAD
                4'h3: ref_regs[4'h3] = tr.pwdata;         // TMR_CMP
                4'h5: ref_regs[4'h5] = tr.pwdata & 8'h3D; // ADC_CTRL (START bit 1 always reads 0)
                4'h6: ref_regs[4'h6] = tr.pwdata;         // ADC_SMP
                4'h7: ref_regs[4'h7] = tr.pwdata;         // ADC_DIV
                4'h8: ref_regs[4'h8] = tr.pwdata;         // ADC_THR_LO
                4'h9: ref_regs[4'h9] = tr.pwdata;         // ADC_THR_HI
                4'hD: ref_regs[4'hD] = tr.pwdata & 8'h3F; // IRQ_EN: bits [5:0]
                4'hE: begin          // IRQ_STAT Write-1-to-Clear (W1C)
                    ref_regs[4'hE] = ref_regs[4'hE] & ~(tr.pwdata & 8'h3F); // Clear written 1s
                    if (tr.pwdata[3]) ref_adc_wd   = 1'b0;// Clear shadow WD flag
                    if (tr.pwdata[4]) ref_fifo_ovr = 1'b0;// Clear shadow OVR flag
                end                  // End of IRQ_STAT W1C branch
                default: begin       // Writes to Read-Only registers (0x4, 0xA, 0xB, 0xC, 0xF)
                    if (!tr.pslverr) begin // Verify DUT raised pslverr on RO write
                        error_cnt++; // Flag missing slave error
                        `uvm_error("SB_RO_ERR", $sformatf("Write to RO reg 0x%01h did not set pslverr!", tr.paddr)) // Format and print simulation status message
                    end              // End of pslverr check
                end                  // End of RO write branch
            endcase                  // End of write address decode
        end else begin               // Process CPU/APB Register Read
            reg_read_cnt++;          // Increment verified register read counter
            case (tr.paddr)          // Verify read data against golden reference model
                4'h1, 4'h2, 4'h3, 4'h5, 4'h6, 4'h7, 4'h8, 4'h9, 4'hD, 4'hF: begin // Static/Config regs
                    if (tr.prdata !== ref_regs[tr.paddr]) begin // Compare readback with shadow
                        error_cnt++; // Increment error counter
                        `uvm_error("SB_REG_RD", $sformatf(                  // Format and print simulation status message
                            "Register 0x%01h read mismatch: got=0x%02h, exp=0x%02h", // Execute statement per peripheral specification
                            tr.paddr, tr.prdata, ref_regs[tr.paddr]))       // Execute statement per peripheral specification
                    end              // End of config register comparison
                end                  // End of static register branch

                4'hA: begin          // ADC_DATA read: returns oldest result and pops FIFO!
                    if (ref_fifo.size() == 0) begin // Golden FIFO is empty
                        if (tr.prdata !== 8'h00) begin // Empty FIFO must return 0x00
                            error_cnt++;                                    // Execute statement per peripheral specification
                            `uvm_error("SB_FIFO_EMPTY_RD", $sformatf(       // Format and print simulation status message
                                "Reading empty ADC_DATA returned 0x%02h instead of 0x00!", tr.prdata)) // Execute statement per peripheral specification
                        end          // End of empty read check
                    end else begin   // Golden FIFO has at least 1 entry
                        bit [9:0] oldest = ref_fifo.pop_front(); // Pop oldest {ch, data}
                        if (tr.prdata !== oldest[7:0]) begin     // Check 8-bit conversion data
                            error_cnt++;                                    // Execute statement per peripheral specification
                            `uvm_error("SB_FIFO_DATA", $sformatf(           // Format and print simulation status message
                                "ADC_DATA FIFO pop mismatch: got=0x%02h, exp=0x%02h (ch=%0d)", // Execute statement per peripheral specification
                                tr.prdata, oldest[7:0], oldest[9:8]))       // Execute statement per peripheral specification
                        end          // End of data match check
                    end              // End of non-empty FIFO pop
                end                  // End of ADC_DATA branch

                4'hB: begin          // ADC_RCH read: {VALID, 5'b0, CH[1:0]} without popping
                    bit [7:0] exp_rch = (ref_fifo.size() == 0) ? 8'h00 : {1'b1, 5'b00000, ref_fifo[0][9:8]}; // Execute statement per peripheral specification
                    if (tr.prdata !== exp_rch) begin // Compare against golden head channel
                        error_cnt++;                                        // Execute statement per peripheral specification
                        `uvm_error("SB_ADC_RCH", $sformatf(                 // Format and print simulation status message
                            "ADC_RCH mismatch: got=0x%02h, exp=0x%02h", tr.prdata, exp_rch)) // Execute statement per peripheral specification
                    end              // End of ADC_RCH comparison
                end                  // End of ADC_RCH branch

                4'hC: begin          // ADC_STAT read: {1'b0, BUSY, FULL, EMPTY, LEVEL[3:0]}
    int       fifo_sz   = ref_fifo.size();   // Lưu kích thước hàng đợi vào biến int 32-bit trước
    bit [3:0] exp_lvl   = fifo_sz[3:0];      // Lấy 4 bit thấp (0..8) chuẩn xác trên Vivado xsim
    bit       exp_empty = (exp_lvl == 4'd0); // Expected EMPTY flag
    bit       exp_full  = (exp_lvl == 4'd8); // Expected FULL flag
                    if ((tr.prdata[5:0] !== {exp_full, exp_empty, exp_lvl}) || (tr.prdata[7] !== 1'b0)) begin // Execute statement per peripheral specification
                        error_cnt++;                                        // Execute statement per peripheral specification
                        `uvm_error("SB_ADC_STAT", $sformatf(                // Format and print simulation status message
                            "ADC_STAT mismatch: got=0x%02h, exp_lvl=%0d", tr.prdata, exp_lvl)) // Execute statement per peripheral specification
                    end              // End of ADC_STAT check
                end                  // End of ADC_STAT branch

                default: begin       // TMR_CTRL (0x0), TMR_CNT (0x4), IRQ_STAT (0xE) checked by SVA & tests
                end                  // End of default read branch
            endcase                  // End of read address decode
        end                          // End of read/write check
    endfunction                      // End of write_apb

    // -------------------------------------------------------------------------
    // UVM Report Phase: Print Verification Summary (Chapter 14 & 15)
    // -------------------------------------------------------------------------
    virtual function void report_phase(uvm_phase phase); // UVM report phase
        super.report_phase(phase);   // Call base report_phase
        `uvm_info("SCOREBOARD", $sformatf(                                  // Format and print simulation status message
            "Summary: %0d conversions, %0d FIFO/status reads, %0d timer events checked, %0d errors", // Execute statement per peripheral specification
            conv_checked_cnt, reg_read_cnt, timer_ev_cnt, error_cnt), UVM_LOW) // Execute statement per peripheral specification
    endfunction                      // End of report_phase

endclass // End of timer_adc_scoreboard class

`endif // End of TIMER_ADC_SCOREBOARD_SV include guard
`endif // End of INSIDE_TIMER_ADC_PKG package scope guard
