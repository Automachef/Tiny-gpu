`timescale 1ns/1ns

module tb_matmul;

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
            input int n,
            ref reg [7:0] data [0:255]
        );
        int i;
        for (i = 0; i < rows * n + n * cols; i++) begin
            data[i] = $urandom_range(0, 9);
        end
        for (i = rows * n + n * cols; i < 256; i++) begin
            data[i] = 0;
        end
    endtask

    task automatic calc_expected_results(
            input reg [7:0] data [0:255],
            input int rows,
            input int cols,
            input int n,
            output reg [7:0] C [0:255]
        );
        int i, j, k;
        int A[0:63];
        int B[0:63];

        for (i = 0; i < rows * n; i++)
            A[i] = data[i];
        for (i = 0; i < n * cols; i++)
            B[i] = data[rows * n + i];

        for (i = 0; i < rows; i++) begin
            for (j = 0; j < cols; j++) begin
                int val = 0;
                for (k = 0; k < n; k++) begin
                    val += A[i * n + k] * B[k * cols + j];
                end
                C[i * cols + j] = (val > 255) ? 8'hFF : val;
            end
        end
        for (i = rows * cols; i < 256; i++)
            C[i] = 0;
    endtask

    task automatic generate_matmul_program(
            input int rows, input int cols, input int n, input int baseA, input int baseB, input int baseC,
            ref int prog_data [0:255]
        );

        prog_data[0]  = 16'b0101000011011110;
        prog_data[1]  = 16'b0011000000001111;
        prog_data[2]  = 16'b1001000100000001;
        prog_data[3]  = 16'b1001001000000000 | (n    & 8'hFF);
        prog_data[4]  = 16'b1001001100000000 | (rows & 8'hFF);
        prog_data[5]  = 16'b1001010000000000 | (cols & 8'hFF);
        prog_data[6]  = 16'b1001010100000000 | (baseA & 8'hFF);
        prog_data[7]  = 16'b1001011000000000 | (baseB & 8'hFF);
        prog_data[8]  = 16'b1001011100000000 | (baseC & 8'hFF);
        prog_data[9]  = 16'b1001100000000000;
        prog_data[10] = 16'b1001100100000000;
        prog_data[11] = 16'b0110101000000100;
        prog_data[12] = 16'b0101101110100100;
        prog_data[13] = 16'b0100101100001011;
        prog_data[14] = 16'b0101101010100010;
        prog_data[15] = 16'b0011101010101001;
        prog_data[16] = 16'b0011101010100101;
        prog_data[17] = 16'b0111101010100000;
        prog_data[18] = 16'b0101110010010100;
        prog_data[19] = 16'b0011101111001011;
        prog_data[20] = 16'b0011101110110110;
        prog_data[21] = 16'b0111101110110000;
        prog_data[22] = 16'b0101110010101011;
        prog_data[23] = 16'b0011100010001100;
        prog_data[24] = 16'b0011100110010001;
        prog_data[25] = 16'b0010000010010010;
        prog_data[26] = 16'b0001100000001011;
        prog_data[27] = 16'b0011101001110000;
        prog_data[28] = 16'b1000000010101000;
        prog_data[29] = 16'b1111000000000000;

        for (int i = 30; i < 256; i++) begin
            prog_data[i] = 16'd0;
        end
    endtask

    task automatic matmul_test(input int rows, input int cols, input int n);
        int baseA, baseB, baseC, total_size;
        reg [7:0] data [0:255];
        int prog_data  [0:255];
        reg [7:0] expected [0:255];
        int i;
        int pass;

        baseA = 0;
        baseB = rows * n;
        baseC = baseB + n * cols;
        total_size = rows * n + n * cols;

        generate_data(rows, cols, n, data);
        for (i = 0; i < 256; i++) begin
            data_mem[i] = data[i];
        end

        generate_matmul_program(rows, cols, n, baseA, baseB, baseC, prog_data);
        for (i = 0; i < 256; i++) begin
            program_mem[i] = prog_data[i];
        end

        print_matrix("Matrix A", rows, n, baseA, data);
        print_matrix("Matrix B", n, cols, baseB, data);

        #10 reset = 1;
        #20 reset = 0;

        #10 device_control_data = rows * cols;
        device_control_write_enable = 1;

        #10 device_control_write_enable = 0;
        #10 start = 1;

        wait(done == 1);
        #10 start = 0;

        calc_expected_results(data, rows, cols, n, expected);
        print_matrix("Expected C", rows, cols, 0, expected);
        print_matrix("Simulated C", rows, cols, baseC, data_mem);

        pass = 1;
        for (i = 0; i < rows * cols; i++) begin
            if (data_mem[baseC + i] !== expected[i]) begin
                $display("FAIL: C[%0d]=%0d, expected=%0d", i, data_mem[baseC + i], expected[i]);
                pass = 0;
            end
        end

        if (pass)
            $display("PASS: All data matched!");
        else
            $display("FAIL: Data mismatch!");
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
        int rows = 3, cols = 3, n = 3;
        matmul_test(rows, cols, n);
        $finish;
    end

    initial begin
        $fsdbDumpfile("simv.fsdb");
        $fsdbDumpvars(0, tb_matmul);
    end

endmodule
