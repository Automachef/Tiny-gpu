`timescale 1ns/1ns

module test_matmul();

	// Parameter
	localparam DATA_MEM_ADDR_BITS = 8;
	localparam DATA_MEM_DATA_BITS = 8;
	localparam DATA_MEM_NUM_CHANNELS = 4;
	localparam PROGRAM_MEM_ADDR_BITS = 8;
	localparam PROGRAM_MEM_DATA_BITS = 16;
	localparam PROGRAM_MEM_NUM_CHANNELS = 1;
	localparam NUM_CORES = 2;
	localparam THREADS_PER_BLOCK = 2;

	localparam DATA_MEM_LENGTH = 1 << DATA_MEM_ADDR_BITS;
	localparam PROGRAM_MEM_LENGTH = 1 << PROGRAM_MEM_ADDR_BITS;

	// Port
	reg clk;
	reg reset;

	reg start;
	wire done;

	reg device_control_write_enable;
	reg [7:0] device_control_data;

	wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
	wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
	reg [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
	reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];

	wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
	wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
	reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
	reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
	wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
	wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
	wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
	reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;

	// Memory
	reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem [0:PROGRAM_MEM_LENGTH-1];
	reg [DATA_MEM_DATA_BITS-1:0] data_mem [0:DATA_MEM_LENGTH-1];

	// Instance
	gpu #(
		.DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
		.DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
		.DATA_MEM_NUM_CHANNELS(DATA_MEM_NUM_CHANNELS),
		.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
		.PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
		.PROGRAM_MEM_NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
		.NUM_CORES(NUM_CORES),
		.THREADS_PER_BLOCK(THREADS_PER_BLOCK)
	) gpu_instance(
		.clk(clk),
		.reset(reset),

		// Kernel Execution
		.start(start),
		.done(done),

		// Device Control Register
		.device_control_write_enable(device_control_write_enable),
		.device_control_data(device_control_data),

		// Program Memory
		.program_mem_read_valid(program_mem_read_valid),
		.program_mem_read_address(program_mem_read_address),
		.program_mem_read_ready(program_mem_read_ready),
		.program_mem_read_data(program_mem_read_data),

		// Data Memory
		.data_mem_read_valid(data_mem_read_valid),
		.data_mem_read_address(data_mem_read_address),
		.data_mem_read_ready(data_mem_read_ready),
		.data_mem_read_data(data_mem_read_data),
		.data_mem_write_valid(data_mem_write_valid),
		.data_mem_write_address(data_mem_write_address),
		.data_mem_write_data(data_mem_write_data),
		.data_mem_write_ready(data_mem_write_ready)
	);

	// Variable for Verification
	int check_return;

	// Clock
	initial clk = 1'b0;
	always #5 clk = ~clk;

	// Simulation Procedure
	initial begin
		reset = 1'b0;
		start = 1'b0;
		device_control_write_enable = 1'b0;
		init_mem();

		// Reset
		#4 reset = 1'b1;
		#20 reset = 1'b0;

		#10;

		// Set thread number
		device_control_data = 8'd4;
		device_control_write_enable = 1'b1;
		#10 device_control_write_enable = 1'b0;

		#10;

		// Run Kernel
		start = 1'b1;
		wait(done);

		#10;

		//Check the Result
		check_return = check_data_mem();
		if (check_return == 0) begin
			$display("\nTest PASS.\n");
			$finish(0);
		end
		else begin
			$display("\nTest FAIL!!!\n");
			$display("return code: %d", check_return);
			$finish(check_return);
		end

	end

	// Memory Management
	task automatic init_mem();
		program_mem_read_ready = 1'b0;
		data_mem_read_ready = 1'b0;
		data_mem_write_ready = 1'b0;

		program_mem[0:27] = '{
			16'b0101000011011110, // MUL R0, %blockIdx, %blockDim
			16'b0011000000001111, // ADD R0, R0, %threadIdx
			16'b1001000100000001, // CONST R1, #1
			16'b1001001000000010, // CONST R2, #2
			16'b1001001100000000, // CONST R3, #0
			16'b1001010000000100, // CONST R4, #4
			16'b1001010100001000, // CONST R5, #8
			16'b0110011000000010, // DIV R6, R0, R2
			16'b0101011101100010, // MUL R7, R6, R2
			16'b0100011100000111, // SUB R7, R0, R7
			16'b1001100000000000, // CONST R8, #0
			16'b1001100100000000, // CONST R9, #0
			// LOOP:
			16'b0101101001100010, // MUL R10, R6, R2
			16'b0011101010101001, // ADD R10, R10, R9
			16'b0011101010100011, // ADD R10, R10, R3
			16'b0111101010100000, // LDR R10, R10
			16'b0101101110010010, // MUL R11, R9, R2
			16'b0011101110110111, // ADD R11, R11, R7
			16'b0011101110110100, // ADD R11, R11, R4
			16'b0111101110110000, // LDR R11, R11
			16'b0101110010101011, // MUL R12, R10, R11
			16'b0011100010001100, // ADD R8, R8, R12
			16'b0011100110010001, // ADD R9, R9, R1
			16'b0010000010010010, // CMP R9, R2
			16'b0001100000001100, // BRn LOOP
			16'b0011100101010000, // ADD R9, R5, R0
			16'b1000000010011000, // STR R9, R8
			16'b1111000000000000  // RET
		};

		data_mem[0:7] = '{
			'd1, 'd2, 'd3, 'd4,  // Matrix A
			'd1, 'd2, 'd3, 'd4   // Matrix B
		};

	endtask

	always@(posedge clk) begin
		for (int i = 0; i < PROGRAM_MEM_NUM_CHANNELS; i += 1) begin
			// Read Program Memory
			if (program_mem_read_valid[i] && program_mem_read_ready[i]) begin
				program_mem_read_ready[i] <= 1'b0;
			end
			else if (program_mem_read_valid[i]) begin
				program_mem_read_ready[i] <= 1'b1;
				program_mem_read_data[i] <= program_mem[program_mem_read_address[i]];
			end
		end
	end

	always@(posedge clk) begin
		for (int i = 0; i < DATA_MEM_NUM_CHANNELS; i += 1) begin
			// Read Data Memory
			if (data_mem_read_valid[i] && data_mem_read_ready[i]) begin
				data_mem_read_ready[i] <= 1'b0;
			end
			else if (data_mem_read_valid[i]) begin
				data_mem_read_ready[i] <= 1'b1;
				data_mem_read_data[i] <= data_mem[data_mem_read_address[i]];
			end

			// Write Data Memory
			if (data_mem_write_valid[i] && data_mem_write_ready[i]) begin
				data_mem_write_ready[i] <= 1'b0;
			end
			else if (data_mem_write_valid[i]) begin
				data_mem_write_ready[i] <= 1'b1;
				data_mem[data_mem_write_address[i]] <= data_mem_write_data[i];
			end
		end
	end

	function automatic int check_data_mem();
		localparam check_length = 12;
		reg [DATA_MEM_DATA_BITS-1:0] expected_data_mem [0:check_length-1] = '{
			'd1, 'd2, 'd3, 'd4, 
			'd1, 'd2, 'd3, 'd4,
			'd7, 'd10, 'd15, 'd22
		};
		for (int i = 0; i < check_length; i += 1) begin
			if (data_mem[i] != expected_data_mem[i]) begin
				return -1;
			end
		end
		return 0;
	endfunction

endmodule