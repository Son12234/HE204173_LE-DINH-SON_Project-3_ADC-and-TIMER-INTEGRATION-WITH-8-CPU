`ifdef INSIDE_TIMER_ADC_PKG // Compile inside timer_adc_pkg package scope (safe when added to Vivado GUI)
`ifndef TIMER_ADC_RAL_SV // Prevent duplicate inclusion of timer_adc_ral.sv
`define TIMER_ADC_RAL_SV // Mark timer_adc_ral.sv as included

// =============================================================================
// File        : timer_adc_ral.sv
// Project     : 8-bit Timer + 8-bit SAR ADC Peripheral (timer_adc8_uvm)
// Description : UVM Register Abstraction Layer (RAL) Modeling all 16 8-bit
//               Registers (0x0 to 0xF) and the APB Register Adapter
//               (Chapter 8, 12, 13).
// =============================================================================

// -----------------------------------------------------------------------------
// Generic 8-bit Configurable Register Class for Single-Field Byte Registers
// -----------------------------------------------------------------------------
class tadc_byte_reg extends uvm_reg;          // Reusable 8-bit register class
    `uvm_object_utils(tadc_byte_reg)          // Register with UVM factory
    rand uvm_reg_field val;                   // 8-bit register value field

    function new(string name = "tadc_byte_reg"); // Constructor
        super.new(name, 8, UVM_NO_COVERAGE);  // 8-bit register width
    endfunction                               // End of constructor

    virtual function void build(string access_mode = "RW", bit [7:0] rst_val = 8'h00, bit is_vol = 0); // Configure
        val = uvm_reg_field::type_id::create("val"); // Create 8-bit field
        val.configure(this, 8, 0, access_mode, is_vol, rst_val, 1, 1, 1); // Configure bit[7:0]
    endfunction                               // End of build function
endclass // End of tadc_byte_reg class

// -----------------------------------------------------------------------------
// Multi-Field Register Classes (TMR_CTRL, ADC_CTRL, ADC_RCH, ADC_STAT, IRQ)
// -----------------------------------------------------------------------------
class reg_tmr_ctrl extends uvm_reg;           // 0x0 TMR_CTRL: {unused[7:2], ONESHOT[1], EN[0]}
    `uvm_object_utils(reg_tmr_ctrl)           // Register with UVM factory
    rand uvm_reg_field en;                    // Bit 0: Timer enable
    rand uvm_reg_field oneshot;               // Bit 1: One-shot mode enable
    uvm_reg_field      unused;                // Bits 7:2: Read-only 0

    function new(string name = "reg_tmr_ctrl"); // Constructor
        super.new(name, 8, UVM_NO_COVERAGE);  // 8 bits wide
    endfunction                               // End of constructor

    virtual function void build();            // Build fields
        en      = uvm_reg_field::type_id::create("en");      // Create EN field
        oneshot = uvm_reg_field::type_id::create("oneshot"); // Create ONESHOT field
        unused  = uvm_reg_field::type_id::create("unused");  // Create unused field
        en.configure     (this, 1, 0, "RW", 1, 1'b0, 1, 1, 0); // Bit 0 RW (volatile in oneshot)
        oneshot.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0); // Bit 1 RW
        unused.configure (this, 6, 2, "RO", 0, 6'h0, 1, 0, 0); // Bits 7:2 RO = 0
    endfunction                               // End of build
endclass // End of reg_tmr_ctrl

class reg_adc_ctrl extends uvm_reg;           // 0x5 ADC_CTRL: {unused[7:6], CH[5:4], TRIG_SEL[3:2], START[1], EN[0]}
    `uvm_object_utils(reg_adc_ctrl)           // Register with UVM factory
    rand uvm_reg_field en;                    // Bit 0: ADC enable
    rand uvm_reg_field start;                 // Bit 1: Software start trigger (reads back 0)
    rand uvm_reg_field trig_sel;              // Bits 3:2: Trigger source select
    rand uvm_reg_field ch;                    // Bits 5:4: Analog channel select
    uvm_reg_field      unused;                // Bits 7:6: Unused RO = 0

    function new(string name = "reg_adc_ctrl"); // Constructor
        super.new(name, 8, UVM_NO_COVERAGE);  // 8 bits wide
    endfunction                               // End of constructor

    virtual function void build();            // Build fields
        en       = uvm_reg_field::type_id::create("en");       // Create EN field
        start    = uvm_reg_field::type_id::create("start");    // Create START field
        trig_sel = uvm_reg_field::type_id::create("trig_sel"); // Create TRIG_SEL field
        ch       = uvm_reg_field::type_id::create("ch");       // Create CH field
        unused   = uvm_reg_field::type_id::create("unused");   // Create unused field
        en.configure      (this, 1, 0, "RW", 0, 1'b0, 1, 1, 0); // Bit 0 RW
        start.configure   (this, 1, 1, "WO", 1, 1'b0, 1, 1, 0); // Bit 1 self-clearing start pulse
        trig_sel.configure(this, 2, 2, "RW", 0, 2'b0, 1, 1, 0); // Bits 3:2 RW
        ch.configure      (this, 2, 4, "RW", 0, 2'b0, 1, 1, 0); // Bits 5:4 RW
        unused.configure  (this, 2, 6, "RO", 0, 2'b0, 1, 0, 0); // Bits 7:6 RO = 0
    endfunction                               // End of build
endclass // End of reg_adc_ctrl

// -----------------------------------------------------------------------------
// Complete 16-Register Block (timer_adc_reg_block)
// -----------------------------------------------------------------------------
class timer_adc_reg_block extends uvm_reg_block; // Software mirror of all 16 registers

    `uvm_object_utils(timer_adc_reg_block)    // Register block with UVM factory

    rand reg_tmr_ctrl  tmr_ctrl;              // 0x0 RW: TMR_CTRL
    rand tadc_byte_reg tmr_presc;             // 0x1 RW: TMR_PRESC
    rand tadc_byte_reg tmr_load;              // 0x2 RW: TMR_LOAD (reset 0xFF)
    rand tadc_byte_reg tmr_cmp;               // 0x3 RW: TMR_CMP  (reset 0x80)
    tadc_byte_reg      tmr_cnt;               // 0x4 RO: TMR_CNT
    rand reg_adc_ctrl  adc_ctrl;              // 0x5 RW: ADC_CTRL
    rand tadc_byte_reg adc_smp;               // 0x6 RW: ADC_SMP  (reset 0x04)
    rand tadc_byte_reg adc_div;               // 0x7 RW: ADC_DIV  (reset 0x00)
    rand tadc_byte_reg adc_thr_lo;            // 0x8 RW: ADC_THR_LO (reset 0x00)
    rand tadc_byte_reg adc_thr_hi;            // 0x9 RW: ADC_THR_HI (reset 0xFF)
    tadc_byte_reg      adc_data;              // 0xA RO pop: ADC_DATA
    tadc_byte_reg      adc_rch;               // 0xB RO: ADC_RCH
    tadc_byte_reg      adc_stat;              // 0xC RO: ADC_STAT (reset 0x10)
    rand tadc_byte_reg irq_en;                // 0xD RW: IRQ_EN
    rand tadc_byte_reg irq_stat;              // 0xE W1C: IRQ_STAT
    tadc_byte_reg      id;                    // 0xF RO: ID (reset 0xA8)

    function new(string name = "timer_adc_reg_block"); // Constructor
        super.new(name, UVM_NO_COVERAGE);     // Call base constructor
    endfunction                               // End of constructor

    virtual function void build();            // Instantiate, configure, and map all 16 registers
        default_map = create_map("default_map", 'h0, 1, UVM_LITTLE_ENDIAN); // 1-byte stride map

        tmr_ctrl   = reg_tmr_ctrl::type_id::create("tmr_ctrl");   tmr_ctrl.configure(this);   tmr_ctrl.build();                     // 0x0
        tmr_presc  = tadc_byte_reg::type_id::create("tmr_presc"); tmr_presc.configure(this);  tmr_presc.build("RW",  8'h00, 0);     // 0x1
        tmr_load   = tadc_byte_reg::type_id::create("tmr_load");  tmr_load.configure(this);   tmr_load.build("RW",   8'hFF, 0);     // 0x2
        tmr_cmp    = tadc_byte_reg::type_id::create("tmr_cmp");   tmr_cmp.configure(this);    tmr_cmp.build("RW",    8'h80, 0);     // 0x3
        tmr_cnt    = tadc_byte_reg::type_id::create("tmr_cnt");   tmr_cnt.configure(this);    tmr_cnt.build("RO",    8'h00, 1);     // 0x4
        adc_ctrl   = reg_adc_ctrl::type_id::create("adc_ctrl");   adc_ctrl.configure(this);   adc_ctrl.build();                     // 0x5
        adc_smp    = tadc_byte_reg::type_id::create("adc_smp");   adc_smp.configure(this);    adc_smp.build("RW",    8'h04, 0);     // 0x6
        adc_div    = tadc_byte_reg::type_id::create("adc_div");   adc_div.configure(this);    adc_div.build("RW",    8'h00, 0);     // 0x7
        adc_thr_lo = tadc_byte_reg::type_id::create("adc_thr_lo");adc_thr_lo.configure(this); adc_thr_lo.build("RW", 8'h00, 0);     // 0x8
        adc_thr_hi = tadc_byte_reg::type_id::create("adc_thr_hi");adc_thr_hi.configure(this); adc_thr_hi.build("RW", 8'hFF, 0);     // 0x9
        adc_data   = tadc_byte_reg::type_id::create("adc_data");  adc_data.configure(this);   adc_data.build("RO",   8'h00, 1);     // 0xA
        adc_rch    = tadc_byte_reg::type_id::create("adc_rch");   adc_rch.configure(this);    adc_rch.build("RO",    8'h00, 1);     // 0xB
        adc_stat   = tadc_byte_reg::type_id::create("adc_stat");  adc_stat.configure(this);   adc_stat.build("RO",   8'h10, 1);     // 0xC
        irq_en     = tadc_byte_reg::type_id::create("irq_en");    irq_en.configure(this);     irq_en.build("RW",     8'h00, 0);     // 0xD
        irq_stat   = tadc_byte_reg::type_id::create("irq_stat");  irq_stat.configure(this);   irq_stat.build("W1C",  8'h00, 1);     // 0xE
        id         = tadc_byte_reg::type_id::create("id");        id.configure(this);         id.build("RO",         8'hA8, 0);     // 0xF

        default_map.add_reg(tmr_ctrl,   'h0, "RW"); // Map TMR_CTRL   at 0x0
        default_map.add_reg(tmr_presc,  'h1, "RW"); // Map TMR_PRESC  at 0x1
        default_map.add_reg(tmr_load,   'h2, "RW"); // Map TMR_LOAD   at 0x2
        default_map.add_reg(tmr_cmp,    'h3, "RW"); // Map TMR_CMP    at 0x3
        default_map.add_reg(tmr_cnt,    'h4, "RO"); // Map TMR_CNT    at 0x4
        default_map.add_reg(adc_ctrl,   'h5, "RW"); // Map ADC_CTRL   at 0x5
        default_map.add_reg(adc_smp,    'h6, "RW"); // Map ADC_SMP    at 0x6
        default_map.add_reg(adc_div,    'h7, "RW"); // Map ADC_DIV    at 0x7
        default_map.add_reg(adc_thr_lo, 'h8, "RW"); // Map ADC_THR_LO at 0x8
        default_map.add_reg(adc_thr_hi, 'h9, "RW"); // Map ADC_THR_HI at 0x9
        default_map.add_reg(adc_data,   'hA, "RO"); // Map ADC_DATA   at 0xA
        default_map.add_reg(adc_rch,    'hB, "RO"); // Map ADC_RCH    at 0xB
        default_map.add_reg(adc_stat,   'hC, "RO"); // Map ADC_STAT   at 0xC
        default_map.add_reg(irq_en,     'hD, "RW"); // Map IRQ_EN     at 0xD
        default_map.add_reg(irq_stat,   'hE, "RW"); // Map IRQ_STAT   at 0xE
        default_map.add_reg(id,         'hF, "RO"); // Map ID         at 0xF

        lock_model();                         // Finalize and lock the RAL register block
    endfunction                               // End of build function

endclass // End of timer_adc_reg_block class

// -----------------------------------------------------------------------------
// APB Register Adapter (apb_reg_adapter): Converts uvm_reg_bus_op <-> apb_seq_item
// -----------------------------------------------------------------------------
class apb_reg_adapter extends uvm_reg_adapter; // Translates RAL operations to APB items

    `uvm_object_utils(apb_reg_adapter)        // Register adapter with UVM factory

    function new(string name = "apb_reg_adapter"); // Constructor
        super.new(name);                      // Call base constructor
        supports_byte_enable = 0;             // 8-bit bus has single byte lane
        provides_responses   = 0;             // Driver updates req item in-place
    endfunction                               // End of constructor

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw); // Convert RAL -> APB
        apb_seq_item item = apb_seq_item::type_id::create("item"); // Create APB bus item
        item.pwrite = (rw.kind == UVM_WRITE) ? 1'b1 : 1'b0;        // Map UVM_WRITE/UVM_READ
        item.paddr  = rw.addr[3:0];                                // Extract 4-bit register offset
        item.pwdata = rw.data[7:0];                                // Extract 8-bit write data
        return item;                                               // Return constructed bus item
    endfunction                                                    // End of reg2bus

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw); // Convert APB -> RAL
        apb_seq_item item;                    // Typed handle to apb_seq_item
        if (!$cast(item, bus_item)) begin     // Cast generic item to apb_seq_item
            `uvm_fatal("RAL_ADAPTER", "Provided bus_item is not of type apb_seq_item!") // Report error
        end                                   // End of cast check
        rw.kind   = item.pwrite ? UVM_WRITE : UVM_READ;            // Record operation direction
        rw.addr   = {60'h0, item.paddr};                           // Store 4-bit register address
        rw.data   = {56'h0, item.pwrite ? item.pwdata : item.prdata}; // Store 8-bit data byte
        rw.status = UVM_IS_OK;                                     // Always report OK to allow RO test
    endfunction                                                    // End of bus2reg

endclass // End of apb_reg_adapter class

`endif // End of TIMER_ADC_RAL_SV include guard
`endif // End of INSIDE_TIMER_ADC_PKG package scope guard
