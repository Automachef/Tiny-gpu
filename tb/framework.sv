module framework #(
  parameter DATA_MEM_ADDR_BITS = 8,
  parameter DATA_MEM_NUM_CHANNELS = 4,
  parameter PROGRAM_MEM_ADDR_BITS = 8,
  parameter PROGRAM_MEM_NUM_CHANNELS = 2,
  parameter NUM_CORES = 2,
  parameter THREADS_PER_BLOCK = 4
) ();

// Local Parameter
localparam DATA_MEM_DATA_BITS = 8;
localparam PROGRAM_MEM_DATA_BITS = 16;

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

initial begin
end

// Simulation Procedure
task automatic test_kernel(
  input reg [PROGRAM_MEM_DATA_BITS-1:0] init_program_mem [],
  input reg [DATA_MEM_DATA_BITS-1:0] init_data_mem [],
  input reg [DATA_MEM_DATA_BITS-1:0] golden_data_mem [],
  input reg [7:0] kernel_thread_number,
  output int return_code
  );

  reset = 1'b0;
  start = 1'b0;
  device_control_write_enable = 1'b0;
  init_mem(init_program_mem, init_data_mem);

  // Reset
  #4 reset = 1'b1;
  #20 reset = 1'b0;

  #10;

  // Set thread number
  device_control_data = kernel_thread_number;
  device_control_write_enable = 1'b1;
  #10 device_control_write_enable = 1'b0;

  #10;

  // Run Kernel
  start = 1'b1;
  wait(done);

  #10;

  //Check the Result
  return_code = check_data_mem(golden_data_mem);
endtask

// Memory Management
task automatic init_mem(
  input reg [PROGRAM_MEM_DATA_BITS-1:0] init_program_mem [],
  input reg [DATA_MEM_DATA_BITS-1:0] init_data_mem []
);
  program_mem_read_ready = 1'b0;
  data_mem_read_ready = 1'b0;
  data_mem_write_ready = 1'b0;

  for (int i = 0; i < init_program_mem.size() && i < PROGRAM_MEM_LENGTH; i += 1) begin
    program_mem[i] = init_program_mem[i];
  end

  for (int i = 0; i < init_data_mem.size() && i < DATA_MEM_LENGTH; i += 1) begin
    data_mem[i] = init_data_mem[i];
  end

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

function automatic int check_data_mem(
  input reg [DATA_MEM_DATA_BITS-1:0] golden_data_mem []
);

  for (int i = 0; i < golden_data_mem.size && i < DATA_MEM_LENGTH; i += 1) begin
    if (data_mem[i] != golden_data_mem[i]) begin
      return -1;
    end
  end

  return 0;
endfunction

task automatic show_data_mem_with_golden(
  input reg [DATA_MEM_DATA_BITS-1:0] golden_data_mem []
);
  for (int i = 0; i < golden_data_mem.size && i < DATA_MEM_LENGTH; i += 1) begin
    if (data_mem[i] != golden_data_mem[i]) begin
      $display("Addr: %x, Golden: %x, Actual: %x.\n", i, golden_data_mem[i], data_mem[i]);
    end
  end
endtask

endmodule
