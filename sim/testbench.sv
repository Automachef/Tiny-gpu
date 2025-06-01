`timescale 1ns/1ns

module tb_matmul;
    // 信号定义
    reg clk = 0;
    reg reset = 0;
    reg start = 0;
    reg device_control_write_enable = 0;
    reg [7:0] device_control_data = 0;

    // 参数定义
    localparam DATA_MEM_ADDR_BITS = 8;
    localparam DATA_MEM_DATA_BITS = 8;
    localparam DATA_MEM_NUM_CHANNELS = 4;
    localparam PROGRAM_MEM_ADDR_BITS = 8;
    localparam PROGRAM_MEM_DATA_BITS = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 1;
    localparam NUM_CORES = 2;
    localparam THREADS_PER_BLOCK = 4;

    // 存储器与接口信号
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem [0:255];
    reg [DATA_MEM_DATA_BITS-1:0] data_mem [0:255];
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready = 0;
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready = 0;
    reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready = 0;
    wire done;

    // DUT实例
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

    // 时钟
    always #5 clk = ~clk;

    // 仿真流程
    initial begin
        // 初始化存储器
        for (int i = 0; i < 256; i++) begin
            program_mem[i] = 16'd0;
            data_mem[i] = 8'd0;
        end

        // 初始化程序存储器
        program_mem[0] = 16'b0101000011011110;  // MUL R0, %blockIdx, %blockDim
        program_mem[1] = 16'b0011000000001111;  // ADD R0, R0, %threadIdx
        program_mem[2] = 16'b1001000100000001;  // CONST R1, #1
        program_mem[3] = 16'b1001001000000010;  // CONST R2, #2
        program_mem[4] = 16'b1001001100000000;  // CONST R3, #0
        program_mem[5] = 16'b1001010000000100;  // CONST R4, #4
        program_mem[6] = 16'b1001010100001000;  // CONST R5, #8
        program_mem[7] = 16'b0110011000000010;  // DIV R6, R0, R2
        program_mem[8] = 16'b0101011101100010;  // MUL R7, R6, R2
        program_mem[9] = 16'b0100011100000111;  // SUB R7, R0, R7
        program_mem[10] = 16'b1001100000000000; // CONST R8, #0
        program_mem[11] = 16'b1001100100000000; // CONST R9, #0
        program_mem[12] = 16'b0101101001100010; // MUL R10, R6, R2
        program_mem[13] = 16'b0011101010101001; // ADD R10, R10, R9
        program_mem[14] = 16'b0011101010100011; // ADD R10, R10, R3
        program_mem[15] = 16'b0111101010100000; // LDR R10, R10
        program_mem[16] = 16'b0101101110010010; // MUL R11, R9, R2
        program_mem[17] = 16'b0011101110110111; // ADD R11, R11, R7
        program_mem[18] = 16'b0011101110110100; // ADD R11, R11, R4
        program_mem[19] = 16'b0111101110110000; // LDR R11, R11
        program_mem[20] = 16'b0101110010101011; // MUL R12, R10, R11
        program_mem[21] = 16'b0011100010001100; // ADD R8, R8, R12
        program_mem[22] = 16'b0011100110010001; // ADD R9, R9, R1
        program_mem[23] = 16'b0010000010010010; // CMP R9, R2
        program_mem[24] = 16'b0001100000001100; // BRn LOOP
        program_mem[25] = 16'b0011100101010000; // ADD R9, R5, R0
        program_mem[26] = 16'b1000000010011000; // STR R9, R8
        program_mem[27] = 16'b1111000000000000; // RET

        // 初始化数据存储器（2x2矩阵A和B）
        data_mem[0] = 8'd1;  // A[0,0]
        data_mem[1] = 8'd2;  // A[0,1]
        data_mem[2] = 8'd3;  // A[1,0]
        data_mem[3] = 8'd4;  // A[1,1]
        data_mem[4] = 8'd1;  // B[0,0]
        data_mem[5] = 8'd2;  // B[0,1]
        data_mem[6] = 8'd3;  // B[1,0]
        data_mem[7] = 8'd4;  // B[1,1]

        // 复位
        #4 reset = 1;
        #20 reset = 0;
        #10;

        // 设置线程数为8
        device_control_data = 8'd4;
        device_control_write_enable = 1;
        #10 device_control_write_enable = 0;
        #10;

        // 启动核
        start = 1;
        wait(done == 1);
        #10 start = 0;
    end

    // 程序存储器接口模拟
    always @(posedge clk) begin
        for (int i = 0; i < PROGRAM_MEM_NUM_CHANNELS; i++) begin
            if (program_mem_read_valid[i] && program_mem_read_ready[i]) begin
                program_mem_read_ready[i] <= 1'b0;
            end
            else if (program_mem_read_valid[i]) begin
                program_mem_read_ready[i] <= 1'b1;
                program_mem_read_data[i] <= program_mem[program_mem_read_address[i]];
            end
        end
    end

    // 数据存储器接口模拟
    always @(posedge clk) begin
        for (int k = 0; k < DATA_MEM_NUM_CHANNELS; k++) begin
            // 读
            if (data_mem_read_valid[k] && data_mem_read_ready[k]) begin
                data_mem_read_ready[k] <= 1'b0;
            end
            else if (data_mem_read_valid[k]) begin
                data_mem_read_ready[k] <= 1'b1;
                data_mem_read_data[k] <= data_mem[data_mem_read_address[k]];
            end

            // 写
            if (data_mem_write_valid[k] && data_mem_write_ready[k]) begin
                data_mem_write_ready[k] <= 1'b0;
            end
            else if (data_mem_write_valid[k]) begin
                data_mem_write_ready[k] <= 1'b1;
                data_mem[data_mem_write_address[k]] <= data_mem_write_data[k];
            end
        end
    end

    // 结果检查
    initial begin
        automatic int pass = 1;
        automatic int i;
        automatic int expected [0:11];
        expected [0:11] = '{1,2,3,4,1,2,3,4,7,10,15,22};

        // 等待核执行完成
        wait(done == 1);
        #10;

        // 检查结果
        for (i = 0; i < 12; i++) begin
            if (data_mem[i] !== expected[i]) begin
                $display("FAIL: data_mem[%0d]=%0d, expected=%0d", i, data_mem[i], expected[i]);
                pass = 0;
            end
        end

        if (pass) begin
            $display("PASS: All data matched (address 0-11)!");
            $finish;
        end
        else begin
            $display("FAIL: Data mismatch!");
            $finish(1);
        end
    end

endmodule