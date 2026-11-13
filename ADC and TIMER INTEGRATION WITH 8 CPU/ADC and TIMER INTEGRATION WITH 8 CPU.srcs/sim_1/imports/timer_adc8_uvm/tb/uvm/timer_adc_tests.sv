`ifdef INSIDE_TIMER_ADC_PKG // Compile inside timer_adc_pkg package scope (safe when added to Vivado GUI)
`ifndef TIMER_ADC_TESTS_SV // Prevent duplicate inclusion of timer_adc_tests.sv
`define TIMER_ADC_TESTS_SV // Mark timer_adc_tests.sv as included

// =============================================================================
// File        : timer_adc_tests.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : 10 Runnable UVM Tests (tadc_reg_test .. tadc_all_test)
//               selectable via +UVM_TESTNAME=<test_name> (Chapter 14, Page 15).
// =============================================================================

// -----------------------------------------------------------------------------
// Base UVM Test Class (tadc_base_test)
// -----------------------------------------------------------------------------
class tadc_base_test extends uvm_test;            // Common base class for all 10 UVM tests

    `uvm_component_utils(tadc_base_test)          // Register base test with UVM factory

    timer_adc_env env;                            // Top-level UVM environment handle

    function new(string name, uvm_component parent); // Constructor
        super.new(name, parent);                  // Call base uvm_test constructor
    endfunction                                   // End of constructor

    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);                 // Call base build_phase
        env = timer_adc_env::type_id::create("env", this); // Create verification environment
    endfunction                                   // End of build_phase

    virtual function void report_phase(uvm_phase phase); // UVM report phase
        uvm_report_server srv = uvm_report_server::get_server(); // Fetch UVM report server
        int err_total = srv.get_severity_count(UVM_ERROR) +                 // Execute statement per peripheral specification
                        srv.get_severity_count(UVM_FATAL) +                 // Execute statement per peripheral specification
                        env.sb.error_cnt;         // Sum all UVM and scoreboard errors
        super.report_phase(phase);                // Call base report_phase
        if (err_total == 0) begin                 // Check if zero errors occurred
            `uvm_info("TEST_RESULT", $sformatf("*** UVM TEST %s PASSED ***", get_type_name()), UVM_NONE) // Format and print simulation status message
        end else begin                            // At least one error was recorded
            `uvm_error("TEST_RESULT", $sformatf("*** UVM TEST %s FAILED (%0d errors) ***", get_type_name(), err_total)) // Format and print simulation status message
        end                                       // End of pass/fail print
    endfunction                                   // End of report_phase

endclass // End of tadc_base_test

// -----------------------------------------------------------------------------
// Test 1: tadc_reg_test — Reset values, bit-bash, write/read-back, bad addresses
// -----------------------------------------------------------------------------
class tadc_reg_test extends tadc_base_test;       // Test 1 class
    `uvm_component_utils(tadc_reg_test)           // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_reg_seq seq = tadc_reg_seq::type_id::create("seq"); // Create sequence 1
        phase.raise_objection(this);              // Raise objection to keep test alive
        seq.env = env; seq.start(null);           // Run sequence against environment
        phase.drop_objection(this);               // Drop objection when finished
    endtask                                       // End of run_phase
endclass // End of tadc_reg_test

// -----------------------------------------------------------------------------
// Test 2: tadc_timer_test — 14 timer settings: periodic, one-shot, LOAD=0, big prescaler
// -----------------------------------------------------------------------------
class tadc_timer_test extends tadc_base_test;     // Test 2 class
    `uvm_component_utils(tadc_timer_test)         // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_timer_seq seq = tadc_timer_seq::type_id::create("seq"); // Create sequence 2
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run sequence
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_timer_test

// -----------------------------------------------------------------------------
// Test 3: tadc_adc_sw_test — Software-started conversions at corner voltages and random
// -----------------------------------------------------------------------------
class tadc_adc_sw_test extends tadc_base_test;    // Test 3 class
    `uvm_component_utils(tadc_adc_sw_test)        // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_adc_sw_seq seq = tadc_adc_sw_seq::type_id::create("seq"); // Create sequence 3
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run sequence
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_adc_sw_test

// -----------------------------------------------------------------------------
// Test 4: tadc_adc_timer_test — Timer-started conversions of ramping inputs
// -----------------------------------------------------------------------------
class tadc_adc_timer_test extends tadc_base_test; // Test 4 class
    `uvm_component_utils(tadc_adc_timer_test)     // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_adc_timer_seq seq = tadc_adc_timer_seq::type_id::create("seq"); // Create sequence 4
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run sequence
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_adc_timer_test

// -----------------------------------------------------------------------------
// Test 5: tadc_adc_cont_test — Continuous mode, FIFO overflow, abort, clear races
// -----------------------------------------------------------------------------
class tadc_adc_cont_test extends tadc_base_test;  // Test 5 class
    `uvm_component_utils(tadc_adc_cont_test)      // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_adc_cont_seq seq = tadc_adc_cont_seq::type_id::create("seq"); // Create sequence 5
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run sequence
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_adc_cont_test

// -----------------------------------------------------------------------------
// Test 6: tadc_window_test — Window comparator incl. exact boundary codes
// -----------------------------------------------------------------------------
class tadc_window_test extends tadc_base_test;    // Test 6 class
    `uvm_component_utils(tadc_window_test)        // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_window_seq seq = tadc_window_seq::type_id::create("seq"); // Create sequence 6
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run sequence
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_window_test

// -----------------------------------------------------------------------------
// Test 7: tadc_noise_test — Analog offset and noise, checked against a tolerance
// -----------------------------------------------------------------------------
class tadc_noise_test extends tadc_base_test;     // Test 7 class
    `uvm_component_utils(tadc_noise_test)         // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_noise_seq seq = tadc_noise_seq::type_id::create("seq"); // Create sequence 7
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run sequence
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_noise_test

// -----------------------------------------------------------------------------
// Test 8: tadc_trig_miss_test — Triggers faster than conversions
// -----------------------------------------------------------------------------
class tadc_trig_miss_test extends tadc_base_test; // Test 8 class
    `uvm_component_utils(tadc_trig_miss_test)     // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_trig_miss_seq seq = tadc_trig_miss_seq::type_id::create("seq"); // Create sequence 8
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run sequence
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_trig_miss_test

// -----------------------------------------------------------------------------
// Test 9: tadc_random_test — Random settings + random register traffic
// -----------------------------------------------------------------------------
class tadc_random_test extends tadc_base_test;    // Test 9 class
    `uvm_component_utils(tadc_random_test)        // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_random_seq seq = tadc_random_seq::type_id::create("seq"); // Create sequence 9
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run sequence
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_random_test

// -----------------------------------------------------------------------------
// Test 10: tadc_all_test — All of the above, one after another
// -----------------------------------------------------------------------------
class tadc_all_test extends tadc_base_test;       // Test 10 full regression class
    `uvm_component_utils(tadc_all_test)           // Register with UVM factory
    function new(string name, uvm_component parent); super.new(name, parent); endfunction // Declare class method or function
    virtual task run_phase(uvm_phase phase);      // UVM run phase
        tadc_all_seq seq = tadc_all_seq::type_id::create("seq"); // Create full suite sequence
        phase.raise_objection(this);              // Raise objection
        seq.env = env; seq.start(null);           // Run all 9 test scenarios sequentially
        phase.drop_objection(this);               // Drop objection
    endtask                                       // End of run_phase
endclass // End of tadc_all_test

`endif // End of TIMER_ADC_TESTS_SV include guard
`endif // End of INSIDE_TIMER_ADC_PKG package scope guard
