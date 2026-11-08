# uart_alu.sdc - Ish Bedi
# 50 MHz board oscillator. UART pins, keys, LEDs and HEX displays are slow/asynchronous.

create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_clock_uncertainty

set_false_path -from [get_ports {KEY[*] ARDUINO_IO[*]}]
set_false_path -to   [get_ports {LEDR[*] HEX0[*] HEX1[*] ARDUINO_IO[*]}]
