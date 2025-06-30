module test_matmul();

framework testcase();

reg [15:0] init_program_mem [] = '{
    'b0101_0000_1101_1110, // MUL R0, %blockIdx, %blockDim
    'b0011_0000_0000_1111, // ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx
    'b1001_0001_0000_0001, // CONST R1, #1                   ; increment
    'b1001_0010_0000_0000, // CONST R2, #0
    'b0111_0010_0010_0000, // LDR R2, R2                     ; M
    'b1001_0011_0000_0001, // CONST R3, #1
    'b0111_0011_0011_0000, // LDR R3, R3                     ; N
    'b1001_0100_0000_0010, // CONST R4, #2
    'b0111_0100_0100_0000, // LDR R4, R4                     ; K
    'b1001_0101_0000_0011, // CONST R5, #3                   ; A (matrix A base address, M * N)
    'b0101_0110_0010_0011, // MUL R6, R2, R3
    'b0011_0110_0101_0110, // ADD R6, R5, R6                 ; B (matrix B base address, N * K)
    'b0101_0111_0011_0100, // MUL R7, R3, R4
    'b0011_0111_0110_0111, // ADD R7, R6, R7                 ; C (matrix C base address, M * K)
    'b0110_1000_0000_0100, // DIV R8, R0, R4                 ; row = i // K
    'b0101_1001_1000_0100, // MUL R9, R8, R4
    'b0100_1001_0000_1001, // SUB R9, R0, R9                 ; col = i % K
    'b0101_1000_0011_1000, // MUL R8, R3, R8
    'b0011_0101_0101_1000, // ADD R5, R5, R8                 ; rowA = A + row * N (override row, A)
    'b0011_0110_0110_1001, // ADD R6, R6, R9                 ; colB = B + col (override B)
    'b1001_1000_0000_0000, // CONST R8, #0                   ; acc = 0
    'b1001_1001_0000_0000, // CONST R9, #0                   ; k = 0 (override col)
                           // LOOP:
    'b0011_1010_0101_1001, //   ADD R10, R5, R9
    'b0111_1010_1010_0000, //   LDR R10, R10                 ; a = *(rowA + k)
    'b0101_1011_1001_0100, //   MUL R11, R9, R4
    'b0011_1011_0110_1011, //   ADD R11, R6, R11
    'b0111_1011_1011_0000, //   LDR R11, R11                 ; b = *(colB + k * K)
    'b0101_1100_1010_1011, //   MUL R12, R10, R11
    'b0011_1000_1000_1100, //   ADD R8, R8, R12              ; acc = acc + a * b
    'b0011_1001_1001_0001, //   ADD R9, R9, R1               ; increment k
    'b0010_0000_1001_0011, //   CMP R9, R3
    'b0001_1000_0001_0110, //   BRn LOOP                     ; loop while k < N
    'b0011_1001_0111_0000, // ADD R9, R7, R0
    'b1000_0000_1001_1000, // STR R9, R8                     ; store C[i] = acc in global memory
    'b1111_0000_0000_0000  // RET                            ; end of kernel
};

reg [7:0] init_data_mem [] = '{
    // M, N, K
    'd3,
    'd4,
    'd5,

    // Matrix A (M * N)
    'd0, 'd1, 'd2, 'd3,
    'd4, 'd5, 'd6, 'd7,
    'd8, 'd7, 'd6, 'd5,

    // Matrix B (N * K)
    'd0, 'd1, 'd2, 'd3, 'd4,
    'd5, 'd6, 'd7, 'd8, 'd9,
    'd0, 'd1, 'd2, 'd3, 'd4,
    'd5, 'd6, 'd7, 'd8, 'd9
};

reg [7:0] golden_data_mem [] = '{
    // M, N, K
    'd3, 'd4, 'd5,

    // Matrix A (M * N)
    'd0, 'd1, 'd2, 'd3,
    'd4, 'd5, 'd6, 'd7,
    'd8, 'd7, 'd6, 'd5,

    // Matrix B (N * K)
    'd0, 'd1, 'd2, 'd3, 'd4,
    'd5, 'd6, 'd7, 'd8, 'd9,
    'd0, 'd1, 'd2, 'd3, 'd4,
    'd5, 'd6, 'd7, 'd8, 'd9,

    // Matrix C (M * K)
    'd20, 'd26, 'd32, 'd38, 'd44,
    'd60, 'd82, 'd104, 'd126, 'd148,
    'd60, 'd86, 'd112, 'd138, 'd164
};

reg [7:0] software_thread_num = 8'd15;

int return_code = 0;

initial begin
  testcase.test_kernel(
    init_program_mem,
    init_data_mem,
    golden_data_mem,
    8'd8,
    return_code
  );

  if (return_code == 0) begin
    $display("\nTest PASS.\n");
    $finish(0);
  end
  else begin
    $display("\nTest FAIL!!!\n");
    $display("return code: %d", return_code);
    testcase.show_data_mem_with_golden(golden_data_mem);
    $finish(return_code);
  end

end

endmodule
