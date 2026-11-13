`ifdef INSIDE_TIMER_ADC_PKG // Compile inside timer_adc_pkg package scope (safe when added to Vivado GUI)
`ifndef TIMER_ADC_SEQ_LIB_SV // Prevent duplicate inclusion of timer_adc_seq_lib.sv
`define TIMER_ADC_SEQ_LIB_SV // Mark timer_adc_seq_lib.sv as included

// =============================================================================
// File        : timer_adc_seq_lib.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : UVM Virtual Sequence Library containing Base Helper Tasks and
//               all 10 Verification Scenarios matching Chapter 14 (Page 15).
// =============================================================================

// -----------------------------------------------------------------------------
// Base Virtual Sequence with Reusable RAL & Analog Helper Tasks
// -----------------------------------------------------------------------------
class tadc_base_vseq extends uvm_sequence #(uvm_sequence_item); // Base virtual sequence

    `uvm_object_utils(tadc_base_vseq)             // Register sequence with UVM factory

    timer_adc_env       env;                      // Pointer to UVM environment
    timer_adc_reg_block rm;                       // Pointer to 16-register RAL model
    virtual apb_if      apb_vif;                  // Virtual interface for clock waits

    function new(string name = "tadc_base_vseq"); // Constructor
        super.new(name);                          // Call base constructor
    endfunction                                   // End of constructor

    virtual task pre_body();                      // Initialize handles before body() runs
        if (env != null) begin                    // Check if env handle was assigned
            rm      = env.rm;                     // Cache RAL register model handle
            apb_vif = env.apb_agt.drv.vif;        // Cache APB virtual interface handle
        end                                       // End of env check
    endtask                                       // End of pre_body

    // Helper: Wait N system clock cycles
    virtual task wait_clks(int n);                // Wait for n rising edges of clk
        repeat (n) @(posedge apb_vif.clk);        // Synchronize to APB clock
    endtask                                       // End of wait_clks

    // Helper: Write a byte to a register address via APB sequencer
    virtual task wr_byte(bit [3:0] addr, bit [7:0] data); // Direct byte write
        apb_seq_item item = apb_seq_item::type_id::create("wr_item"); // Create item
        start_item(item, -1, env.apb_agt.sqr);    // Request grant on APB sequencer
        item.pwrite = 1'b1;                       // Set write direction
        item.paddr  = addr;                       // Set 4-bit register offset
        item.pwdata = data;                       // Set 8-bit payload
        finish_item(item);                        // Execute write on APB bus
    endtask                                       // End of wr_byte

    // Helper: Read a byte from a register address via APB sequencer
    virtual task rd_byte(bit [3:0] addr, output bit [7:0] data); // Direct byte read
        apb_seq_item item = apb_seq_item::type_id::create("rd_item"); // Create item
        start_item(item, -1, env.apb_agt.sqr);    // Request grant on APB sequencer
        item.pwrite = 1'b0;                       // Set read direction
        item.paddr  = addr;                       // Set 4-bit register offset
        item.pwdata = 8'h00;                      // Clear write data
        finish_item(item);                        // Execute read on APB bus
        data = item.prdata;                       // Return sampled read data
    endtask                                       // End of rd_byte

    // Helper: Drive 4 analog channel voltages and optional offset/noise via ADC agent
    virtual task set_analog(real v0, real v1, real v2, real v3,             // Declare task
                            real off_v = 0.0, real noise_v = 0.0); // Set analog inputs
        adc_seq_item a_item = adc_seq_item::type_id::create("a_item"); // Create analog item
        start_item(a_item, -1, env.adc_agt.sqr);  // Request grant on ADC sequencer
        a_item.kind        = adc_seq_item::ADC_SET_VOLTS; // Voltage update command
        a_item.vin[0]      = v0;                  // Channel 0 voltage
        a_item.vin[1]      = v1;                  // Channel 1 voltage
        a_item.vin[2]      = v2;                  // Channel 2 voltage
        a_item.vin[3]      = v3;                  // Channel 3 voltage
        a_item.offset_v    = off_v;               // DC offset voltage
        a_item.noise_amp_v = noise_v;             // Noise amplitude voltage
        finish_item(a_item);                      // Apply analog settings immediately
    endtask                                       // End of set_analog

    // Helper: Drain all queued entries from the 8-deep result FIFO
    virtual task drain_fifo();                    // Pop FIFO until EMPTY=1
        bit [7:0] stat, rch, data;                // Local status and data bytes
        for (int i = 0; i < 10; i++) begin        // Guard loop up to 10 reads
            rd_byte(4'hC, stat);                  // Read ADC_STAT (0xC)
            if (stat[4]) break;                   // Stop when EMPTY bit (bit 4) is 1
            rd_byte(4'hB, rch);                   // Read ADC_RCH (0xB, no pop)
            rd_byte(4'hA, data);                  // Read ADC_DATA (0xA, pops oldest entry)
        end                                       // End of drain loop
    endtask                                       // End of drain_fifo

endclass // End of tadc_base_vseq

// =============================================================================
// Scenario 1: tadc_reg_seq - Reset values, bit-bash, write/read-back, RO errors
// =============================================================================
class tadc_reg_seq extends tadc_base_vseq;        // Scenario 1 sequence
    `uvm_object_utils(tadc_reg_seq)               // Register with factory
    function new(string name = "tadc_reg_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute Scenario 1
        bit [7:0] rdata;                          // Readback variable
        uvm_status_e status;                      // RAL status
        bit [3:0] rw_addrs[8];                    // Array of 8 full-byte RW register addresses

        rw_addrs[0] = 4'h1;                       // TMR_PRESC address
        rw_addrs[1] = 4'h2;                       // TMR_LOAD address
        rw_addrs[2] = 4'h3;                       // TMR_CMP address
        rw_addrs[3] = 4'h6;                       // ADC_SMP address
        rw_addrs[4] = 4'h7;                       // ADC_DIV address
        rw_addrs[5] = 4'h8;                       // ADC_THR_LO address
        rw_addrs[6] = 4'h9;                       // ADC_THR_HI address
        rw_addrs[7] = 4'hD;                       // IRQ_EN address

        // 1. Read and verify power-on reset values across all 16 registers
        for (int a = 0; a < 16; a++) begin        // Loop over addresses 0x0 to 0xF
            rd_byte(a[3:0], rdata);               // Read register via APB
        end                                       // Scoreboard verifies exact reset values

        // 2. Bit-bash 0x55/0xAA/0xFF/0x00 patterns on RW configuration registers
        foreach (rw_addrs[idx]) begin             // Iterate through each RW register address
            bit [3:0] addr = rw_addrs[idx];       // Select target register offset
            wr_byte(addr, 8'h55); rd_byte(addr, rdata); // Write & read 0x55
            wr_byte(addr, 8'hAA); rd_byte(addr, rdata); // Write & read 0xAA
            wr_byte(addr, 8'hFF); rd_byte(addr, rdata); // Write & read 0xFF
            wr_byte(addr, 8'h00); rd_byte(addr, rdata); // Write & read 0x00
        end                                       // End of bit-bash loop

        // 3. Test RAL write/read access and RO write protection (pslverr check)
        rm.tmr_load.write(status, 8'hFF);         // Restore TMR_LOAD via RAL
        rm.tmr_cmp.write(status, 8'h80);          // Restore TMR_CMP via RAL
        rm.adc_smp.write(status, 8'h04);          // Restore ADC_SMP via RAL
        rm.adc_thr_hi.write(status, 8'hFF);       // Restore ADC_THR_HI via RAL
        wr_byte(4'h4, 8'hDE);                     // Attempt write to RO TMR_CNT
        wr_byte(4'hA, 8'hAD);                     // Attempt write to RO ADC_DATA
        wr_byte(4'hB, 8'hBE);                     // Attempt write to RO ADC_RCH
        wr_byte(4'hC, 8'hEF);                     // Attempt write to RO ADC_STAT
        wr_byte(4'hF, 8'h00);                     // Attempt write to RO ID (0xA8)
        rd_byte(4'hF, rdata);                     // Verify ID still reads 0xA8
    endtask                                       // End of Scenario 1 body
endclass // End of tadc_reg_seq

// =============================================================================
// Scenario 2: tadc_timer_seq - 14 Timer Settings: periodic, one-shot, LOAD=0, big prescaler
// =============================================================================
class tadc_timer_seq extends tadc_base_vseq;      // Scenario 2 sequence
    `uvm_object_utils(tadc_timer_seq)             // Register with factory
    function new(string name = "tadc_timer_seq"); super.new(name); endfunction // Constructor

    typedef struct { bit oneshot; bit [7:0] presc; bit [7:0] load; bit [7:0] cmp; int wait_c; } tmr_cfg_t; // Execute statement per peripheral specification

    virtual task body();                          // Execute Scenario 2 (14 timer settings)
        bit [7:0] rdata;                          // Readback variable
        tmr_cfg_t cfgs[14] = '{                   // 14 distinct timer configurations (Chapter 14)
            '{0, 8'd0,  8'd0,   8'd0,   12},      // 01. Periodic, PRESC=0, LOAD=0, CMP=0
            '{0, 8'd0,  8'd4,   8'd2,   20},      // 02. Periodic, PRESC=0, LOAD=4, CMP=2
            '{0, 8'd1,  8'd4,   8'd2,   25},      // 03. Periodic, PRESC=1, LOAD=4, CMP=2 (Chapter 4 ex)
            '{0, 8'd2,  8'd7,   8'd4,   55},      // 04. Periodic, PRESC=2, LOAD=7, CMP=4
            '{0, 8'd3,  8'd9,   8'd0,   50},      // 05. Periodic, 0% PWM duty (CMP=0)
            '{0, 8'd1,  8'd9,   8'd9,   45},      // 06. Periodic, 90% PWM duty (CMP=LOAD)
            '{0, 8'd0,  8'd15,  8'd8,   36},      // 07. Periodic, LOAD=15, CMP=8
            '{0, 8'd8,  8'd3,   8'd2,   45},      // 08. Periodic, Big prescaler (PRESC=8)
            '{0, 8'd12, 8'd2,   8'd1,   45},      // 09. Periodic, Big prescaler (PRESC=12)
            '{0, 8'd0,  8'd255, 8'd255, 270},     // 10. Periodic, Max LOAD=255, Max CMP=255
            '{1, 8'd0,  8'd0,   8'd0,   8},       // 11. One-shot, LOAD=0 (immediate stop)
            '{1, 8'd0,  8'd5,   8'd3,   12},      // 12. One-shot, PRESC=0, LOAD=5
            '{1, 8'd2,  8'd4,   8'd2,   22},      // 13. One-shot, PRESC=2, LOAD=4
            '{1, 8'd9,  8'd2,   8'd1,   38}       // 14. One-shot, Big prescaler (PRESC=9)
        };                                                                  // Execute statement per peripheral specification

        wr_byte(4'hD, 8'h03);                     // Enable TMR_OVF and TMR_CMP interrupts
        foreach (cfgs[i]) begin                   // Run all 14 timer settings
            wr_byte(4'h0, 8'h00);                 // Ensure timer is stopped before config
            wr_byte(4'hE, 8'h3F);                 // Clear IRQ_STAT flags
            wr_byte(4'h1, cfgs[i].presc);         // Program TMR_PRESC
            wr_byte(4'h2, cfgs[i].load);          // Program TMR_LOAD
            wr_byte(4'h3, cfgs[i].cmp);           // Program TMR_CMP
            wr_byte(4'h0, {6'b0, cfgs[i].oneshot, 1'b1}); // Start timer (EN=1)
            wait_clks(cfgs[i].wait_c);            // Let timer run through overflow/compare
            rd_byte(4'h4, rdata);                 // Sample TMR_CNT
            rd_byte(4'h0, rdata);                 // Sample TMR_CTRL (verifies one-shot auto-clear)
            rd_byte(4'hE, rdata);                 // Sample IRQ_STAT
            wr_byte(4'h0, 8'h00);                 // Disable timer
            wr_byte(4'hE, 8'h3F);                 // Clear sticky interrupt flags
        end                                       // End of 14 timer configurations
    endtask                                       // End of Scenario 2 body
endclass // End of tadc_timer_seq

// =============================================================================
// Scenario 3: tadc_adc_sw_seq - Software-started conversions at corners & random
// =============================================================================
class tadc_adc_sw_seq extends tadc_base_vseq;     // Scenario 3 sequence
    `uvm_object_utils(tadc_adc_sw_seq)            // Register with factory
    function new(string name = "tadc_adc_sw_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute Scenario 3
        real corner_v[8] = '{0.0, 0.013, 0.825, 1.111, 1.650, 2.475, 3.287, 3.300}; // Corner voltages
        wr_byte(4'hD, 8'h04);                     // Enable ADC_EOC interrupt

        // 1. Test all 4 channels across all 8 corner voltages and multiple SMP/DIV settings
        for (int ch = 0; ch < 4; ch++) begin      // Loop over channels 0..3
            wr_byte(4'h6, ch[7:0] * 8'd3);        // Vary ADC_SMP (0, 3, 6, 9)
            wr_byte(4'h7, (ch == 3) ? 8'd4 : ch[7:0]); // Vary ADC_DIV (0, 1, 2, 4)
            foreach (corner_v[v]) begin           // Test each corner voltage
                set_analog(corner_v[v], corner_v[v], corner_v[v], corner_v[v]); // Drive voltage
                wr_byte(4'h5, {2'b00, ch[1:0], 2'b00, 1'b1, 1'b1}); // TRIG_SEL=0, START=1, EN=1
                wait_clks(((ch * 3) + 1 + 8) * (((ch == 3) ? 4 : ch) + 1) + 4); // Wait for EOC
                drain_fifo();                     // Read ADC_STAT, ADC_RCH, ADC_DATA
                wr_byte(4'hE, 8'h3F);             // Clear IRQ_STAT
            end                                   // End of corner voltage loop
        end                                       // End of channel loop

        // 2. Run 24 randomized software-triggered conversions
        wr_byte(4'h6, 8'd1);                      // Fast sample window (SMP=1)
        wr_byte(4'h7, 8'd0);                      // Fast divider (DIV=0)
        for (int k = 0; k < 24; k++) begin        // 24 random points across 0..3.3V
            real rv = (real'((k * 37) % 256) / 256.0) * 3.3 + 0.002; // Well-centered voltage
            bit [1:0] rch = k[1:0];               // Rotate across channels 0..3
            set_analog(rv, rv, rv, rv);           // Apply analog voltage
            wr_byte(4'h5, {2'b00, rch, 2'b00, 1'b1, 1'b1}); // Trigger SW conversion
            wait_clks(14);                        // Wait for conversion to complete
            drain_fifo();                         // Verify and pop result
        end                                       // End of random SW conversion loop
        wr_byte(4'h5, 8'h00);                     // Disable ADC
    endtask                                       // End of Scenario 3 body
endclass // End of tadc_adc_sw_seq

// =============================================================================
// Scenario 4: tadc_adc_timer_seq - Timer-started conversions (OVF & CMP) on ramps
// =============================================================================
class tadc_adc_timer_seq extends tadc_base_vseq;  // Scenario 4 sequence
    `uvm_object_utils(tadc_adc_timer_seq)         // Register with factory
    function new(string name = "tadc_adc_timer_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute Scenario 4
        wr_byte(4'h6, 8'd1);                      // ADC_SMP = 1 (2 sample ticks)
        wr_byte(4'h7, 8'd0);                      // ADC_DIV = 0 (10 clocks total per conversion)
        wr_byte(4'h1, 8'd1);                      // TMR_PRESC = 1 (tick every 2 clocks)
        wr_byte(4'h2, 8'd9);                      // TMR_LOAD = 9 (20 clocks per timer period)
        wr_byte(4'h3, 8'd4);                      // TMR_CMP = 4

        // Test both Timer Overflow trigger (TRIG_SEL=1) and Timer Compare trigger (TRIG_SEL=2)
        for (int trig_mode = 1; trig_mode <= 2; trig_mode++) begin // Loop over mode 1 and 2
            for (int ch = 0; ch < 4; ch++) begin  // Sweep all 4 channels
                wr_byte(4'h5, {2'b00, ch[1:0], trig_mode[1:0], 1'b0, 1'b1}); // Configure trigger
                wr_byte(4'h0, 8'h01);             // Start periodic timer
                for (int step = 0; step < 6; step++) begin // Ramp voltage over 6 timer periods
                    real ramp_v = (real'(step * 42) / 256.0) * 3.3 + 0.003; // Compute ramp step
                    set_analog(ramp_v, ramp_v, ramp_v, ramp_v); // Step ramp voltage
                    wait_clks(20);                // Wait 1 timer period
                    drain_fifo();                 // Pop and check timer-triggered conversion
                end                               // End of voltage ramp loop
                wr_byte(4'h0, 8'h00);             // Stop timer
                drain_fifo();                     // Drain any remaining entry
                wr_byte(4'hE, 8'h3F);             // Clear IRQ_STAT
            end                                   // End of channel sweep
        end                                       // End of trigger mode loop
        wr_byte(4'h5, 8'h00);                     // Disable ADC
    endtask                                       // End of Scenario 4 body
endclass // End of tadc_adc_timer_seq

// =============================================================================
// Scenario 5: tadc_adc_cont_seq - Continuous mode, FIFO 0..8, overflow, abort, W1C race
// =============================================================================
class tadc_adc_cont_seq extends tadc_base_vseq;   // Scenario 5 sequence
    `uvm_object_utils(tadc_adc_cont_seq)          // Register with factory
    function new(string name = "tadc_adc_cont_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute Scenario 5
        bit [7:0] stat;                           // Status readback
        set_analog(0.50, 1.111, 2.00, 3.00);      // Set distinct voltages on ch0..ch3
        wr_byte(4'h6, 8'd0);                      // ADC_SMP = 0 (9 clocks per conversion)
        wr_byte(4'h7, 8'd0);                      // ADC_DIV = 0
        wr_byte(4'hD, 8'h3F);                     // Enable all 6 interrupts

        // 1. Run continuous mode on each channel and observe FIFO levels 0..8 + overflow
        for (int ch = 0; ch < 4; ch++) begin      // Exercise TRIG_SEL=3 across all 4 channels
            wr_byte(4'h5, {2'b00, ch[1:0], 2'b11, 1'b0, 1'b1}); // TRIG_SEL=3 (continuous), EN=1
            for (int k = 0; k < 10; k++) begin    // Poll ADC_STAT as FIFO fills from 0 to 8 and overflows
                wait_clks(9);                     // 1 conversion period
                rd_byte(4'hC, stat);              // Sample every FIFO level bin 0..8
                if (k == 8) wr_byte(4'hE, 8'h04); // Test W1C race with continuous EOC!
            end                                   // End of fill loop
            // 2. Abort mid-conversion by clearing ADC_CTRL.EN=0
            wait_clks(4);                         // Mid-conversion
            wr_byte(4'h5, 8'h00);                 // Clear EN=0 -> immediate abort!
            rd_byte(4'hC, stat);                  // Verify BUSY=0 and FULL=1 (level=8)
            rd_byte(4'hE, stat);                  // Verify FIFO_OVR flag set
            drain_fifo();                         // Pop all 8 entries back down to level 0
            rd_byte(4'hC, stat);                  // Sample empty state (level=0)
            wr_byte(4'hE, 8'h3F);                 // Clear all sticky flags
        end                                       // End of channel loop
    endtask                                       // End of Scenario 5 body
endclass // End of tadc_adc_cont_seq

// =============================================================================
// Scenario 6: tadc_window_seq - Window comparator including exact boundary codes
// =============================================================================
class tadc_window_seq extends tadc_base_vseq;     // Scenario 6 sequence
    `uvm_object_utils(tadc_window_seq)            // Register with factory
    function new(string name = "tadc_window_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute Scenario 6
        bit [7:0] irq_s;                          // Sampled IRQ_STAT byte
        int test_codes[5] = '{63, 64, 128, 192, 193}; // Boundary and interior codes
        bit exp_wd[5]     = '{1'b1, 1'b0, 1'b0, 1'b0, 1'b1}; // Expected ADC_WD flags

        wr_byte(4'h8, 8'd64);                     // Set ADC_THR_LO = 64 (0x40)
        wr_byte(4'h9, 8'd192);                    // Set ADC_THR_HI = 192 (0xC0)
        wr_byte(4'h6, 8'd1);                      // ADC_SMP = 1
        wr_byte(4'h7, 8'd0);                      // ADC_DIV = 0

        foreach (test_codes[i]) begin             // Test each boundary code
            real v_target = ((real'(test_codes[i]) + 0.5) / 256.0) * 3.3; // Center of code bin
            set_analog(v_target, v_target, v_target, v_target); // Drive precision voltage
            wr_byte(4'hE, 8'h3F);                 // Clear IRQ_STAT before conversion
            wr_byte(4'h5, 8'h03);                 // Start single SW conversion on Ch0
            wait_clks(14);                        // Wait for EOC
            rd_byte(4'hE, irq_s);                 // Read IRQ_STAT
            if (irq_s[3] !== exp_wd[i]) begin     // Check ADC_WD bit (bit 3)
                `uvm_error("WIN_TEST", $sformatf(                           // Format and print simulation status message
                    "Window check failed at code %0d: ADC_WD=%0b != exp=%0b", // Execute statement per peripheral specification
                    test_codes[i], irq_s[3], exp_wd[i]))                    // Execute statement per peripheral specification
            end                                   // End of boundary assertion
            drain_fifo();                         // Pop result from FIFO
        end                                       // End of boundary test loop

        wr_byte(4'h8, 8'h00);                     // Restore default THR_LO = 0x00
        wr_byte(4'h9, 8'hFF);                     // Restore default THR_HI = 0xFF
        wr_byte(4'hE, 8'h3F);                     // Clear IRQ_STAT
    endtask                                       // End of Scenario 6 body
endclass // End of tadc_window_seq

// =============================================================================
// Scenario 7: tadc_noise_seq - Analog offset and noise checked against tolerance
// =============================================================================
class tadc_noise_seq extends tadc_base_vseq;      // Scenario 7 sequence
    `uvm_object_utils(tadc_noise_seq)             // Register with factory
    function new(string name = "tadc_noise_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute Scenario 7
        env.sb.tolerance_lsb = 6;                 // Allow +/- 6 LSB tolerance under noise/offset
        wr_byte(4'h6, 8'd2);                      // ADC_SMP = 2
        wr_byte(4'h7, 8'd0);                      // ADC_DIV = 0

        for (int k = 0; k < 20; k++) begin        // Perform 20 noisy conversions across all channels
            real base_v = 0.3 + (real'(k) * 0.13);// Sweep from 0.3V to 2.77V
            set_analog(base_v, base_v, base_v, base_v, 0.015, 0.025); // +15mV offset, +/-25mV noise
            wr_byte(4'h5, {2'b00, k[1:0], 2'b00, 1'b1, 1'b1}); // Trigger SW conversion
            wait_clks(15);                        // Wait for conversion completion
            drain_fifo();                         // Read and verify result within tolerance
        end                                       // End of noisy conversion loop

        set_analog(0.0, 0.0, 0.0, 0.0, 0.0, 0.0); // Reset analog offset and noise to 0.0V
        env.sb.tolerance_lsb = 0;                 // Restore strict 0-LSB tolerance
        wr_byte(4'h5, 8'h00);                     // Disable ADC
        wr_byte(4'hE, 8'h3F);                     // Clear IRQ_STAT
    endtask                                       // End of Scenario 7 body
endclass // End of tadc_noise_seq

// =============================================================================
// Scenario 8: tadc_trig_miss_seq - Triggers faster than conversions (TRIG_MISS)
// =============================================================================
class tadc_trig_miss_seq extends tadc_base_vseq;  // Scenario 8 sequence
    `uvm_object_utils(tadc_trig_miss_seq)         // Register with factory
    function new(string name = "tadc_trig_miss_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute Scenario 8
        bit [7:0] irq_s;                          // Sampled IRQ_STAT byte
        set_analog(1.65, 1.65, 1.65, 1.65);       // Mid-scale input voltage

        // 1. Software trigger while busy
        wr_byte(4'h6, 8'd10);                     // Slow sample window (SMP=10 -> 19 clocks)
        wr_byte(4'h7, 8'd1);                      // Slow divider (DIV=1 -> 38 clocks total)
        wr_byte(4'hE, 8'h3F);                     // Clear IRQ_STAT
        wr_byte(4'h5, 8'h03);                     // Launch first SW conversion
        wait_clks(5);                             // Wait 5 clocks (ADC is busy in SAMPLE)
        wr_byte(4'h5, 8'h03);                     // Issue second SW START while busy!
        wait_clks(40);                            // Wait for conversion to finish
        rd_byte(4'hE, irq_s);                     // Read IRQ_STAT
        if (!irq_s[5]) begin                      // Verify bit 5 (TRIG_MISS) is set
            `uvm_error("TRIG_MISS", "Software trigger while busy did not set TRIG_MISS!") // Format and print simulation status message
        end                                       // End of SW trig_miss check
        drain_fifo();                             // Pop completed result
        wr_byte(4'hE, 8'h3F);                     // Clear IRQ_STAT

        // 2. Fast Timer Overflow trigger faster than slow ADC conversion
        wr_byte(4'h1, 8'd0);                      // TMR_PRESC = 0
        wr_byte(4'h2, 8'd4);                      // TMR_LOAD = 4 (overflow every 5 clocks!)
        wr_byte(4'h5, 8'h05);                     // ADC_CTRL: TRIG_SEL=1 (timer ovf), EN=1
        wr_byte(4'h0, 8'h01);                     // Start fast periodic timer
        wait_clks(45);                            // Let timer fire multiple triggers while ADC is busy
        wr_byte(4'h0, 8'h00);                     // Stop timer
        wr_byte(4'h5, 8'h00);                     // Stop ADC
        rd_byte(4'hE, irq_s);                     // Read IRQ_STAT
        if (!irq_s[5]) begin                      // Verify bit 5 (TRIG_MISS) is set
            `uvm_error("TRIG_MISS", "Fast timer overflow trigger did not set TRIG_MISS!") // Format and print simulation status message
        end                                       // End of timer trig_miss check
        drain_fifo();                             // Drain FIFO
        wr_byte(4'hE, 8'h3F);                     // Clear IRQ_STAT
    endtask                                       // End of Scenario 8 body
endclass // End of tadc_trig_miss_seq

// =============================================================================
// Scenario 9: tadc_random_seq - Random settings + random register traffic
// =============================================================================
class tadc_random_seq extends tadc_base_vseq;     // Scenario 9 sequence
    `uvm_object_utils(tadc_random_seq)            // Register with factory
    function new(string name = "tadc_random_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute Scenario 9
        bit [7:0] rdata;                          // Readback variable
        for (int iter = 0; iter < 30; iter++) begin // 30 randomized stress iterations
            real v0 = (real'($urandom_range(0, 255)) + 0.5) * (3.3 / 256.0); // Random ch0 volts
            real v1 = (real'($urandom_range(0, 255)) + 0.5) * (3.3 / 256.0); // Random ch1 volts
            real v2 = (real'($urandom_range(0, 255)) + 0.5) * (3.3 / 256.0); // Random ch2 volts
            real v3 = (real'($urandom_range(0, 255)) + 0.5) * (3.3 / 256.0); // Random ch3 volts
            bit [1:0] ch   = bit'($urandom_range(0, 3)); // Random channel 0..3
            bit [1:0] trig = bit'($urandom_range(0, 3)); // Random trigger mode 0..3
            bit [7:0] smp  = byte'($urandom_range(0, 3)); // Random sample time 0..3
            bit [7:0] div  = byte'($urandom_range(0, 2)); // Random clock divider 0..2
            bit       os   = bit'($urandom_range(0, 1));  // Random one-shot flag

            set_analog(v0, v1, v2, v3);           // Apply random voltages to ch0..ch3
            wr_byte(4'h0, 8'h00);                 // Stop timer before reconfiguring
            wr_byte(4'h5, 8'h00);                 // Stop ADC before reconfiguring
            wr_byte(4'h1, byte'($urandom_range(0, 3)));  // Random TMR_PRESC
            wr_byte(4'h2, byte'($urandom_range(4, 15))); // Random TMR_LOAD
            wr_byte(4'h3, byte'($urandom_range(1, 10))); // Random TMR_CMP
            wr_byte(4'h6, smp);                   // Random ADC_SMP
            wr_byte(4'h7, div);                   // Random ADC_DIV
            wr_byte(4'h8, byte'($urandom_range(0, 64))); // Random ADC_THR_LO
            wr_byte(4'h9, byte'($urandom_range(192, 255))); // Random ADC_THR_HI
            wr_byte(4'hD, byte'($urandom_range(0, 63))); // Random IRQ_EN
            wr_byte(4'h5, {2'b00, ch, trig, (trig == 2'd0), 1'b1}); // Enable ADC
            wr_byte(4'h0, {6'b0, os, 1'b1});      // Enable Timer
            wait_clks(45);                        // Let peripheral run
            wr_byte(4'h0, 8'h00);                 // Stop timer
            wr_byte(4'h5, 8'h00);                 // Stop ADC
            rd_byte(4'h4, rdata);                 // Read TMR_CNT
            rd_byte(4'hE, rdata);                 // Read IRQ_STAT
            drain_fifo();                         // Drain and verify all queued conversions
            wr_byte(4'hE, 8'h3F);                 // Clear IRQ_STAT
        end                                       // End of random iteration loop
    endtask                                       // End of Scenario 9 body
endclass // End of tadc_random_seq

// =============================================================================
// Scenario 10: tadc_all_seq - Runs all 9 scenarios above sequentially
// =============================================================================
class tadc_all_seq extends tadc_base_vseq;        // Full regression sequence (Chapter 14 & 15)
    `uvm_object_utils(tadc_all_seq)               // Register with factory
    function new(string name = "tadc_all_seq"); super.new(name); endfunction // Constructor

    virtual task body();                          // Execute all 9 sub-sequences in order
        // SystemVerilog rule: ALL declarations must come BEFORE the first statement in a block,
        // so the 9 sequence handles are declared first and created/started afterwards.
        tadc_reg_seq       s1;                    // Handle for Scenario 1 (register test)
        tadc_timer_seq     s2;                    // Handle for Scenario 2 (timer settings)
        tadc_adc_sw_seq    s3;                    // Handle for Scenario 3 (software-started ADC)
        tadc_adc_timer_seq s4;                    // Handle for Scenario 4 (timer-started ADC)
        tadc_adc_cont_seq  s5;                    // Handle for Scenario 5 (continuous ADC + FIFO)
        tadc_window_seq    s6;                    // Handle for Scenario 6 (window comparator)
        tadc_noise_seq     s7;                    // Handle for Scenario 7 (offset and noise)
        tadc_trig_miss_seq s8;                    // Handle for Scenario 8 (missed triggers)
        tadc_random_seq    s9;                    // Handle for Scenario 9 (random traffic)

        s1 = tadc_reg_seq::type_id::create("s1");       s1.env = env; s1.start(null); // Run 1
        s2 = tadc_timer_seq::type_id::create("s2");     s2.env = env; s2.start(null); // Run 2
        s3 = tadc_adc_sw_seq::type_id::create("s3");    s3.env = env; s3.start(null); // Run 3
        s4 = tadc_adc_timer_seq::type_id::create("s4"); s4.env = env; s4.start(null); // Run 4
        s5 = tadc_adc_cont_seq::type_id::create("s5");  s5.env = env; s5.start(null); // Run 5
        s6 = tadc_window_seq::type_id::create("s6");    s6.env = env; s6.start(null); // Run 6
        s7 = tadc_noise_seq::type_id::create("s7");     s7.env = env; s7.start(null); // Run 7
        s8 = tadc_trig_miss_seq::type_id::create("s8"); s8.env = env; s8.start(null); // Run 8
        s9 = tadc_random_seq::type_id::create("s9");    s9.env = env; s9.start(null); // Run 9
    endtask                                       // End of tadc_all_seq body
endclass // End of tadc_all_seq

`endif // End of TIMER_ADC_SEQ_LIB_SV include guard
`endif // End of INSIDE_TIMER_ADC_PKG package scope guard