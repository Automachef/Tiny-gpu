.PHONY: test compile sim verdi clean show_sim compile_% test_%

init_dirs:
	@mkdir -p build/cocotb build/simvcs

test_%: init_dirs
	make compile
	iverilog -o build/cocotb/sim.vvp -s gpu -g2012 build/cocotb/gpu.v
	MODULE=test.test_$* vvp -M $(shell cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/cocotb/sim.vvp

compile: init_dirs
	make compile_alu
	sv2v -I src/* -w build/cocotb/gpu.v
	echo "" >> build/cocotb/gpu.v
	cat build/cocotb/alu.v >> build/cocotb/gpu.v
	echo '`timescale 1ns/1ns' > build/cocotb/temp.v
	cat build/cocotb/gpu.v >> build/cocotb/temp.v
	mv build/cocotb/temp.v build/cocotb/gpu.v

compile_%: init_dirs
	sv2v -w build/cocotb/$*.v src/$*.sv

sim: init_dirs
	cd build/simvcs && vcs -full64 -sverilog -f ../../filelist.f -debug_all -l sim.log -o simv \
	    -kdb +define+FSDB +access+r \
	    -P $(VERDI_HOME)/share/PLI/VCS/linux64/novas.tab \
	       $(VERDI_HOME)/share/PLI/VCS/linux64/pli.a

verdi: init_dirs
	cd build/simvcs && ./simv
	cd build/simvcs && verdi -sv -f ../../filelist.f -ssf simv.fsdb

show_sim: build/cocotb/sim.vcd
	gtkwave build/cocotb/sim.vcd

clean:
	rm -rf test/logs/* build/cocotb/* build/simvcs/*