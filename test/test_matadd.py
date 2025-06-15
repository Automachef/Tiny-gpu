import cocotb
import random
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

def generate_program(size, base_a=0, base_b=8, base_c=16):
    
    return [
        0b0101000011011110,                          # MUL R0, %blockIdx, %blockDim
        0b0011000000001111,                          # ADD R0, R0, %threadIdx
        (0b1001000100000000 | ((base_a & 0xFF))),    # CONST R1, #baseA
        (0b1001001000000000 | ((base_b & 0xFF))),    # CONST R2, #baseB
        (0b1001001100000000 | ((base_c & 0xFF))),    # CONST R3, #baseC
        0b0011010000010000,                          # ADD R4, R1, R0
        0b0111010001000000,                          # LDR R4, R4
        0b0011010100100000,                          # ADD R5, R2, R0
        0b0111010101010000,                          # LDR R5, R5
        0b0011011001000101,                          # ADD R6, R4, R5
        0b0011011100110000,                          # ADD R7, R3, R0
        0b1000000001110110,                          # STR R7, R6
        0b1111000000000000,                          # RET
    ]

def display_matrix(matrix, rows, cols, name="Matrix"):
    print(f"\n{name}:")
    for r in range(rows):
        row_data = matrix[r * cols : (r + 1) * cols]
        print("  " + " ".join(f"{v:3}" for v in row_data))

def generate_data(rows, cols):
    A = [random.randint(0, 9) for _ in range(rows * cols)]
    B = [random.randint(0, 9) for _ in range(rows * cols)]
    return A + B, rows * cols

@cocotb.test()
async def test_matadd(dut):
    
    rows = 4
    cols = 4

    base_a = 0
    base_b = rows * cols
    base_c = base_b + rows * cols

    program = generate_program(size=rows * cols, base_a=base_a, base_b=base_b, base_c=base_c)
    data, threads = generate_data(rows, cols)

    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    data_memory.display(base_c + threads)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()
        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)
        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(base_c + threads)

    expected_results = [a + b for a, b in zip(data[0:threads], data[threads:threads * 2])]
    actual_results = [data_memory.memory[i + base_c] for i in range(threads)]

    display_matrix(expected_results, rows, cols, name="Expected C = A + B")
    display_matrix(actual_results, rows, cols, name="Actual   C")

    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i + base_c]
        assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"
