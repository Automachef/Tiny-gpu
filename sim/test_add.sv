`timescale 1ns/1ns

module tb_matadd;

    reg clk = 0;
    reg reset = 0;
    reg start = 0;
    reg device_control_write_enable = 0;
    reg [7:0] device_control_data = 0;

    localparam DATA_MEM_ADDR_BITS       = 8;
    localparam DATA_MEM_DATA_BITS       = 8;
    localparam DATA_MEM_NUM_CHANNELS    = 4;
    localparam PROGRAM_MEM_ADDR_BITS    = 8;
    localparam PROGRAM_MEM_DATA_BITS    = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 1;
    localparam NUM_CORES                = 2;
    localparam THREADS_PER_BLOCK        = 4;

    reg  [PROGRAM_MEM_DATA_BITS-1:0]      program_mem [0:255];
    reg  [DATA_MEM_DATA_BITS-1:0]         data_mem    [0:255];

    wire [PROGRAM_MEM_NUM_CHANNELS-1:0]   program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0]      program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg  [PROGRAM_MEM_NUM_CHANNELS-1:0]   program_mem_read_ready = 0;
    reg  [PROGRAM_MEM_DATA_BITS-1:0]      program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];

    wire [DATA_MEM_NUM_CHANNELS-1:0]      data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0]         data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
    reg  [DATA_MEM_NUM_CHANNELS-1:0]      data_mem_read_ready = 0;
    reg  [DATA_MEM_DATA_BITS-1:0]         data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];

    wire [DATA_MEM_NUM_CHANNELS-1:0]      data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0]         data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0]         data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
    reg  [DATA_MEM_NUM_CHANNELS-1:0]      data_mem_write_ready = 0;

    wire done;

    gpu #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .DATA_MEM_NUM_CHANNELS(DATA_MEM_NUM_CHANNELS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .program_mem_read_valid(program_mem_read_valid),
        .program_mem_read_address(program_mem_read_address),
        .program_mem_read_ready(program_mem_read_ready),
        .program_mem_read_data(program_mem_read_data),
        .data_mem_read_valid(data_mem_read_valid),
        .data_mem_read_address(data_mem_read_address),
        .data_mem_read_ready(data_mem_read_ready),
        .data_mem_read_data(data_mem_read_data),
        .data_mem_write_valid(data_mem_write_valid),
        .data_mem_write_address(data_mem_write_address),
        .data_mem_write_data(data_mem_write_data),
        .data_mem_write_ready(data_mem_write_ready)
    );

    always #5 clk = ~clk;

    task print_matrix(
        input string name,
        input int rows,
        input int cols,
        input int base,
        input reg [7:0] mem [0:255]
    );
        int i, j;
        $display("%s:", name);
        for (i = 0; i < rows; i++) begin
            $write("  ");
            for (j = 0; j < cols; j++) begin
                $write("%4d", mem[base + i * cols + j]);
            end
            $write("\n");
        end
    endtask

    task automatic generate_data(
        input int rows, 
        input int cols, 
        ref reg [7:0] data [0:255]
    );
        int i;
        for (i = 0; i < rows * cols * 2; i++) begin
            data[i] = $urandom_range(0, 9);
        end
        for (i = rows * cols * 2; i < 256; i++) begin
            data[i] = 0;
        end
    endtask

    task automatic calc_expected_results(
        input reg [7:0] data [0:255],
        input int rows, 
        input int cols, 
        input int baseA,
        input int baseB,
        output reg [7:0] C [0:255]
    );
        int i, j;
        for (i = 0; i < rows; i++) begin
            for (j = 0; j < cols; j++) begin
                int idx = i * cols + j;
                C[idx] = data[baseA + idx] + data[baseB + idx];
            end
        end
        for (i = rows * cols; i < 256; i++) C[i] = 0;
    endtask

    task automatic generate_matadd_program(
        input int base_a, input int base_b, input int base_c,
        ref int prog_data [0:255]
    );

        prog_data[0] = 16'b0101000011011110; // MUL R0, %blockIdx, %blockDim
        prog_data[1] = 16'b0011000000001111; // ADD R0, R0, %threadIdx
        prog_data[2] = (16'b1001000100000000 | (base_a & 8'hFF)); // CONST R1, #baseA
        prog_data[3] = (16'b1001001000000000 | (base_b & 8'hFF)); // CONST R2, #baseB
        prog_data[4] = (16'b1001001100000000 | (base_c & 8'hFF)); // CONST R3, #baseC
        prog_data[5] = 16'b0011010000010000; // ADD R4, R1, R0
        prog_data[6] = 16'b0111010001000000; // LDR R4, R4
        prog_data[7] = 16'b0011010100100000; // ADD R5, R2, R0
        prog_data[8] = 16'b0111010101010000; // LDR R5, R5
        prog_data[9] = 16'b0011011001000101; // ADD R6, R4, R5
        prog_data[10] = 16'b0011011100110000; // ADD R7, R3, R0
        prog_data[11] = 16'b1000000001110110; // STR R7, R6
        prog_data[12] = 16'b1111000000000000; // RET

        for (int i = 13; i < 256; i++) begin
            prog_data[i] = 16'd0;
        end
    endtask

    task automatic matadd_test(input int rows, input int cols);
        int baseA, baseB, baseC;
        reg [7:0] data [0:255];
        int prog_data  [0:255];
        reg [7:0] expected [0:255];
        int i;
        int pass;

        baseA = 0;
        baseB = rows * cols;
        baseC = baseB + rows * cols;

        generate_data(rows, cols, data);
        for (i = 0; i < 256; i++) begin
            data_mem[i] = data[i];
        end

        generate_matadd_program(baseA, baseB, baseC, prog_data);
        for (i = 0; i < 256; i++) begin 
            program_mem[i] = prog_data[i];
        end

        print_matrix("Matrix A", rows, cols, baseA, data);
        print_matrix("Matrix B", rows, cols, baseB, data);

        #10 reset = 1;
        #20 reset = 0;
        #10 device_control_data = rows * cols;
            device_control_write_enable = 1;
        
        #10 device_control_write_enable = 0;
        #10 start = 1;
        
        wait(done == 1);
        #10 start = 0;

        calc_expected_results(data, rows, cols, baseA, baseB, expected);
        print_matrix("Expected C", rows, cols, 0, expected);
        print_matrix("Simulated C", rows, cols, baseC, data_mem);

        pass = 1;
        for (i = 0; i < rows * cols; i++) begin
            if (data_mem[baseC + i] !== expected[i]) begin
                $display("FAIL: C[%0d]=%0d, expected=%0d", i, data_mem[baseC + i], expected[i]);
                pass = 0;
            end
        end

        if (pass) $display("PASS: All data matched!");
        else      $display("FAIL: Data mismatch!");
    endtask

    always @(posedge clk) begin
        for (int i = 0; i < PROGRAM_MEM_NUM_CHANNELS; i++) begin
            if (program_mem_read_valid[i] && program_mem_read_ready[i])
                program_mem_read_ready[i] <= 1'b0;
            else if (program_mem_read_valid[i]) begin
                program_mem_read_ready[i] <= 1'b1;
                program_mem_read_data[i]  <= program_mem[program_mem_read_address[i]];
            end
        end
    end

    always @(posedge clk) begin
        for (int k = 0; k < DATA_MEM_NUM_CHANNELS; k++) begin
            if (data_mem_read_valid[k] && data_mem_read_ready[k])
                data_mem_read_ready[k] <= 1'b0;
            else if (data_mem_read_valid[k]) begin
                data_mem_read_ready[k] <= 1'b1;
                data_mem_read_data[k]  <= data_mem[data_mem_read_address[k]];
            end

            if (data_mem_write_valid[k] && data_mem_write_ready[k])
                data_mem_write_ready[k] <= 1'b0;
            else if (data_mem_write_valid[k]) begin
                data_mem_write_ready[k] <= 1'b1;
                data_mem[data_mem_write_address[k]] <= data_mem_write_data[k];
            end
        end
    end

    initial begin
        int rows = 3, cols = 3;
        matadd_test(rows, cols);
        $finish;
    end

    initial begin
        $fsdbDumpfile("simv.fsdb");
        $fsdbDumpvars(0, tb_matadd);
    end

endmodule
