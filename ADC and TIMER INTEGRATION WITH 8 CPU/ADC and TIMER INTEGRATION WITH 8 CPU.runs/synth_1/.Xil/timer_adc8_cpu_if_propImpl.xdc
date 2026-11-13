set_property SRC_FILE_INFO {cfile:{C:/Users/admin/Downloads/Project_Vivado/ADC and TIMER INTEGRATION WITH 8 CPU/ADC and TIMER INTEGRATION WITH 8 CPU.srcs/constrs_1/imports/constraints/timer_adc8_vivado.xdc} rfile:{../../../ADC and TIMER INTEGRATION WITH 8 CPU.srcs/constrs_1/imports/constraints/timer_adc8_vivado.xdc} id:1} [current_design]
set_property src_info {type:XDC file:1 line:7 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk] ;# Map clk to oscillator pin
set_property src_info {type:XDC file:1 line:11 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports rst_n] ;# Center push-button
set_property src_info {type:XDC file:1 line:17 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN T18  IOSTANDARD LVCMOS33 } [get_ports cs]       ;# CPU chip select
set_property src_info {type:XDC file:1 line:18 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN W19  IOSTANDARD LVCMOS33 } [get_ports we]       ;# CPU write enable
set_property src_info {type:XDC file:1 line:19 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports {addr[0]}] ;# Register addr bit 0
set_property src_info {type:XDC file:1 line:20 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports {addr[1]}] ;# Register addr bit 1
set_property src_info {type:XDC file:1 line:21 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports {addr[2]}] ;# Register addr bit 2
set_property src_info {type:XDC file:1 line:22 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN W17  IOSTANDARD LVCMOS33 } [get_ports {addr[3]}] ;# Register addr bit 3
set_property src_info {type:XDC file:1 line:25 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS33 } [get_ports {wdata[0]}] ;# CPU write data bit 0
set_property src_info {type:XDC file:1 line:26 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports {wdata[1]}] ;# CPU write data bit 1
set_property src_info {type:XDC file:1 line:27 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN W14  IOSTANDARD LVCMOS33 } [get_ports {wdata[2]}] ;# CPU write data bit 2
set_property src_info {type:XDC file:1 line:28 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN W13  IOSTANDARD LVCMOS33 } [get_ports {wdata[3]}] ;# CPU write data bit 3
set_property src_info {type:XDC file:1 line:29 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33 } [get_ports {wdata[4]}] ;# CPU write data bit 4
set_property src_info {type:XDC file:1 line:30 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN T3   IOSTANDARD LVCMOS33 } [get_ports {wdata[5]}] ;# CPU write data bit 5
set_property src_info {type:XDC file:1 line:31 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN T2   IOSTANDARD LVCMOS33 } [get_ports {wdata[6]}] ;# CPU write data bit 6
set_property src_info {type:XDC file:1 line:32 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN R3   IOSTANDARD LVCMOS33 } [get_ports {wdata[7]}] ;# CPU write data bit 7
set_property src_info {type:XDC file:1 line:35 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {rdata[0]}] ;# CPU read data bit 0
set_property src_info {type:XDC file:1 line:36 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports {rdata[1]}] ;# CPU read data bit 1
set_property src_info {type:XDC file:1 line:37 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports {rdata[2]}] ;# CPU read data bit 2
set_property src_info {type:XDC file:1 line:38 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN V19  IOSTANDARD LVCMOS33 } [get_ports {rdata[3]}] ;# CPU read data bit 3
set_property src_info {type:XDC file:1 line:39 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN W18  IOSTANDARD LVCMOS33 } [get_ports {rdata[4]}] ;# CPU read data bit 4
set_property src_info {type:XDC file:1 line:40 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN U15  IOSTANDARD LVCMOS33 } [get_ports {rdata[5]}] ;# CPU read data bit 5
set_property src_info {type:XDC file:1 line:41 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports {rdata[6]}] ;# CPU read data bit 6
set_property src_info {type:XDC file:1 line:42 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports {rdata[7]}] ;# CPU read data bit 7
set_property src_info {type:XDC file:1 line:45 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN V13  IOSTANDARD LVCMOS33 } [get_ports irq]      ;# Interrupt doorbell LED
set_property src_info {type:XDC file:1 line:46 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN V3   IOSTANDARD LVCMOS33 } [get_ports pwm_out]  ;# Timer PWM output LED
set_property src_info {type:XDC file:1 line:49 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN J1   IOSTANDARD LVCMOS33 } [get_ports adc_sample]  ;# S&H switch control
set_property src_info {type:XDC file:1 line:50 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN L2   IOSTANDARD LVCMOS33 } [get_ports {adc_ch[0]}]  ;# Analog mux ch[0]
set_property src_info {type:XDC file:1 line:51 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN J2   IOSTANDARD LVCMOS33 } [get_ports {adc_ch[1]}]  ;# Analog mux ch[1]
set_property src_info {type:XDC file:1 line:52 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN G2   IOSTANDARD LVCMOS33 } [get_ports adc_cmp]      ;# Comparator input
set_property src_info {type:XDC file:1 line:53 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN A14  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[0]}] ;# R-2R DAC bit 0
set_property src_info {type:XDC file:1 line:54 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN A16  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[1]}] ;# R-2R DAC bit 1
set_property src_info {type:XDC file:1 line:55 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN B15  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[2]}] ;# R-2R DAC bit 2
set_property src_info {type:XDC file:1 line:56 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN B16  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[3]}] ;# R-2R DAC bit 3
set_property src_info {type:XDC file:1 line:57 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN A15  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[4]}] ;# R-2R DAC bit 4
set_property src_info {type:XDC file:1 line:58 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN A17  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[5]}] ;# R-2R DAC bit 5
set_property src_info {type:XDC file:1 line:59 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN C15  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[6]}] ;# R-2R DAC bit 6
set_property src_info {type:XDC file:1 line:60 export:INPUT save:INPUT read:READ} [current_design]
set_property -dict { PACKAGE_PIN C16  IOSTANDARD LVCMOS33 } [get_ports {adc_dac[7]}] ;# R-2R DAC bit 7
