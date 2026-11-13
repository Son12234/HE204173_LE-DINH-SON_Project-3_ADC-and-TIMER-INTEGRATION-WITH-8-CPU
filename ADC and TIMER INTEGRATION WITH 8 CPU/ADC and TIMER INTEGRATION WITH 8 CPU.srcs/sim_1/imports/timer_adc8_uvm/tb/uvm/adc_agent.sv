`ifdef INSIDE_TIMER_ADC_PKG // Compile inside timer_adc_pkg package scope (safe when added to Vivado GUI)
`ifndef ADC_AGENT_SV // Prevent duplicate inclusion of adc_agent.sv
`define ADC_AGENT_SV // Mark adc_agent.sv as included

// =============================================================================
// File        : adc_agent.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : UVM Analog Front-End Agent containing adc_seq_item,
//               adc_sequencer, adc_driver, adc_monitor, and adc_agent
//               (Chapter 12, 13, 14).
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Analog Event / Stimulus Transaction Item (adc_seq_item)
// -----------------------------------------------------------------------------
class adc_seq_item extends uvm_sequence_item; // Represents analog stimulus or monitored event

    typedef enum bit [1:0] {                  // Enumerate analog event/command categories
        ADC_SET_VOLTS = 2'd0,                 // Command to update sensor channel voltages/noise
        ADC_EOC_EVENT = 2'd1,                 // Observed ADC End-Of-Conversion event
        TMR_OVF_EVENT = 2'd2,                 // Observed Timer Overflow pulse event
        TMR_CMP_EVENT = 2'd3                  // Observed Timer Compare pulse event
    } kind_e;                                 // End of event kind enumeration

    kind_e     kind;                          // Type of analog item
    real       vin [0:3];                     // 4 channel voltages in Volts (0.0 to 3.3V)
    real       offset_v;                      // Analog DC offset in Volts
    real       noise_amp_v;                   // Analog noise amplitude in Volts
    real       vhold_at_eoc;                  // Sample-and-hold capacitor voltage at EOC
    bit  [1:0] conv_ch;                       // Channel index converted by SAR ADC (0..3)
    bit  [7:0] conv_result;                   // Actual 8-bit digital code produced by DUT
    bit  [7:0] exp_ideal_code;                // Expected 8-bit code from held voltage

    `uvm_object_utils_begin(adc_seq_item)     // Register adc_seq_item with UVM factory
        `uvm_field_enum(kind_e, kind, UVM_ALL_ON)       // Register kind enum
        `uvm_field_int(conv_ch,        UVM_ALL_ON)      // Register converted channel
        `uvm_field_int(conv_result,    UVM_ALL_ON)      // Register actual 8-bit result
        `uvm_field_int(exp_ideal_code, UVM_ALL_ON)      // Register expected 8-bit code
    `uvm_object_utils_end                     // End of UVM field macros

    function new(string name = "adc_seq_item"); // Constructor for adc_seq_item
        super.new(name);                      // Call base constructor
        kind        = ADC_SET_VOLTS;          // Default to voltage update command
        vin[0]      = 0.0;                    // Initialize ch0 voltage
        vin[1]      = 0.0;                    // Initialize ch1 voltage
        vin[2]      = 0.0;                    // Initialize ch2 voltage
        vin[3]      = 0.0;                    // Initialize ch3 voltage
        offset_v    = 0.0;                    // Initialize DC offset to 0.0V
        noise_amp_v = 0.0;                    // Initialize noise amplitude to 0.0V
    endfunction                               // End of constructor

    function string convert2string();         // Convert item to human-readable string
        return $sformatf("ADC_ITEM kind=%s ch=%0d res=0x%02h exp=0x%02h vhold=%0.4fV", // Execute statement per peripheral specification
                         kind.name(), conv_ch, conv_result, exp_ideal_code, vhold_at_eoc); // Format string
    endfunction                               // End of convert2string

endclass // End of adc_seq_item class

// -----------------------------------------------------------------------------
// 2. Analog Sequencer (adc_sequencer)
// -----------------------------------------------------------------------------
typedef uvm_sequencer #(adc_seq_item) adc_sequencer; // Sequencer for analog voltage sequences

// -----------------------------------------------------------------------------
// 3. Analog Driver (adc_driver)
// -----------------------------------------------------------------------------
class adc_driver extends uvm_driver #(adc_seq_item); // Drives real voltages onto adc_if

    `uvm_component_utils(adc_driver)          // Register adc_driver with UVM factory

    virtual adc_if vif;                       // Virtual interface handle to adc_if

    function new(string name, uvm_component parent); // Constructor for adc_driver
        super.new(name, parent);              // Call base constructor
    endfunction                               // End of constructor

    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);             // Call base build_phase
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif)) begin // Fetch adc_if
            `uvm_fatal("ADC_DRV", "Failed to get virtual adc_if from uvm_config_db!") // Fatal if missing
        end                                   // End of config_db check
    endfunction                               // End of build_phase

    virtual task run_phase(uvm_phase phase);  // UVM run phase
        adc_seq_item req_item;                // Sequence item handle
        forever begin                         // Process incoming voltage update items
            seq_item_port.get_next_item(req_item); // Wait for next item from sequencer
            if (req_item.kind == adc_seq_item::ADC_SET_VOLTS) begin // Check if voltage command
                vif.vin[0]      = req_item.vin[0];      // Drive channel 0 voltage
                vif.vin[1]      = req_item.vin[1];      // Drive channel 1 voltage
                vif.vin[2]      = req_item.vin[2];      // Drive channel 2 voltage
                vif.vin[3]      = req_item.vin[3];      // Drive channel 3 voltage
                vif.offset_v    = req_item.offset_v;    // Drive analog DC offset
                vif.noise_amp_v = req_item.noise_amp_v; // Drive analog noise amplitude
            end                               // End of command check
            seq_item_port.item_done();        // Signal completion to sequencer
        end                                   // End of forever loop
    endtask                                   // End of run_phase

endclass // End of adc_driver class

// -----------------------------------------------------------------------------
// 4. Analog & Peripheral Event Monitor (adc_monitor)
// -----------------------------------------------------------------------------
class adc_monitor extends uvm_monitor;        // Watches analog conversions and timer pulses

    `uvm_component_utils(adc_monitor)         // Register adc_monitor with UVM factory

    virtual adc_if                   vif;     // Virtual interface handle to adc_if
    uvm_analysis_port #(adc_seq_item) ap;     // Analysis port to scoreboard and coverage

    function new(string name, uvm_component parent); // Constructor for adc_monitor
        super.new(name, parent);              // Call base constructor
        ap = new("ap", this);                 // Instantiate analysis port
    endfunction                               // End of constructor

    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);             // Call base build_phase
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif)) begin // Retrieve adc_if
            `uvm_fatal("ADC_MON", "Failed to get virtual adc_if from uvm_config_db!") // Fatal if missing
        end                                   // End of config_db check
    endfunction                               // End of build_phase

    virtual task run_phase(uvm_phase phase);  // UVM run phase watching every clock edge
      real      latched_vhold = 0.0;        // Held voltage captured when adc_sample falls
      bit       eoc_seen;                   // Sampled pre-edge EOC pulse
      bit [7:0] res_seen;                   // Sampled pre-edge 8-bit conversion result
      bit [1:0] ch_seen;                    // Sampled pre-edge 2-bit channel tag
      bit       ovf_seen;                   // Sampled pre-edge timer overflow pulse
      bit       cmp_seen;                   // Sampled pre-edge timer compare pulse
      @(posedge vif.rst_n);                 // Wait for reset release
      forever begin                         // Continuous monitoring loop
          @(posedge vif.clk);               // Sample on rising clock edge
          if (vif.adc_sample) begin         // Track capacitor voltage while switch is closed
              latched_vhold = vif.vhold;    // Keep updating tracked voltage
          end                               // End of sample tracking
          eoc_seen = vif.adc_eoc_mon;       // Capture pre-edge EOC pulse
          res_seen = vif.adc_result_mon;    // Capture pre-edge 8-bit result
          ch_seen  = vif.adc_result_ch_mon; // Capture pre-edge 2-bit channel tag
          ovf_seen = vif.tmr_ovf_mon;       // Capture pre-edge timer overflow pulse
          cmp_seen = vif.tmr_cmp_mon;       // Capture pre-edge timer compare pulse
          #1ps;                             // Wait 1ps so APB read checks pre-NBA FIFO before EOC push
          if (eoc_seen) begin               // EOC pulsed on this clock cycle
              adc_seq_item ev = adc_seq_item::type_id::create("eoc_ev");
              ev.kind           = adc_seq_item::ADC_EOC_EVENT;
              ev.conv_ch        = ch_seen;
              ev.conv_result    = res_seen;
              ev.vhold_at_eoc   = latched_vhold;
              ev.exp_ideal_code = vif.voltage_to_code(latched_vhold);
              ev.vin[0]         = vif.vin[0];
              ev.vin[1]         = vif.vin[1];
              ev.vin[2]         = vif.vin[2];
              ev.vin[3]         = vif.vin[3];
              ev.offset_v       = vif.offset_v;
              ev.noise_amp_v    = vif.noise_amp_v;
              ap.write(ev);
          end
          if (ovf_seen) begin
              adc_seq_item ovf_ev = adc_seq_item::type_id::create("ovf_ev");
              ovf_ev.kind = adc_seq_item::TMR_OVF_EVENT;
              ap.write(ovf_ev);
          end
          if (cmp_seen) begin
              adc_seq_item cmp_ev = adc_seq_item::type_id::create("cmp_ev");
              cmp_ev.kind = adc_seq_item::TMR_CMP_EVENT;
              ap.write(cmp_ev);
          end
      end
  endtask

endclass // End of adc_monitor class

// -----------------------------------------------------------------------------
// 5. Analog Agent (adc_agent)
// -----------------------------------------------------------------------------
class adc_agent extends uvm_agent;            // Bundles adc_sequencer, adc_driver, adc_monitor

    `uvm_component_utils(adc_agent)           // Register adc_agent with UVM factory

    adc_sequencer sqr;                        // Analog sequencer handle
    adc_driver    drv;                        // Analog driver handle
    adc_monitor   mon;                        // Analog monitor handle

    function new(string name, uvm_component parent); // Constructor for adc_agent
        super.new(name, parent);              // Call base constructor
    endfunction                               // End of constructor

    virtual function void build_phase(uvm_phase phase); // UVM build phase
        super.build_phase(phase);             // Call base build_phase
        mon = adc_monitor::type_id::create("mon", this); // Create monitor
        if (get_is_active() == UVM_ACTIVE) begin // Build driver & sequencer when active
            sqr = adc_sequencer::type_id::create("sqr", this); // Create sequencer
            drv = adc_driver::type_id::create("drv", this);    // Create driver
        end                                   // End of active check
    endfunction                               // End of build_phase

    virtual function void connect_phase(uvm_phase phase); // UVM connect phase
        super.connect_phase(phase);           // Call base connect_phase
        if (get_is_active() == UVM_ACTIVE) begin // Connect driver and sequencer
            drv.seq_item_port.connect(sqr.seq_item_export); // Connect ports
        end                                   // End of active connection check
    endfunction                               // End of connect_phase

endclass // End of adc_agent class

`endif // End of ADC_AGENT_SV include guard
`endif // End of INSIDE_TIMER_ADC_PKG package scope guard
