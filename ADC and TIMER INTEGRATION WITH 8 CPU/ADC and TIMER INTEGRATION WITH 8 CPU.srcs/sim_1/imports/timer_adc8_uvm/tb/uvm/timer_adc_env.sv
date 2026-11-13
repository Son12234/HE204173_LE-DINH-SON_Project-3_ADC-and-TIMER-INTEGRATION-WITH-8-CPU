`ifdef INSIDE_TIMER_ADC_PKG // Compile inside timer_adc_pkg package scope (safe when added to Vivado GUI)
`ifndef TIMER_ADC_ENV_SV // Prevent duplicate inclusion of timer_adc_env.sv
`define TIMER_ADC_ENV_SV // Mark timer_adc_env.sv as included

// =============================================================================
// File        : timer_adc_env.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : UVM Verification Environment instantiating and wiring the
//               APB Agent, Analog Agent, RAL Register Block, Adapter,
//               Predictor, Scoreboard, and Coverage Collector (Chapter 13, 14).
// =============================================================================

class timer_adc_env extends uvm_env;              // Top-level UVM verification environment

    `uvm_component_utils(timer_adc_env)           // Register environment with UVM factory

    // -------------------------------------------------------------------------
    // Child Sub-Components Inside timer_adc_env (Chapter 13 Diagram, Page 14)
    // -------------------------------------------------------------------------
    apb_agent                         apb_agt;    // Active 8-bit APB bus agent
    adc_agent                         adc_agt;    // Active Analog Front-End (AFE) agent
    timer_adc_reg_block               rm;         // RAL software model of the 16 registers
    apb_reg_adapter                   adapter;    // Translates RAL reg ops <-> apb_seq_item
    uvm_reg_predictor #(apb_seq_item) predictor;  // Updates RAL mirror from observed bus items
    timer_adc_scoreboard              sb;         // Reference model and self-checking scoreboard
    timer_adc_coverage                cov;        // Functional coverage collector (5 covergroups)

    function new(string name, uvm_component parent); // Environment constructor
        super.new(name, parent);                  // Call base uvm_env constructor
    endfunction                                   // End of constructor

    // -------------------------------------------------------------------------
    // UVM Build Phase: Create Agents, RAL Model, Predictor, Scoreboard, Coverage
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);                 // Call base build_phase
        apb_agt   = apb_agent::type_id::create("apb_agt", this);     // Build APB agent
        adc_agt   = adc_agent::type_id::create("adc_agt", this);     // Build Analog agent
        sb        = timer_adc_scoreboard::type_id::create("sb", this);  // Build Scoreboard
        cov       = timer_adc_coverage::type_id::create("cov", this);   // Build Coverage
        adapter   = apb_reg_adapter::type_id::create("adapter");     // Build RAL bus adapter
        predictor = uvm_reg_predictor#(apb_seq_item)::type_id::create("predictor", this); // Build predictor

        // Create and lock the 16-register RAL model if not passed from top-level test
        if (rm == null) begin                     // Check if register block needs creation
            rm = timer_adc_reg_block::type_id::create("rm"); // Instantiate RAL register block
            rm.build();                           // Build and lock all 16 registers
            rm.reset();                           // Initialize RAL mirror to reset values
        end                                       // End of RAL creation block
    endfunction                                   // End of build_phase

    // -------------------------------------------------------------------------
    // UVM Connect Phase: Wire Sequencer, Predictor, Scoreboard, and Coverage
    // -------------------------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase); // UVM connect phase
        super.connect_phase(phase);               // Call base connect_phase

        // Connect RAL default map to APB sequencer via adapter
        rm.default_map.set_sequencer(apb_agt.sqr, adapter); // Route rm.write / rm.read to apb_agt
        rm.default_map.set_auto_predict(0);       // Use explicit bus monitor predictor

        // Configure explicit RAL predictor on APB monitor port
        predictor.map     = rm.default_map;       // Point predictor to RAL default map
        predictor.adapter = adapter;              // Attach APB register adapter
        apb_agt.mon.ap.connect(predictor.bus_in); // Feed monitored APB items into predictor

        // Connect APB monitor analysis port to Scoreboard and Coverage
        apb_agt.mon.ap.connect(sb.apb_imp);       // Feed APB transactions to Scoreboard
        apb_agt.mon.ap.connect(cov.apb_imp);      // Feed APB transactions to Coverage

        // Connect Analog/Event monitor analysis port to Scoreboard and Coverage
        adc_agt.mon.ap.connect(sb.adc_imp);       // Feed ADC/Timer events to Scoreboard
        adc_agt.mon.ap.connect(cov.adc_imp);      // Feed ADC/Timer events to Coverage
    endfunction                                   // End of connect_phase

endclass // End of timer_adc_env class

`endif // End of TIMER_ADC_ENV_SV include guard
`endif // End of INSIDE_TIMER_ADC_PKG package scope guard
