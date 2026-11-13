`ifdef INSIDE_TIMER_ADC_PKG // Compile inside timer_adc_pkg package scope (safe when added to Vivado GUI)
`ifndef APB_AGENT_SV // Prevent duplicate inclusion of apb_agent.sv
`define APB_AGENT_SV // Mark apb_agent.sv as included

// =============================================================================
// File        : apb_agent.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : UVM APB Agent File containing apb_seq_item, apb_sequencer,
//               apb_driver, apb_monitor, and apb_agent (Chapter 12, 13).
// =============================================================================

// -----------------------------------------------------------------------------
// 1. APB Sequence Item (apb_seq_item)
// -----------------------------------------------------------------------------
class apb_seq_item extends uvm_sequence_item; // Transaction object for APB bus access

    rand bit       pwrite;  // Transfer direction: 1 = write (ST), 0 = read (LD)
    rand bit [3:0] paddr;   // 4-bit register offset address (0x0 to 0xF)
    rand bit [7:0] pwdata;  // 8-bit write data byte
    bit      [7:0] prdata;  // 8-bit read data byte captured from peripheral
    bit            pslverr; // Slave error response captured from peripheral
    bit            irq;     // Sampled state of interrupt request wire

    `uvm_object_utils_begin(apb_seq_item)           // Register item with UVM factory
        `uvm_field_int(pwrite,  UVM_ALL_ON)         // Enable automation for pwrite
        `uvm_field_int(paddr,   UVM_ALL_ON)         // Enable automation for paddr
        `uvm_field_int(pwdata,  UVM_ALL_ON)         // Enable automation for pwdata
        `uvm_field_int(prdata,  UVM_ALL_ON)         // Enable automation for prdata
        `uvm_field_int(pslverr, UVM_ALL_ON)         // Enable automation for pslverr
        `uvm_field_int(irq,     UVM_ALL_ON)         // Enable automation for irq
    `uvm_object_utils_end                           // End of UVM field macros

    function new(string name = "apb_seq_item");     // Constructor for apb_seq_item
        super.new(name);                            // Call base uvm_sequence_item constructor
    endfunction                                     // End of constructor

    function string convert2string();               // Format transaction as readable string
        return $sformatf("APB %s addr=0x%01h wdata=0x%02h rdata=0x%02h err=%0b irq=%0b", // Execute statement per peripheral specification
                         pwrite ? "WR" : "RD", paddr, pwdata, prdata, pslverr, irq); // Return formatted string
    endfunction                                     // End of convert2string

endclass // End of apb_seq_item class

// -----------------------------------------------------------------------------
// 2. APB Sequencer (apb_sequencer)
// -----------------------------------------------------------------------------
typedef uvm_sequencer #(apb_seq_item) apb_sequencer; // Parameterize standard UVM sequencer

// -----------------------------------------------------------------------------
// 3. APB Driver (apb_driver)
// -----------------------------------------------------------------------------
class apb_driver extends uvm_driver #(apb_seq_item); // Translates apb_seq_item into pin wiggles

    `uvm_component_utils(apb_driver)                // Register driver with UVM factory

    virtual apb_if vif;                             // Virtual interface handle to apb_if

    function new(string name, uvm_component parent);// Constructor for apb_driver
        super.new(name, parent);                    // Call base uvm_driver constructor
    endfunction                                     // End of constructor

    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);                   // Call base build_phase
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin // Retrieve vif
            `uvm_fatal("APB_DRV", "Failed to get virtual apb_if from uvm_config_db!") // Report fatal if missing
        end                                         // End of config_db check
    endfunction                                     // End of build_phase

    virtual task run_phase(uvm_phase phase);        // Main UVM run phase task
        apb_seq_item req_item;                      // Handle to current sequence item
        vif.reset_bus();                            // Initialize bus signals to idle
        @(posedge vif.rst_n);                       // Wait until active-low reset is deasserted
        forever begin                               // Loop continuously for the test duration
            seq_item_port.get_next_item(req_item);  // Fetch next bus transaction from sequencer
            drive_item(req_item);                   // Drive transaction on APB interface
            seq_item_port.item_done();              // Notify sequencer that transaction completed
        end                                         // End of forever loop
    endtask                                         // End of run_phase

    virtual task drive_item(apb_seq_item item);     // Execute 1-cycle APB transfer
        @(posedge vif.clk);                         // Align to rising clock edge
        vif.psel    <= 1'b1;                        // Assert peripheral select
        vif.penable <= 1'b1;                        // Assert enable for single-cycle transfer
        vif.pwrite  <= item.pwrite;                 // Drive read/write direction
        vif.paddr   <= item.paddr;                  // Drive 4-bit register address
        vif.pwdata  <= item.pwrite ? item.pwdata : 8'h00; // Drive write data if writing
        @(posedge vif.clk);                         // Wait for active clock edge
        item.prdata  = vif.prdata;                  // Sample read data returned by DUT
        item.pslverr = vif.pslverr;                 // Sample slave error flag
        item.irq     = vif.irq;                     // Sample interrupt line state
        vif.psel    <= 1'b0;                        // Deassert peripheral select
        vif.penable <= 1'b0;                        // Deassert enable signal
        vif.pwrite  <= 1'b0;                        // Return direction wire to read
    endtask                                         // End of drive_item task

endclass // End of apb_driver class

// -----------------------------------------------------------------------------
// 4. APB Monitor (apb_monitor)
// -----------------------------------------------------------------------------
class apb_monitor extends uvm_monitor;              // Passively observes APB bus transfers

    `uvm_component_utils(apb_monitor)               // Register monitor with UVM factory

    virtual apb_if                   vif;           // Virtual interface handle to apb_if
    uvm_analysis_port #(apb_seq_item) ap;           // Analysis port broadcasting observed items

    function new(string name, uvm_component parent);// Constructor for apb_monitor
        super.new(name, parent);                    // Call base uvm_monitor constructor
        ap = new("ap", this);                       // Instantiate analysis port
    endfunction                                     // End of constructor

    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);                   // Call base build_phase
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin // Retrieve vif
            `uvm_fatal("APB_MON", "Failed to get virtual apb_if from uvm_config_db!") // Report fatal if missing
        end                                         // End of config_db check
    endfunction                                     // End of build_phase

    virtual task run_phase(uvm_phase phase);        // Main UVM run phase task
        @(posedge vif.rst_n);                       // Wait until reset is released
        forever begin                               // Observe every rising clock edge
            @(posedge vif.clk);                     // Wait for clock edge
            if (vif.psel && vif.penable && vif.pready) begin // Detect valid APB transfer
                apb_seq_item tr = apb_seq_item::type_id::create("tr"); // Create transaction copy
                tr.pwrite  = vif.pwrite;            // Record direction (1=write, 0=read)
                tr.paddr   = vif.paddr;             // Record 4-bit register address
                tr.pwdata  = vif.pwdata;            // Record 8-bit write data
                tr.prdata  = vif.prdata;            // Record 8-bit read data
                tr.pslverr = vif.pslverr;           // Record slave error response
                tr.irq     = vif.irq;               // Record interrupt output state
                ap.write(tr);                       // Broadcast transaction to scoreboard & coverage
            end                                     // End of transfer detection
        end                                         // End of forever loop
    endtask                                         // End of run_phase

endclass // End of apb_monitor class

// -----------------------------------------------------------------------------
// 5. APB Agent (apb_agent)
// -----------------------------------------------------------------------------
class apb_agent extends uvm_agent;                  // Encapsulates sequencer, driver, and monitor

    `uvm_component_utils(apb_agent)                 // Register agent with UVM factory

    apb_sequencer sqr;                              // Sequencer handle
    apb_driver    drv;                              // Driver handle
    apb_monitor   mon;                              // Monitor handle

    function new(string name, uvm_component parent);// Constructor for apb_agent
        super.new(name, parent);                    // Call base uvm_agent constructor
    endfunction                                     // End of constructor

    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);                   // Call base build_phase
        mon = apb_monitor::type_id::create("mon", this); // Always build passive monitor
        if (get_is_active() == UVM_ACTIVE) begin    // Check if agent is configured as active
            sqr = apb_sequencer::type_id::create("sqr", this); // Create sequencer
            drv = apb_driver::type_id::create("drv", this);    // Create driver
        end                                         // End of active agent check
    endfunction                                     // End of build_phase

    virtual function void connect_phase(uvm_phase phase); // UVM connect phase
        super.connect_phase(phase);                 // Call base connect_phase
        if (get_is_active() == UVM_ACTIVE) begin    // Connect driver to sequencer if active
            drv.seq_item_port.connect(sqr.seq_item_export); // Wire seq_item_port to export
        end                                         // End of active connection check
    endfunction                                     // End of connect_phase

endclass // End of apb_agent class

`endif // End of APB_AGENT_SV include guard
`endif // End of INSIDE_TIMER_ADC_PKG package scope guard
