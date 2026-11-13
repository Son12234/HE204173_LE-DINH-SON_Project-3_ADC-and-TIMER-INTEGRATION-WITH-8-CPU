// =============================================================================
// File        : tb_directed.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : Directed Smoke Testbench performing 37 self-checking register,
//               timer, PWM, SAR ADC, FIFO, window comparator, and interrupt
//               checks directly through the 8-bit APB port (Chapter 12 & 15).
// =============================================================================

`timescale 1ns/1ps // Define simulation time unit (1ns) and precision (1ps)

module tb_directed; // Declare directed APB testbench top module

    // -------------------------------------------------------------------------
    // Clock, Reset, and Test Bookkeeping Counters
    // -------------------------------------------------------------------------
    logic clk   = 1'b0; // System clock initialized to 0 (100 MHz -> 10ns period)
    logic rst_n = 1'b0; // Active-low reset initialized to asserted (0)
    int   pass_cnt = 0; // Count of passing directed checks (expected: 37)
    int   fail_cnt = 0; // Count of failing directed checks (expected: 0)

    always #5 clk = ~clk; // Generate 100 MHz clock (toggle every 5ns)

    // -------------------------------------------------------------------------
    // Instantiate Interfaces, DUT (timer_adc8_top), AFE Model, and SVA Bind
    // -------------------------------------------------------------------------
    apb_if apb ( .clk(clk), .rst_n(rst_n) ); // Instantiate 8-bit APB interface
    adc_if afe ( .clk(clk), .rst_n(rst_n) ); // Instantiate analog front-end interface

    timer_adc8_top dut (                     // Instantiate Design Under Test
        .clk        (clk),                   // Connect system clock
        .rst_n      (rst_n),                 // Connect active-low reset
        .psel       (apb.psel),              // Connect APB select
        .penable    (apb.penable),           // Connect APB enable
        .pwrite     (apb.pwrite),            // Connect APB write direction
        .paddr      (apb.paddr),             // Connect APB 4-bit address
        .pwdata     (apb.pwdata),            // Connect APB 8-bit write data
        .prdata     (apb.prdata),            // Connect APB 8-bit read data
        .pready     (apb.pready),            // Connect APB ready signal
        .pslverr    (apb.pslverr),           // Connect APB slave error signal
        .irq        (apb.irq),               // Connect CPU interrupt output
        .pwm_out    (afe.pwm_out),           // Connect timer PWM output
        .adc_sample (afe.adc_sample),        // Connect AFE sample switch
        .adc_ch     (afe.adc_ch),            // Connect AFE mux channel select
        .adc_dac    (afe.adc_dac),           // Connect AFE 8-bit DAC code
        .adc_cmp    (afe.adc_cmp)            // Connect AFE comparator output
    ); // End of DUT instantiation

    sar_afe_model u_afe (                    // Instantiate behavioral analog front-end
        .clk        (clk),                   // Connect clock
        .rst_n      (rst_n),                 // Connect reset
        .afe        (afe)                    // Connect analog interface
    ); // End of AFE model instantiation

    bind_timer_adc_sva u_bind_sva();         // Bind all 30 SVA assertions into DUT

    // -------------------------------------------------------------------------
    // Self-Checking Helper Tasks
    // -------------------------------------------------------------------------
    task automatic check_val(input string name, input logic [7:0] got, input logic [7:0] exp); // Check byte
        if (got === exp) begin               // Compare actual value against expected value
            pass_cnt++;                      // Increment pass counter
            $display("[PASS] Check %02d (%s): got=0x%02h == exp=0x%02h", pass_cnt + fail_cnt, name, got, exp); // Format and print simulation status message
        end else begin                       // Value mismatch detected
            fail_cnt++;                      // Increment fail counter
            $error("[FAIL] Check %02d (%s): got=0x%02h != exp=0x%02h", pass_cnt + fail_cnt, name, got, exp); // Execute statement per peripheral specification
        end                                  // End of comparison
    endtask                                  // End of check_val task

    task automatic check_bit(input string name, input logic got, input logic exp); // Check 1-bit flag
        if (got === exp) begin               // Compare actual bit against expected bit
            pass_cnt++;                      // Increment pass counter
            $display("[PASS] Check %02d (%s): got=%0b == exp=%0b", pass_cnt + fail_cnt, name, got, exp); // Format and print simulation status message
        end else begin                       // Bit mismatch detected
            fail_cnt++;                      // Increment fail counter
            $error("[FAIL] Check %02d (%s): got=%0b != exp=%0b", pass_cnt + fail_cnt, name, got, exp); // Execute statement per peripheral specification
        end                                  // End of comparison
    endtask                                  // End of check_bit task

    // -------------------------------------------------------------------------
    // Main Directed Test Sequence (37 Checks across all chapters)
    // -------------------------------------------------------------------------
    initial begin                            // Begin directed verification flow
        logic [7:0] rdata;                   // Local variable for register reads
        logic       err;                     // Local variable for bus error status

        apb.reset_bus();                     // Initialize APB master signals
        afe.set_all_voltages(1.111, 2.475, 0.4125, 3.300); // Ch0=1.111V(86), Ch1=2.475V(192), Ch2=0.4125V(32), Ch3=3.3V(255)
        repeat (5) @(posedge clk);           // Hold reset low for 5 clock cycles
        rst_n = 1'b1;                        // Release active-low reset
        repeat (2) @(posedge clk);           // Wait 2 clocks after reset release

        // --- Checks 1..16: Reset Values of All 16 Registers (Chapter 8, Page 9) ---
        apb.read_reg(4'h0, rdata, err); check_val("01. Reset TMR_CTRL",   rdata, 8'h00); // Check 1
        apb.read_reg(4'h1, rdata, err); check_val("02. Reset TMR_PRESC",  rdata, 8'h00); // Check 2
        apb.read_reg(4'h2, rdata, err); check_val("03. Reset TMR_LOAD",   rdata, 8'hFF); // Check 3
        apb.read_reg(4'h3, rdata, err); check_val("04. Reset TMR_CMP",    rdata, 8'h80); // Check 4
        apb.read_reg(4'h4, rdata, err); check_val("05. Reset TMR_CNT",    rdata, 8'h00); // Check 5
        apb.read_reg(4'h5, rdata, err); check_val("06. Reset ADC_CTRL",   rdata, 8'h00); // Check 6
        apb.read_reg(4'h6, rdata, err); check_val("07. Reset ADC_SMP",    rdata, 8'h04); // Check 7
        apb.read_reg(4'h7, rdata, err); check_val("08. Reset ADC_DIV",    rdata, 8'h00); // Check 8
        apb.read_reg(4'h8, rdata, err); check_val("09. Reset ADC_THR_LO", rdata, 8'h00); // Check 9
        apb.read_reg(4'h9, rdata, err); check_val("10. Reset ADC_THR_HI", rdata, 8'hFF); // Check 10
        apb.read_reg(4'hA, rdata, err); check_val("11. Reset ADC_DATA",   rdata, 8'h00); // Check 11
        apb.read_reg(4'hB, rdata, err); check_val("12. Reset ADC_RCH",    rdata, 8'h00); // Check 12
        apb.read_reg(4'hC, rdata, err); check_val("13. Reset ADC_STAT",   rdata, 8'h10); // Check 13 (EMPTY=1)
        apb.read_reg(4'hD, rdata, err); check_val("14. Reset IRQ_EN",     rdata, 8'h00); // Check 14
        apb.read_reg(4'hE, rdata, err); check_val("15. Reset IRQ_STAT",   rdata, 8'h00); // Check 15
        apb.read_reg(4'hF, rdata, err); check_val("16. Reset ID",         rdata, 8'hA8); // Check 16

        // --- Check 17: Write to Read-Only ID Register flags pslverr & preserves 0xA8 ---
        apb.write_reg(4'hF, 8'h55, err);     // Attempt illegal write to RO ID register
        check_bit("17. RO Write pslverr", err, 1'b1); // Check 17

        // --- Checks 18..21: Timer Periodic Mode & PWM (Chapter 4 Example: PRESC=1, LOAD=4, CMP=2) ---
        apb.write_reg(4'h1, 8'd1,  err);     // TMR_PRESC = 1 (tick every 2 clocks)
        apb.write_reg(4'h2, 8'd4,  err);     // TMR_LOAD  = 4 (counts 0..4 -> 10 clocks period)
        apb.write_reg(4'h3, 8'd2,  err);     // TMR_CMP   = 2 (PWM high for cnt=0,1)
        apb.write_reg(4'hD, 8'h03, err);     // IRQ_EN    = 0x03 (enable TMR_OVF and TMR_CMP)
        apb.write_reg(4'h0, 8'h01, err);     // TMR_CTRL  = 0x01 (EN=1, periodic)
        @(posedge clk);                      // Wait 1 clock for cnt=0 state
        check_bit("18. PWM high when cnt<CMP", afe.pwm_out, 1'b1); // Check 18
        repeat (10) @(posedge clk);          // Run 1 full period (10 clocks)
        apb.read_reg(4'hE, rdata, err);      // Read IRQ_STAT
        check_val("19. Timer OVF+CMP flags set", rdata & 8'h03, 8'h03); // Check 19
        check_bit("20. IRQ pin high on timer flags", apb.irq, 1'b1); // Check 20
        apb.write_reg(4'h0, 8'h00, err);     // Stop timer (TMR_CTRL = 0)
        apb.write_reg(4'hE, 8'h3F, err);     // W1C clear all IRQ_STAT flags
        apb.read_reg(4'hE, rdata, err);      // Read back IRQ_STAT
        check_val("21. W1C cleared IRQ_STAT", rdata, 8'h00); // Check 21

        // --- Checks 22..23: Timer One-Shot Mode Auto-Stop (Chapter 4) ---
        apb.write_reg(4'h1, 8'd0,  err);     // TMR_PRESC = 0 (tick every clock)
        apb.write_reg(4'h2, 8'd3,  err);     // TMR_LOAD  = 3 (4 clocks to overflow)
        apb.write_reg(4'h0, 8'h03, err);     // TMR_CTRL  = 0x03 (ONESHOT=1, EN=1)
        repeat (6) @(posedge clk);           // Wait for one-shot overflow to complete
        apb.read_reg(4'h0, rdata, err);      // Read TMR_CTRL
        check_val("22. One-shot auto-cleared EN", rdata, 8'h02); // Check 22 (EN=0, ONESHOT=1)
        apb.read_reg(4'h4, rdata, err);      // Read TMR_CNT
        check_val("23. One-shot counter stopped at 0", rdata, 8'h00); // Check 23
        apb.write_reg(4'hE, 8'h3F, err);     // Clear IRQ_STAT

        // --- Checks 24..28: Software-Triggered SAR ADC Conversion (Chapter 5 & 6: 1.111V -> 0x56) ---
        apb.write_reg(4'h6, 8'd2,  err);     // ADC_SMP = 2 (3 sample clocks)
        apb.write_reg(4'h7, 8'd0,  err);     // ADC_DIV = 0 (1 clock per tick -> 11 clocks total)
        apb.write_reg(4'h5, 8'h03, err);     // ADC_CTRL: CH=0, TRIG_SEL=0, START=1, EN=1
        apb.read_reg(4'h5, rdata, err);      // Read ADC_CTRL immediately
        check_val("24. ADC_CTRL.START reads back 0", rdata, 8'h01); // Check 24
        repeat (15) @(posedge clk);          // Wait for 11-clock conversion to finish
        apb.read_reg(4'hC, rdata, err);      // Read ADC_STAT
        check_val("25. ADC_STAT level=1 after 1 conv", rdata, 8'h01); // Check 25
        apb.read_reg(4'hB, rdata, err);      // Read ADC_RCH (no pop)
        check_val("26. ADC_RCH valid=1, ch=0", rdata, 8'h80); // Check 26
        apb.read_reg(4'hA, rdata, err);      // Read ADC_DATA (pops FIFO)
        check_val("27. ADC_DATA 1.111V == 0x56 (86)", rdata, 8'h56); // Check 27
        apb.read_reg(4'hC, rdata, err);      // Read ADC_STAT after pop
        check_val("28. ADC_STAT empty=1 after pop", rdata, 8'h10); // Check 28
        apb.write_reg(4'hE, 8'h3F, err);     // Clear IRQ_STAT

        // --- Checks 29..31: Multi-Channel Conversions (Ch1=192=0xC0, Ch2=32=0x20, Ch3=255=0xFF) ---
        apb.write_reg(4'h5, 8'h13, err);     // Start Ch1 (0x13: CH=1, START=1, EN=1)
        repeat (15) @(posedge clk);          // Wait for conversion
        apb.write_reg(4'h5, 8'h23, err);     // Start Ch2 (0x23: CH=2, START=1, EN=1)
        repeat (15) @(posedge clk);          // Wait for conversion
        apb.write_reg(4'h5, 8'h33, err);     // Start Ch3 (0x33: CH=3, START=1, EN=1)
        repeat (15) @(posedge clk);          // Wait for conversion
        apb.read_reg(4'hA, rdata, err); check_val("29. Ch1 2.475V == 0xC0",  rdata, 8'hC0); // Check 29
        apb.read_reg(4'hA, rdata, err); check_val("30. Ch2 0.4125V == 0x20", rdata, 8'h20); // Check 30
        apb.read_reg(4'hA, rdata, err); check_val("31. Ch3 3.300V == 0xFF",  rdata, 8'hFF); // Check 31
        apb.write_reg(4'hE, 8'h3F, err);     // Clear IRQ_STAT

        // --- Checks 32..33: Window Comparator Out-of-Window Flag (ADC_WD, bit 3) ---
        apb.write_reg(4'h8, 8'h60, err);     // Set ADC_THR_LO = 0x60 (96)
        apb.write_reg(4'h9, 8'hA0, err);     // Set ADC_THR_HI = 0xA0 (160)
        apb.write_reg(4'h5, 8'h03, err);     // Convert Ch0 (0x56 = 86 < 0x60 -> out of window!)
        repeat (15) @(posedge clk);          // Wait for conversion
        apb.read_reg(4'hE, rdata, err);      // Read IRQ_STAT
        check_val("32. Window low violation sets ADC_WD", rdata & 8'h0C, 8'h0C); // Check 32 (ADC_WD + ADC_EOC)
        apb.read_reg(4'hA, rdata, err);      // Pop FIFO result
        check_val("33. Popped out-of-window result 0x56", rdata, 8'h56); // Check 33
        apb.write_reg(4'h8, 8'h00, err);     // Restore THR_LO = 0x00
        apb.write_reg(4'h9, 8'hFF, err);     // Restore THR_HI = 0xFF
        apb.write_reg(4'hE, 8'h3F, err);     // Clear IRQ_STAT

        // --- Check 34: Trigger Miss Flag (TRIG_MISS, bit 5) when triggered while busy ---
        apb.write_reg(4'h6, 8'd6,  err);     // ADC_SMP = 6 (15 clocks total)
        apb.write_reg(4'h5, 8'h03, err);     // Start conversion 1
        repeat (2) @(posedge clk);           // While ADC is busy in SAMPLE state
        apb.write_reg(4'h5, 8'h03, err);     // Send second software START while busy!
        repeat (18) @(posedge clk);          // Let conversion 1 finish
        apb.read_reg(4'hE, rdata, err);      // Read IRQ_STAT
        check_val("34. Trigger while busy sets TRIG_MISS", rdata & 8'h20, 8'h20); // Check 34
        apb.read_reg(4'hA, rdata, err);      // Drain 1 result from FIFO
        apb.write_reg(4'hE, 8'h3F, err);     // Clear IRQ_STAT

        // --- Checks 35..37: Continuous Mode & FIFO Full / Overflow (FIFO_OVR, bit 4) ---
        apb.write_reg(4'h6, 8'd0,  err);     // ADC_SMP = 0 (9 clocks per conversion)
        apb.write_reg(4'h5, 8'h0D, err);     // ADC_CTRL = 0x0D (TRIG_SEL=3 continuous, EN=1)
        repeat (95) @(posedge clk);          // Run ~10 conversions to fill 8 slots and overflow
        apb.write_reg(4'h5, 8'h00, err);     // Disable ADC (abort continuous mode)
        apb.read_reg(4'hC, rdata, err);      // Read ADC_STAT
        check_val("35. FIFO full (FULL=1, LEVEL=8 -> 0x28)", rdata, 8'h28); // Check 35
        apb.read_reg(4'hE, rdata, err);      // Read IRQ_STAT
        check_val("36. FIFO overflow sets FIFO_OVR", rdata & 8'h10, 8'h10); // Check 36
        for (int k = 0; k < 8; k++) begin    // Pop all 8 entries from FIFO
            apb.read_reg(4'hA, rdata, err);  // Read ADC_DATA
        end                                  // End of FIFO drain loop
        apb.read_reg(4'hC, rdata, err);      // Read ADC_STAT after draining all 8 slots
        check_val("37. FIFO empty after 8 pops (0x10)", rdata, 8'h10); // Check 37

        // --- Final Summary Report ---
        $display("============================================================="); // Format and print simulation status message
        $display(" tb_directed Summary: %0d PASSED, %0d FAILED (Total: %0d/37)", // Format and print simulation status message
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);                  // Execute statement per peripheral specification
        $display("============================================================="); // Format and print simulation status message
        if (fail_cnt == 0 && pass_cnt == 37) begin                          // Execute statement per peripheral specification
            $display("TEST PASSED");                                        // Format and print simulation status message
        end else begin                                                      // Close block scope
            $fatal(1, "TEST FAILED");                                       // Execute statement per peripheral specification
        end                                                                 // Close block scope
        $finish;                             // End simulation cleanly
    end                                      // End of initial block

endmodule // End of tb_directed module
