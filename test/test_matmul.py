import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

def generate_matmul_program(rows, cols, n, baseA=0, baseB=4, baseC=8):

    program = [
        0b0101000011011110,  # MUL R0, %blockIdx, %blockDim
        0b0011000000001111,  # ADD R0, R0, %threadIdx
        0b1001000100000001,  # CONST R1, #1
        (0b1001001000000000 | (n & 0xFF)),       # CONST R2, #n
        (0b1001001100000000 | (baseA & 0xFF)),   # CONST R3, #baseA
        (0b1001010000000000 | (baseB & 0xFF)),   # CONST R4, #baseB
        (0b1001010100000000 | (baseC & 0xFF)),   # CONST R5, #baseC

        0b0110011000000010,  # DIV R6, R0, R2      ; row = i / n
        0b0101011101100010,  # MUL R7, R6, R2      ; tmp = row * n
        0b0100011100000111,  # SUB R7, R0, R7      ; col = i - tmp

        0b1001100000000000,  # CONST R8, #0        ; acc = 0
        0b1001100100000000,  # CONST R9, #0        ; k = 0

        # LOOP:
        0b0101101001100010,  #   MUL R10, R6, R2      ; row * n
        0b0011101010101001,  #   ADD R10, R10, R9     ; + k
        0b0011101010100011,  #   ADD R10, R10, R3     ; + baseA
        0b0111101010100000,  #   LDR R10, R10         ; A[i]

        0b0101101110010010,  #   MUL R11, R9, R2      ; k * n（复用R2）
        0b0011101110110111,  #   ADD R11, R11, R7     ; + col
        0b0011101110110100,  #   ADD R11, R11, R4     ; + baseB
        0b0111101110110000,  #   LDR R11, R11         ; B[i]

        0b0101110010101011,  #   MUL R12, R10, R11    ; A[i] * B[i]
        0b0011100010001100,  #   ADD R8, R8, R12      ; acc +=

        0b0011100110010001,  #   ADD R9, R9, R1       ; k++
        0b0010000010010010,  #   CMP R9, R2
        0b0001100000001100,  #   BRn LOOP

        0b0011100101010000,  # ADD R9, R5, R0         ; addr = baseC + i
        0b1000000010011000,  # STR R9, R8             ; store result

        0b1111000000000000   # RET
    ]
    return program

def generate_data(rows, cols, n):
    import random
    A = [random.randint(0, 9) for _ in range(rows * n)]
    B = [random.randint(0, 9) for _ in range(n * cols)]
    return A + B, rows * cols

def calc_expected_results(data, rows, cols, n):
    A = [data[i * n:(i + 1) * n] for i in range(rows)]
    B = [data[rows * n + i * cols:rows * n + (i + 1) * cols] for i in range(n)]
    C = []
    for i in range(rows):
        for j in range(cols):
            val = 0
            for k in range(n):
                val += A[i][k] * B[k][j]
            C.append(val)
    return C

def print_matrix(mat, rows, cols, name):
    print(f"{name}:")
    for i in range(rows):
        print(" ", mat[i*cols:(i+1)*cols])

@cocotb.test()
async def test_matmul(dut):
    rows, cols, n = 4, 4, 4 
    baseA = 0
    baseB = rows * n
    baseC = baseB + n * cols

    program = generate_matmul_program(rows, cols, n, baseA=baseA, baseB=baseB, baseC=baseC)
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    
    data, threads = generate_data(rows, cols, n)
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    data_memory.display(12)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles, thread_id=1)
        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(12)

    expected_results = calc_expected_results(data, rows, cols, n)
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i + baseC]
        assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"

    print_matrix(expected_results, rows, cols, "Expected (Theoretical) C")
    sim_results = [data_memory.memory[i + baseC] for i in range(rows * cols)]
    print_matrix(sim_results, rows, cols, "Simulated C")
