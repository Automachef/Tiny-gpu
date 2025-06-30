import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

def generate_matmul_program(rows, cols, n, baseA=0, baseB=4, baseC=8):
    program = [
        # i = blockIdx * blockDim + threadIdx
        0b0101000011011110,  # MUL R0, %blockIdx, %blockDim
        0b0011000000001111,  # ADD R0, R0, %threadIdx

        # CONSTs
        0b1001000100000001,                   # CONST R1 = 1
        (0b1001001000000000 | (n & 0xFF)),    # CONST R2 = n
        (0b1001001100000000 | (rows & 0xFF)), # CONST R3 = rows
        (0b1001010000000000 | (cols & 0xFF)), # CONST R4 = cols
        (0b1001010100000000 | (baseA & 0xFF)),# CONST R5 = baseA
        (0b1001011000000000 | (baseB & 0xFF)),# CONST R6 = baseB
        (0b1001011100000000 | (baseC & 0xFF)),# CONST R7 = baseC

        0b1001100000000000,  # CONST R8 = acc = 0
        0b1001100100000000,  # CONST R9 = k = 0

        # LOOP:
        # row = i / cols → R10
        0b0110101000000100,  # DIV R10, R0, R4
        # tmp = row * cols
        0b0101101110100100,  # MUL R11, R10, R4
        # col = i - tmp → R11
        0b0100101100001011,  # SUB R11, R0, R11

        # A_addr = row * n + k + baseA
        0b0101101010100010,  # MUL R10, R10, R2
        0b0011101010101001,  # ADD R10, R10, R9
        0b0011101010100101,  # ADD R10, R10, R5
        0b0111101010100000,  # LDR R10, R10     

        # B_addr = k * cols + col + baseB
        0b0101110010010100,  # MUL R12, R9, R4   
        0b0011101111001011,  # ADD R11, R12, R11
        0b0011101110110110,  # ADD R11, R11, R6
        0b0111101110110000,  # LDR R11, R11

        # acc += A * B
        0b0101110010101011,  # MUL R12, R10, R11
        0b0011100010001100,  # ADD R8, R8, R12

        # k++
        0b0011100110010001,  # ADD R9, R9, R1
        0b0010000010010010,  # CMP R9, R2
        0b0001100000001011,  # BRn LOOP

        # addr = baseC + i
        0b0011101001110000,  # ADD R10, R7, R0
        0b1000000010101000,  # STR R10, R8

        # return
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

def print_matrix(mat, rows, cols, name, indent=2):
    """统一打印矩阵函数"""
    indent_str = ' ' * indent
    print(f"{name}:")
    for i in range(rows):
        row_data = mat[i * cols:(i + 1) * cols]
        print(f"{indent_str}", end="")
        for j, value in enumerate(row_data):
            print(f"{value:>4}", end="")
        print()  # 换行

@cocotb.test()
async def test_matmul(dut):
    rows, cols, n = 3, 3, 3 
    baseA = 0
    baseB = rows * n
    baseC = baseB + n * cols
    total_size = rows * n + n * cols

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

    print_matrix(data[0:rows*n], rows, n, "Matrix A")
    print_matrix(data[rows*n:total_size], n, cols, "Matrix B")
    
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