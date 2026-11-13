// =============================================================================
// File   : afe_model.sv
// Purpose: Testbench-only behavioral stand-in for the external analog front
//          end (mux + sample/hold + comparator) that a real board would
//          need around sar_adc_ctrl.sv's adc_sample/adc_ch/adc_dac/adc_cmp
//          pins. Four fixed channel voltages are used, chosen to match
//          every worked numeric example in the integration guide (so the
//          expected FIFO codes in the firmware's self-check table line up
//          with a familiar reference), using an 8-bit, VREF=3.3V linear
//          transfer function: code = round(Vin / VREF * 255).
//            ch0 = 0.40 V -> 0x1F (31)
//            ch1 = 1.111V -> 0x56 (86)
//            ch2 = 2.00 V -> 0x9B (155)
//            ch3 = 3.00 V -> 0xE8 (232)
//          This file is simulation-only: it is never part of the
//          synthesizable rtl/ sources.
// =============================================================================
module afe_model (
  input  logic       clk,
  input  logic       adc_sample,   // 1 while the SAR controller wants to track/hold
  input  logic [1:0] adc_ch,
  input  logic [7:0] adc_dac,      // the SAR controller's current trial code
  output logic       adc_cmp       // 1 = adc_dac is higher than the held sample
);

  // Fixed 8-bit codes for the four channels (see header comment for the
  // Vin -> code derivation).
  logic [7:0] channel_code [0:3];
  initial begin
    channel_code[0] = 8'h1F;   // 0.40 V
    channel_code[1] = 8'h56;   // 1.111 V
    channel_code[2] = 8'h9B;   // 2.00 V
    channel_code[3] = 8'hE8;   // 3.00 V
  end

  // Sample-and-hold: keeps tracking the selected channel's code while
  // adc_sample is asserted, and simply stops updating (holds) the instant
  // it deasserts -- exactly what a real track/hold amplifier does.
  logic [7:0] held_code;
  always_ff @(posedge clk) begin
    if (adc_sample)
      held_code <= channel_code[adc_ch];
  end

  // Comparator: purely combinational in this behavioral model (a real
  // comparator has propagation delay, but the SAR controller already
  // waits a full divided SAR-clock period between trials, which stands in
  // for that settling time).
  assign adc_cmp = (adc_dac > held_code);

endmodule : afe_model
