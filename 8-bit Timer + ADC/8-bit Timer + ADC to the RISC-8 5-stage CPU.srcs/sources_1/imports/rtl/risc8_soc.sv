// =============================================================================
// File   : risc8_soc.sv
// Purpose: System top module. Places the CPU core and the timer/ADC
//          peripheral side by side and connects them: five bus wires, a
//          shared clock, and a reset-polarity inversion (guide chapter 5).
// =============================================================================
module risc8_soc #(
  parameter string IMEM_FILE = "soc_demo.hex"
) (
  input  logic       clk,
  input  logic       rst,           // synchronous, active-high (CPU-side convention)

  // ---- debug pins ----
  output logic       halted,
  output logic [7:0] pc_out,

  // ---- peripheral pins, brought out to the top level ----
  output logic       irq,
  output logic       pwm_out,
  output logic       adc_sample,
  output logic [1:0] adc_ch,
  output logic [7:0] adc_dac,
  input  logic       adc_cmp
);

  // ---- five bus wires between the CPU core and the peripheral ----
  logic        io_cs;
  logic        io_we;
  logic [3:0]  io_addr;
  logic [7:0]  io_wdata;
  logic [7:0]  io_rdata;

  risc8_5stage_core #(
    .IMEM_FILE (IMEM_FILE),
    .IO_ENABLE (1),             // this is the SoC configuration: the I/O page is live
    .IO_PAGE   (4'hF)
  ) u_cpu (
    .clk        (clk),
    .rst        (rst),
    .halted     (halted),
    .pc_out     (pc_out),
    .flags_out  (),              // not brought out at system level
    .instr_done (),              // not brought out at system level
    .io_cs      (io_cs),
    .io_we      (io_we),
    .io_addr    (io_addr),
    .io_wdata   (io_wdata),
    .io_rdata   (io_rdata)
  );

  timer_adc8_cpu_if u_tadc (
    .clk        (clk),
    .rst_n      (~rst),          // polarity conversion: CPU is active-high, peripheral is active-low
    .cs         (io_cs),
    .we         (io_we),
    .addr       (io_addr),
    .wdata      (io_wdata),
    .rdata      (io_rdata),
    .irq        (irq),
    .adc_sample (adc_sample),
    .adc_ch     (adc_ch),
    .adc_dac    (adc_dac),
    .adc_cmp    (adc_cmp),
    .pwm_out    (pwm_out)
  );

endmodule : risc8_soc
