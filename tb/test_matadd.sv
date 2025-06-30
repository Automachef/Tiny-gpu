module test_matadd();

framework testcase();

reg [15:0] init_program_mem [] = '{
    'b0101000011011110, // MUL R0, %blockIdx, %blockDim
    'b0011000000001111, // ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx
    'b1001000100000000, // CONST R1, #0                   ; baseA (matrix A base address)
    'b1001001000001000, // CONST R2, #8                   ; baseB (matrix B base address)
    'b1001001100010000, // CONST R3, #16                  ; baseC (matrix C base address)
    'b0011010000010000, // ADD R4, R1, R0                 ; addr(A[i]) = baseA + i
    'b0111010001000000, // LDR R4, R4                     ; load A[i] from global memory
    'b0011010100100000, // ADD R5, R2, R0                 ; addr(B[i]) = baseB + i
    'b0111010101010000, // LDR R5, R5                     ; load B[i] from global memory
    'b0011011001000101, // ADD R6, R4, R5                 ; C[i] = A[i] + B[i]
    'b0011011100110000, // ADD R7, R3, R0                 ; addr(C[i]) = baseC + i
    'b1000000001110110, // STR R7, R6                     ; store C[i] in global memory
    'b1111000000000000  // RET                            ; end of kernel
};

reg [7:0] init_data_mem [] = '{
    'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7, // Matrix A
    'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7 // Matrix B
};

reg [7:0] golden_data_mem [] = '{
    'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7,
    'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7,
    'd0, 'd2, 'd4, 'd6, 'd8, 'd10, 'd12, 'd14
};

reg [7:0] software_thread_num = 8'd8;

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
