// =============================================================================
// File        : tb_cpu_if.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : Directed CPU Bus Wrapper Testbench performing 20 single-cycle
//               CPU LD/ST checks on timer_adc8_cpu_if.v (Chapter 2, 9, 12, 15).
// =============================================================================

`timescale 1ns/1ps // Define simulation time unit (1ns) and precision (1ps)

module tb_cpu_if; // Declare CPU bus wrapper testbench top module

    // -------------------------------------------------------------------------
    // Clock, Reset, CPU Bus Wires, and Test Counters
    // -------------------------------------------------------------------------
    logic       clk      = 1'b0; // System clock (10 MHz equivalent or 100 MHz sim clock)
    logic       rst_n    = 1'b0; // Asynchronous active-low reset
    logic       cs       = 1'b0; // CPU address decoder chip select
    logic       we       = 1'b0; // CPU write enable (1 = ST, 0 = LD)
    logic [3:0] addr     = 4'h0; // 4-bit register offset (0x0 to 0xF)
    logic [7:0] wdata    = 8'h00;// 8-bit write data from CPU
    logic [7:0] rdata;           // 8-bit read data to CPU (0 when cs == 0)
    logic       irq;             // Interrupt request wire to CPU
    int         pass_cnt = 0;    // Number of passing checks (expected: 20)
    int         fail_cnt = 0;    // Number of failing checks (expected: 0)

    always #5 clk = ~clk;        // Generate 100 MHz simulation clock (10ns period)

    // -------------------------------------------------------------------------
    // Instantiate Analog Interface, CPU Wrapper DUT, AFE Model, and SVA Bind
    // -------------------------------------------------------------------------
    adc_if afe ( .clk(clk), .rst_n(rst_n) ); // Instantiate analog front-end interface

    timer_adc8_cpu_if dut (                  // Instantiate CPU wrapper module
        .clk        (clk),                   // Connect system clock
        .rst_n      (rst_n),                 // Connect active-low reset
        .cs         (cs),                    // Connect CPU chip select
        .we         (we),                    // Connect CPU write enable
        .addr       (addr),                  // Connect CPU 4-bit register offset
        .wdata      (wdata),                 // Connect CPU 8-bit write data
        .rdata      (rdata),                 // Connect CPU 8-bit read data
        .irq        (irq),                   // Connect CPU interrupt wire
        .pwm_out    (afe.pwm_out),           // Connect timer PWM output pin
        .adc_sample (afe.adc_sample),        // Connect AFE sample switch
        .adc_ch     (afe.adc_ch),            // Connect AFE channel select
        .adc_dac    (afe.adc_dac),           // Connect AFE 8-bit DAC code
        .adc_cmp    (afe.adc_cmp)            // Connect AFE comparator output
    ); // End of CPU wrapper instantiation

    sar_afe_model u_afe (                    // Instantiate behavioral analog front-end
        .clk        (clk),                   // Connect clock
        .rst_n      (rst_n),                 // Connect reset
        .afe        (afe)                    // Connect analog interface
    ); // End of AFE instantiation

    bind_timer_adc_sva u_bind_sva();         // Attach 30 SVA rules inside u_periph

    // -------------------------------------------------------------------------
    // Single-Cycle CPU Instruction Tasks: ST (Store) and LD (Load)
    // -------------------------------------------------------------------------
    task automatic cpu_st(input logic [3:0] reg_addr, input logic [7:0] val); // 1-clock ST instruction
        @(posedge clk);                      // Align to instruction start clock edge
        cs    <= 1'b1;                       // Drive chip select high for 1 clock
        we    <= 1'b1;                       // Assert write enable for store
        addr  <= reg_addr;                   // Present 4-bit register address
        wdata <= val;                        // Present 8-bit byte to store
        @(posedge clk);                      // Register latches wdata on this rising edge
        cs    <= 1'b0;                       // Deassert chip select after 1 clock
        we    <= 1'b0;                       // Deassert write enable
    endtask                                  // End of cpu_st task

    task automatic cpu_ld(input logic [3:0] reg_addr, output logic [7:0] val); // 1-clock LD instruction
        @(posedge clk);                      // Align to instruction start clock edge
        cs    <= 1'b1;                       // Drive chip select high for 1 clock
        we    <= 1'b0;                       // Deassert write enable for load
        addr  <= reg_addr;                   // Present 4-bit register address
        wdata <= 8'h00;                      // Clear wdata bus
        @(posedge clk);                      // CPU latches rdata at the end of the cycle
        val    = rdata;                      // Capture combinational rdata before edge
        cs    <= 1'b0;                       // Deassert chip select so FIFO only pops once
    endtask                                  // End of cpu_ld task

    task automatic check_byte(input string label, input logic [7:0] got, input logic [7:0] exp); // Verify byte
        if (got === exp) begin               // Check if read value matches expected
            pass_cnt++;                      // Increment pass count
            $display("[PASS] CPU Check %02d (%s): got=0x%02h == exp=0x%02h", pass_cnt + fail_cnt, label, got, exp); // Format and print simulation status message
        end else begin                       // Report mismatch
            fail_cnt++;                      // Increment fail count
            $error("[FAIL] CPU Check %02d (%s): got=0x%02h != exp=0x%02h", pass_cnt + fail_cnt, label, got, exp); // Execute statement per peripheral specification
        end                                  // End of check
    endtask                                  // End of check_byte task

    // -------------------------------------------------------------------------
    // Main CPU Wrapper Verification Sequence (20 Checks)
    // -------------------------------------------------------------------------
    initial begin                            // Start CPU bus verification
        logic [7:0] val;                     // Temporary variable for CPU LD results

        // Set sensor voltages: ch0=1.111V(0x56), ch1=1.111V(0x56), ch2=2.0625V(0xA0), ch3=0.825V(0x40)
        afe.set_all_voltages(1.111, 1.111, 2.0625, 0.825);                  // Execute statement per peripheral specification
        repeat (5) @(posedge clk);           // Hold reset active for 5 cycles
        rst_n = 1'b1;                        // Release reset
        repeat (2) @(posedge clk);           // Wait 2 cycles

        // --- Check 01: When cs == 0, rdata must be 0x00 so CPU can OR-mux peripherals ---
        cs = 1'b0; addr = 4'hF; #1;          // Point to ID register (0xA8) but keep cs=0
        check_byte("01. rdata is 0x00 when cs=0", rdata, 8'h00); // Check 1

        // --- Checks 02..05: Back-to-back 4-instruction sequence from Chapter 9 (Page 10) ---
        // First, pre-populate 1 conversion on channel 1 (1.111V -> 0x56) so FIFO level = 1
        cpu_st(4'h6, 8'd2);                  // ST ADC_SMP, 2
        cpu_st(4'h5, 8'h13);                 // ST ADC_CTRL, 0x13 (CH=1, START=1, EN=1)
        repeat (15) @(posedge clk);          // Wait for conversion to finish (FIFO has {ch=1, 0x56})

        // Now execute the exact 4 instructions from Chapter 9 waveform (Page 10):
        // 1) ST TMR_LOAD, 0x31 -> 2) LD ID -> 3) LD ADC_RCH -> 4) LD ADC_DATA
        cpu_st(4'h2, 8'h31);                 // ST TMR_LOAD, 0x31
        cpu_ld(4'h2, val); check_byte("02. ST/LD TMR_LOAD == 0x31", val, 8'h31); // Check 2
        cpu_ld(4'hF, val); check_byte("03. LD ID == 0xA8",          val, 8'hA8); // Check 3
        cpu_ld(4'hB, val); check_byte("04. LD ADC_RCH == 0x81",     val, 8'h81); // Check 4 (VALID=1, CH=1)
        cpu_ld(4'hA, val); check_byte("05. LD ADC_DATA == 0x56",    val, 8'h56); // Check 5 (pops FIFO)

        // --- Checks 06..07: Verify FIFO is now empty after single-cycle LD ADC_DATA ---
        cpu_ld(4'hC, val); check_byte("06. LD ADC_STAT empty (0x10)", val, 8'h10); // Check 6
        cpu_ld(4'hB, val); check_byte("07. LD ADC_RCH empty (0x00)",  val, 8'h00); // Check 7
        cpu_st(4'hE, 8'h3F);                 // Clear IRQ_STAT

        // --- Checks 08..14: Chapter 9 Complete Example Program (Timer-Triggered Ch2 + ISR) ---
        cpu_st(4'h1, 8'd1);                  // ST TMR_PRESC, 1 (scaled for fast simulation)
        cpu_st(4'h2, 8'd9);                  // ST TMR_LOAD, 9 (period = 2 * 10 = 20 clocks)
        cpu_st(4'h6, 8'd2);                  // ST ADC_SMP, 2
        cpu_st(4'h7, 8'd0);                  // ST ADC_DIV, 0
        cpu_st(4'hD, 8'h04);                 // ST IRQ_EN, 0x04 (ring irq on ADC_EOC)
        cpu_st(4'h5, 8'h25);                 // ST ADC_CTRL, 0x25 (EN=1, TRIG_SEL=1 timer ovf, CH=2)
        cpu_st(4'h0, 8'h01);                 // ST TMR_CTRL, 0x01 (start the timer)

        // Wait for irq ("the doorbell") to go high after timer overflow triggers ADC
        begin : wait_for_irq                 // Bounded wait for interrupt assertion
            int timeout = 0;                 // Cycle counter
            while (!irq && timeout < 100) begin // Poll irq wire
                @(posedge clk);              // Advance 1 clock
                timeout++;                   // Increment timeout counter
            end                              // End of wait loop
        end                                  // End of wait_for_irq block

        check_byte("08. ISR doorbell irq asserted", {7'b0, irq}, 8'h01); // Check 8
        cpu_st(4'h0, 8'h00);                 // Stop timer during ISR check
        cpu_ld(4'hB, val); check_byte("09. ISR LD ADC_RCH == 0x82 (CH2)", val, 8'h82); // Check 9
        cpu_ld(4'hA, val); check_byte("10. ISR LD ADC_DATA == 0xA0",      val, 8'hA0); // Check 10
        cpu_st(4'hE, 8'h04);                 // ST IRQ_STAT, 0x04 (clear ADC_EOC flag)
        @(posedge clk);                      // Allow 1 cycle for W1C update
        check_byte("11. ISR irq deasserted after W1C", {7'b0, irq}, 8'h00); // Check 11
        cpu_ld(4'hE, val); check_byte("12. ADC_EOC bit cleared in IRQ_STAT", val & 8'h04, 8'h00); // Check 12
        cpu_st(4'hE, 8'h3F);                 // Clear remaining TMR_OVF/CMP flags
        cpu_ld(4'hE, val); check_byte("13. All IRQ_STAT flags cleared", val, 8'h00); // Check 13
        cpu_ld(4'hC, val); check_byte("14. FIFO empty after ISR read",  val, 8'h10); // Check 14

        // --- Checks 15..20: Timer Compare Trigger (TRIG_SEL=2) & Threshold Registers ---
        cpu_st(4'h8, 8'h20);                 // ST ADC_THR_LO, 0x20
        cpu_st(4'h9, 8'hE0);                 // ST ADC_THR_HI, 0xE0
        cpu_ld(4'h8, val); check_byte("15. LD ADC_THR_LO == 0x20", val, 8'h20); // Check 15
        cpu_ld(4'h9, val); check_byte("16. LD ADC_THR_HI == 0xE0", val, 8'hE0); // Check 16
        cpu_st(4'h3, 8'd4);                  // ST TMR_CMP, 4
        cpu_ld(4'h3, val); check_byte("17. LD TMR_CMP == 0x04",    val, 8'h04); // Check 17
        cpu_st(4'h5, 8'h39);                 // ST ADC_CTRL, 0x39 (CH=3, TRIG_SEL=2 cmp, EN=1)
        cpu_st(4'h0, 8'h03);                 // ST TMR_CTRL, 0x03 (ONESHOT=1, EN=1)
        repeat (30) @(posedge clk);          // Wait for compare trigger + ADC conversion
        cpu_ld(4'hB, val); check_byte("18. CMP-triggered ADC_RCH == 0x83", val, 8'h83); // Check 18
        cpu_ld(4'hA, val); check_byte("19. CMP-triggered Ch3 == 0x40",     val, 8'h40); // Check 19
        cpu_ld(4'h0, val); check_byte("20. One-shot TMR_CTRL auto-stopped", val, 8'h02); // Check 20

        // --- Final Summary Report ---
        $display("============================================================="); // Format and print simulation status message
        $display(" tb_cpu_if Summary: %0d PASSED, %0d FAILED (Total: %0d/20)", // Format and print simulation status message
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);                  // Execute statement per peripheral specification
        $display("============================================================="); // Format and print simulation status message
        if (fail_cnt == 0 && pass_cnt == 20) begin                          // Execute statement per peripheral specification
            $display("TEST PASSED");                                        // Format and print simulation status message
        end else begin                                                      // Close block scope
            $fatal(1, "TEST FAILED");                                       // Execute statement per peripheral specification
        end                                                                 // Close block scope
        $finish;                             // Finish simulation
    end                                      // End of initial block

endmodule // End of tb_cpu_if module
