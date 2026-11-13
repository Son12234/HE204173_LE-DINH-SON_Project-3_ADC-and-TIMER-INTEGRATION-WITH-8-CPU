# 1. Device Configuration Voltage Constraints (Eliminates DRC CFGBVS-1 Warning)
set_property CFGBVS VCCO [current_design]         ;# Select Bank 0 VCCO reference for config pins
set_property CONFIG_VOLTAGE 3.3 [current_design]  ;# Specify 3.3V supply voltage on Bank 0
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design] ;# Enable bitstream compression

# 2. Primary System Clock Definition (25 MHz / 40.000 ns Period; Spec = 10 MHz)
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk] ;# Map clk to oscillator pin
create_clock -add -name sys_clk_pin -period 40.000 -waveform {0.000 20.000} [get_ports clk] ;# 40ns clk

# 3. Asynchronous Active-Low Reset Pin (rst_n) with Input Delay + False Path
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports rst_n] ;# Center push-button
set_input_delay -clock [get_clocks sys_clk_pin] -min 0.500 [get_ports rst_n]  ;# Define min input delay for check_timing
set_input_delay -clock [get_clocks sys_clk_pin] -max 2.000 [get_ports rst_n]  ;# Define max input delay for check_timing
set_false_path -from [get_ports rst_n]            ;# Do not time asynchronous reset assertion edge

# 4. 8-bit CPU Bus Control & Address Signals (cs, we, addr[3:0])
set_property -dict { PACKAGE_PIN T18  IOSTANDARD LVCMOS33 } [get_ports cs]       ;# CPU chip select
set_property -dict { PACKAGE_PIN W19  IOSTANDARD LVCMOS33 } [get_ports we]       ;# CPU write enable
set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports {addr[0]}] ;# Register addr bit 0
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports {addr[1]}] ;# Register addr bit 1
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports {addr[2]}] ;# Register addr bit 2
set_property -dict { PACKAGE_PIN W17  IOSTANDARD LVCMOS33 } [get_ports {addr[3]}] ;# Register addr bit 3

# 5. 8-bit CPU Write Data Bus (wdata[7:0])
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS33 } [get_ports {wdata[0]}] ;# CPU write data bit 0
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports {wdata[1]}] ;# CPU write data bit 1
set_property -dict { PACKAGE_PIN W14  IOSTANDARD LVCMOS33 } [get_ports {wdata[2]}] ;# CPU write data bit 2
set_property -dict { PACKAGE_PIN W13  IOSTANDARD LVCMOS33 } [get_ports {wdata[3]}] ;# CPU write data bit 3
set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33 } [get_ports {wdata[4]}] ;# CPU write data bit 4
set_property -dict { PACKAGE_PIN T3   IOSTANDARD LVCMOS33 } [get_ports {wdata[5]}] ;# CPU write data bit 5
set_property -dict { PACKAGE_PIN T2   IOSTANDARD LVCMOS33 } [get_ports {wdata[6]}] ;# CPU write data bit 6
set_property -dict { PACKAGE_PIN R3   IOSTANDARD LVCMOS33 } [get_ports {wdata[7]}] ;# CPU write data bit 7

# 6. 8-bit CPU Read Data Bus (rdata[7:0])
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {rdata[0]}] ;# CPU read data bit 0
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports {rdata[1]}] ;# CPU read data bit 1
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports {rdata[2]}] ;# CPU read data bit 2
set_property -dict { PACKAGE_PIN V19  IOSTANDARD LVCMOS33 } [get_ports {rdata[3]}] ;# CPU read data bit 3
set_property -dict { PACKAGE_PIN W18  IOSTANDARD LVCMOS33 } [get_ports {rdata[4]}] ;# CPU read data bit 4
set_property -dict { PACKAGE_PIN U15  IOSTANDARD LVCMOS33 } [get_ports {rdata[5]}] ;# CPU read data bit 5
set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports {rdata[6]}] ;# CPU read data bit 6
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports {rdata[7]}] ;# CPU read data bit 7

# 7. CPU Interrupt Output (irq) & Timer PWM Output (pwm_out)
set_property -dict { PACKAGE_PIN V13  IOSTANDARD LVCMOS33 } [get_ports irq]      ;# Interrupt doorbell LED
set_property -dict { PACKAGE_PIN V3   IOSTANDARD LVCMOS33 } [get_ports pwm_out]  ;# Timer PWM output LED

# 8. Analog Front-End (AFE) Digital Control & Comparator Interface Pins
set_property -dict { PACKAGE_PIN J1   IOSTANDARD LVCMOS33 } [get_ports adc_sample]  ;# S&H switch control
set_property -dict { PACKAGE_PIN L2   IOSTANDARD LVCMOS33 } [get_ports {adc_ch[0]}]  ;# Analog mux ch[0]
set_property -dict { PACKAGE_PIN J2   IOSTANDARD LVCMOS33 } [get_ports {adc_ch[1]}]  ;# Analog mux ch[1]
set_property -dict { PACKAGE_PIN G2   IOSTANDARD LVCMOS33 } [get_ports adc_cmp]      ;# Comparator input
set_property -dict { PACKAGE_PIN A14  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[0]}] ;# R-2R DAC bit 0
set_property -dict { PACKAGE_PIN A16  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[1]}] ;# R-2R DAC bit 1
set_property -dict { PACKAGE_PIN B15  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[2]}] ;# R-2R DAC bit 2
set_property -dict { PACKAGE_PIN B16  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[3]}] ;# R-2R DAC bit 3
set_property -dict { PACKAGE_PIN A15  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[4]}] ;# R-2R DAC bit 4
set_property -dict { PACKAGE_PIN A17  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[5]}] ;# R-2R DAC bit 5
set_property -dict { PACKAGE_PIN C15  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[6]}] ;# R-2R DAC bit 6
set_property -dict { PACKAGE_PIN C16  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[7]}] ;# R-2R DAC bit 7

# 9. Synchronous Input / Output Timing Budget Constraints
set_input_delay  -clock [get_clocks sys_clk_pin] -min 1.500 [get_ports {cs we addr[*] wdata[*] adc_cmp}] ;# Min input delay
set_input_delay  -clock [get_clocks sys_clk_pin] -max 3.000 [get_ports {cs we addr[*] wdata[*] adc_cmp}] ;# Max input delay
set_output_delay -clock [get_clocks sys_clk_pin] -min 0.000 [get_ports {rdata[*] irq pwm_out adc_sample adc_ch[*] adc_dac[*]}] ;# Min output delay
set_output_delay -clock [get_clocks sys_clk_pin] -max 2.000 [get_ports {rdata[*] irq pwm_out adc_sample adc_ch[*] adc_dac[*]}] ;# Max output delay