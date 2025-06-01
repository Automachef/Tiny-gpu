`timescale 1ns/1ns

module test_matadd();

	// Parameter
	localparam DATA_MEM_ADDR_BITS = 8;
	localparam DATA_MEM_DATA_BITS = 8;
	localparam DATA_MEM_NUM_CHANNELS = 4;
	localparam PROGRAM_MEM_ADDR_BITS = 8;
	localparam PROGRAM_MEM_DATA_BITS = 16;
	localparam PROGRAM_MEM_NUM_CHANNELS = 1;
	localparam NUM_CORES = 2;
	localparam THREADS_PER_BLOCK = 4;

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
		device_control_data = 8'd8;
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

		program_mem[0:12] = '{
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

		data_mem[0:15] = '{
			'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7, // Matrix A
			'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7 // Matrix B
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
		localparam check_length = 24;
		reg [DATA_MEM_DATA_BITS-1:0] expected_data_mem [0:check_length-1] = '{
			'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7,
			'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7,
			'd0, 'd2, 'd4, 'd6, 'd8, 'd10, 'd12, 'd14
		};
		for (int i = 0; i < check_length; i += 1) begin
			if (data_mem[i] != expected_data_mem[i]) begin
				return -1;
			end
		end
		return 0;
	endfunction

endmodule