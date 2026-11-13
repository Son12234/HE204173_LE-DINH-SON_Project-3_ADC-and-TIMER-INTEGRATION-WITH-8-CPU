# =============================================================================
# File   : risc8_soc.xdc
# Purpose: Clock, I/O timing, pin and configuration constraints for risc8_soc.sv.
#
#          PIN ASSIGNMENTS TARGET THE DIGILENT BASYS 3 BOARD (xc7a35tcpg236-1).
#          Using another board: change only the PACKAGE_PIN values below (and the
#          create_clock period if the oscillator is not 100 MHz).
#
#          Basys 3 usage:  clk = 100 MHz oscillator (W5)     rst = centre button
#          halted = LED0,  pc_out[7:0] = LED1..LED8,  irq = LED9,  pwm_out = LED10
#          adc_sample/adc_ch[1:0]/adc_cmp = Pmod JA,  adc_dac[7:0] = Pmod JB
# =============================================================================

# ---------------------------------------------------------------------------
# Clock: 100 MHz external oscillator, matching tb_top.sv's 10 ns simulation
# clock so timing behavior in simulation and on real silicon line up.
# ---------------------------------------------------------------------------
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]

# ---------------------------------------------------------------------------
# I/O timing (clears "no_input_delay" / "no_output_delay" in Check Timing and
# the TIMING-18 methodology warnings).
#
#   inputs : rst, adc_cmp                      (2 ports)  -> real timing check
#   outputs: halted, pc_out[7:0], irq, pwm_out, adc_sample, adc_ch[1:0],
#            adc_dac[7:0]                      (22 ports)
#
# The 2.0 ns values are PLACEHOLDERS; replace them with the real numbers from
# your board / external parts.
#
# The 22 outputs are debug LEDs (halted, pc_out, irq, pwm_out) and the slow
# analog front-end control (adc_sample/adc_ch/adc_dac, which the SAR logic
# changes at most once per sar_tick and which the off-chip DAC/mux must settle
# on anyway). They have no clock-edge relationship to check, so the output delay
# is kept (it satisfies Check Timing) and the paths are declared false paths.
# Once a real external timing budget exists, delete the set_false_path line and
# tighten the output delay.
# ---------------------------------------------------------------------------
set_input_delay  -clock [get_clocks sys_clk] -max 2.000 [get_ports {rst adc_cmp}]
set_input_delay  -clock [get_clocks sys_clk] -min 0.500 [get_ports {rst adc_cmp}]
set_output_delay -clock [get_clocks sys_clk] -max 2.000 [get_ports {halted irq pwm_out adc_sample pc_out[*] adc_ch[*] adc_dac[*]}]
set_output_delay -clock [get_clocks sys_clk] -min 0.000 [get_ports {halted irq pwm_out adc_sample pc_out[*] adc_ch[*] adc_dac[*]}]
set_false_path -to [get_ports {halted irq pwm_out adc_sample pc_out[*] adc_ch[*] adc_dac[*]}]

# ---------------------------------------------------------------------------
# Reset is synchronous inside the CPU core and only inverted (not
# re-synchronized) on the way into the peripheral (risc8_soc.sv: rst_n =
# ~rst). On real silicon, release an external reset through a proper
# synchronizer before it reaches this pin (the integration guide's chapter 5
# says the same). Here rst is the Basys 3 centre button: pressed = 1 = reset.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Pin locations + I/O standard (Basys 3, all banks at 3.3 V -> LVCMOS33)
# This clears DRC NSTD-1 (default I/O standard) and UCIO-1 (no pin location).
# ---------------------------------------------------------------------------
# clock and reset
set_property -dict {PACKAGE_PIN W5  IOSTANDARD LVCMOS33} [get_ports clk]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports rst]

# debug outputs: halted -> LED0, pc_out[7:0] -> LED1..LED8
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports halted]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {pc_out[0]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {pc_out[1]}]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports {pc_out[2]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {pc_out[3]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {pc_out[4]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {pc_out[5]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {pc_out[6]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {pc_out[7]}]

# peripheral status: irq -> LED9, pwm_out -> LED10
set_property -dict {PACKAGE_PIN V3  IOSTANDARD LVCMOS33} [get_ports irq]
set_property -dict {PACKAGE_PIN W3  IOSTANDARD LVCMOS33} [get_ports pwm_out]

# SAR-ADC analog front-end, control side: Pmod JA
# (adc_sample, adc_ch[1:0] out to an external mux/DAC; adc_cmp in from the comparator)
set_property -dict {PACKAGE_PIN J1  IOSTANDARD LVCMOS33} [get_ports adc_sample]
set_property -dict {PACKAGE_PIN L2  IOSTANDARD LVCMOS33} [get_ports {adc_ch[0]}]
set_property -dict {PACKAGE_PIN J2  IOSTANDARD LVCMOS33} [get_ports {adc_ch[1]}]
set_property -dict {PACKAGE_PIN G2  IOSTANDARD LVCMOS33} [get_ports adc_cmp]

# SAR-ADC analog front-end, DAC code (adc_dac[7:0]): Pmod JB
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports {adc_dac[0]}]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports {adc_dac[1]}]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports {adc_dac[2]}]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports {adc_dac[3]}]
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports {adc_dac[4]}]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {adc_dac[5]}]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports {adc_dac[6]}]
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports {adc_dac[7]}]

# ---------------------------------------------------------------------------
# Configuration bank voltage (clears DRC CFGBVS-1). Basys 3: bank 0 at 3.3 V.
# ---------------------------------------------------------------------------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
