# Include src files
+incdir+src
../../src/alu.sv
../../src/controller.sv
../../src/core.sv
../../src/dcr.sv
../../src/decoder.sv
../../src/dispatch.sv
../../src/fetcher.sv
../../src/icache.sv
../../src/gpu.sv
../../src/lsu.sv
../../src/pc.sv
../../src/registers.sv
../../src/scheduler.sv

# Include sim files
+incdir+sim
# ../../sim/testbench.sv
../../sim/test_add.sv
../../sim/test_mul.sv
# ../../sim/test_matadd.sv
# ../../sim/test_matmul.sv