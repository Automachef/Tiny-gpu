import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

def generate_matmul_program(rows, cols, n, baseA=0, baseB=4, baseC=8):
    """
    修复3x3方阵问题的矩阵乘法指令生成函数
    关键修复：
      1. B矩阵地址计算使用cols而非n（R6存储cols）[6,7](@ref)
      2. 动态计算分支偏移量，避免硬编码跳转
      3. 寄存器分配优化（累加器用R9，k计数器用R10）
    """
    program = [
        # ---- 初始化阶段 ----
        0b0101000011011110,  # MUL R0, %blockIdx, %blockDim   ; 全局线程ID
        0b0011000000001111,  # ADD R0, R0, %threadIdx         ; 当前线程ID存入R0
        0b1001000100000001,  # CONST R1, #1                   ; 步长=1
        0b1001001000000000 | (n & 0xFF),      # CONST R2, #n   ; A列数/B行数
        0b1001001100000000 | (baseA & 0xFF),  # CONST R3, #baseA
        0b1001010000000000 | (baseB & 0xFF),  # CONST R4, #baseB
        0b1001010100000000 | (baseC & 0xFF),  # CONST R5, #baseC
        0b1001011000000000 | (cols & 0xFF),   # CONST R6, #cols ; B列数[关键修复1]

        # ---- 计算行/列索引 ----
        0b0110011100000010,  # DIV R7, R0, R2       ; row = i // n
        0b0101100011100010,  # MUL R8, R7, R2        ; tmp = row * n
        0b0100011110001000,  # SUB R7, R0, R8        ; col = i - tmp

        # ---- 初始化累加器和循环计数器 ----
        0b1001100100000000,  # CONST R9, #0          ; acc = 0
        0b1001101000000000,  # CONST R10, #0         ; k = 0

        # ---- LOOP 开始 (指令位置12) ----
        # 计算A[row][k]地址
        0b0101101111100010,  # MUL R11, R7, R2       ; row * n
        0b0011101111111010,  # ADD R11, R11, R10     ; + k
        0b0011101111110011,  # ADD R11, R11, R3      ; + baseA
        0b0111101111110000,  # LDR R11, R11           ; A[row][k]

        # 计算B[k][col]地址 [关键修复：使用R6=cols]
        0b0101110000100110,  # MUL R12, R10, R6      ; k * cols
        0b0011110000110111,  # ADD R12, R12, R7      ; + col
        0b0011110000110100,  # ADD R12, R12, R4      ; + baseB
        0b0111110000110000,  # LDR R12, R12           ; B[k][col]

        # 乘积累加
        0b0101110110111100,  # MUL R13, R11, R12     ; A * B
        0b0011100110011101,  # ADD R9, R9, R13       ; acc +=

        # 循环计数器更新
        0b0011101010100001,  # ADD R10, R10, R1      ; k++
        0b0010000010100010,  # CMP R10, R2           ; k < n?
    ]

    # ---- 动态计算分支偏移量 [关键修复2] ----
    loop_start_index = 12
    branch_index = len(program)
    offset = loop_start_index - (branch_index + 1)
    if offset < 0:
        offset = (1 << 10) + offset  # 负偏移补码转换
    offset &= 0x3FF
    branch_inst = 0b0001100000000000 | offset
    program.append(branch_inst)

    # ---- 存储结果 ----
    program += [
        0b0101101011110010,  # MUL R11, R7, R2        ; row * n
        0b0011101011110111,  # ADD R11, R11, R7       ; + col
        0b0011101011110101,  # ADD R11, R11, R5       ; + baseC
        0b1000000010111001,  # STR R11, R9            ; 存储结果
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
    rows, cols, n = 3, 3, 3     # 矩阵大小
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
        result = data_memory.memory[i + baseC]  # 使用 baseC 确保正确偏移
        assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"

    print_matrix(expected_results, rows, cols, "Expected (Theoretical) C")
    sim_results = [data_memory.memory[i + baseC] for i in range(rows * cols)]
    print_matrix(sim_results, rows, cols, "Simulated C")
