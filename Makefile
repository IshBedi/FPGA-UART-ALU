# Ish Bedi - UART ALU on DE10-Lite
# Simulation with Icarus Verilog; waveforms open in GTKWave.

IVERILOG ?= iverilog
VVP      ?= vvp
FLAGS    := -g2012 -Wall -Wno-timescale

RTL := rtl/baud_gen.v rtl/uart_tx.v rtl/uart_rx.v rtl/alu8.v rtl/uart_alu.v

.PHONY: all test alu uart system waves lint clean

all: test

test: alu uart system

build:
	mkdir -p build

alu: build
	$(IVERILOG) $(FLAGS) -o build/tb_alu8.vvp $(RTL) tb/tb_alu8.v
	$(VVP) -n build/tb_alu8.vvp

uart: build
	$(IVERILOG) $(FLAGS) -o build/tb_uart.vvp $(RTL) tb/tb_uart.v
	$(VVP) -n build/tb_uart.vvp

system: build
	$(IVERILOG) $(FLAGS) -o build/tb_uart_alu.vvp $(RTL) tb/tb_uart_alu.v
	$(VVP) -n build/tb_uart_alu.vvp

# Re-draw the PNGs in docs/ from the VCD files (needs Python 3 + matplotlib)
waves: uart system
	python3 scripts/plot_waves.py

lint:
	$(IVERILOG) $(FLAGS) -o /dev/null $(RTL) rtl/hex7seg.v rtl/de10_lite_top.v

clean:
	rm -rf build
