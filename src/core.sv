`default_nettype none
`timescale 1ns/1ns

// COMPUTE CORE
// > Handles processing 1 block at a time
// > The core also has it's own scheduler to manage control flow
// > Each core contains 1 fetcher & decoder, and register files, ALUs, LSUs, PC for each thread
module core #(
        parameter DATA_MEM_ADDR_BITS = 8,
        parameter DATA_MEM_DATA_BITS = 8,
        parameter PROGRAM_MEM_ADDR_BITS = 8,
        parameter PROGRAM_MEM_DATA_BITS = 16,
        parameter THREADS_PER_BLOCK = 4,
        parameter CACHE_SIZE = 32
    ) (
        input wire clk,
        input wire reset,

        // Kernel Execution
        input wire start,
        output wire done,

        // Block Metadata
        input wire [7:0] block_id,
        input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

        // Program Memory
        output reg program_mem_read_valid,
        output reg [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
        input wire program_mem_read_ready,
        input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

        // Data Memory
        output reg [THREADS_PER_BLOCK-1:0] data_mem_read_valid,
        output reg [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [THREADS_PER_BLOCK-1:0],
        input wire [THREADS_PER_BLOCK-1:0] data_mem_read_ready,
        input wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [THREADS_PER_BLOCK-1:0],
        output reg [THREADS_PER_BLOCK-1:0] data_mem_write_valid,
        output reg [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [THREADS_PER_BLOCK-1:0],
        output reg [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [THREADS_PER_BLOCK-1:0],
        input wire [THREADS_PER_BLOCK-1:0] data_mem_write_ready
    );
    // State
    reg [2:0] core_state;
    reg [2:0] fetcher_state;
    reg [15:0] instruction;

    // Intermediate Signals
    reg [7:0] current_pc;
    wire [7:0] next_pc[THREADS_PER_BLOCK-1:0];
    reg [7:0] rs[THREADS_PER_BLOCK-1:0];
    reg [7:0] rt[THREADS_PER_BLOCK-1:0];
    reg [1:0] lsu_state[THREADS_PER_BLOCK-1:0];
    reg [7:0] lsu_out[THREADS_PER_BLOCK-1:0];
    wire [7:0] alu_out[THREADS_PER_BLOCK-1:0];

    // Interface between LSU and data cache
    wire [THREADS_PER_BLOCK-1:0] lsu_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_read_address [THREADS_PER_BLOCK-1:0];
    reg [THREADS_PER_BLOCK-1:0] lsu_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] lsu_read_data [THREADS_PER_BLOCK-1:0];

    // Decoded Instruction Signals
    reg [3:0] decoded_rd_address;
    reg [3:0] decoded_rs_address;
    reg [3:0] decoded_rt_address;
    reg [2:0] decoded_nzp;
    reg [7:0] decoded_immediate;

    // Decoded Control Signals
    reg decoded_reg_write_enable;           // Enable writing to a register
    reg decoded_mem_read_enable;            // Enable reading from memory
    reg decoded_mem_write_enable;           // Enable writing to memory
    reg decoded_nzp_write_enable;           // Enable writing to NZP register
    reg [1:0] decoded_reg_input_mux;        // Select input to register
    reg [1:0] decoded_alu_arithmetic_mux;   // Select arithmetic operation
    reg decoded_alu_output_mux;             // Select operation in ALU
    reg decoded_pc_mux;                     // Select source of next PC
    reg decoded_ret;

    // Cache performance statistics from fetcher
    wire [31:0] cache_hit_count;
    wire [31:0] cache_miss_count;
    wire [31:0] cache_total_requests;
    wire [31:0] cache_memory_wait_cycles;

    // LSU performance statistics
    wire [31:0] lsu_read_requests [THREADS_PER_BLOCK-1:0];
    wire [31:0] lsu_write_requests [THREADS_PER_BLOCK-1:0];
    wire [31:0] lsu_wait_cycles [THREADS_PER_BLOCK-1:0];

    // Dcache performance statistics
    wire [31:0] dcache_read_hits [THREADS_PER_BLOCK-1:0];
    wire [31:0] dcache_read_misses [THREADS_PER_BLOCK-1:0];
    wire [31:0] dcache_write_requests [THREADS_PER_BLOCK-1:0];
    wire [31:0] dcache_memory_wait_cycles [THREADS_PER_BLOCK-1:0];

    // Aggregated LSU statistics
    wire [31:0] total_lsu_read_requests;
    wire [31:0] total_lsu_write_requests;
    wire [31:0] total_lsu_wait_cycles;

    // Aggregated Dcache statistics
    wire [31:0] total_dcache_read_hits;
    wire [31:0] total_dcache_read_misses;
    wire [31:0] total_dcache_write_requests;
    wire [31:0] total_dcache_memory_wait_cycles;

    // Aggregate LSU statistics across all threads
    assign total_lsu_read_requests = lsu_read_requests[0] + lsu_read_requests[1] + lsu_read_requests[2] + lsu_read_requests[3];
    assign total_lsu_write_requests = lsu_write_requests[0] + lsu_write_requests[1] + lsu_write_requests[2] + lsu_write_requests[3];
    assign total_lsu_wait_cycles = lsu_wait_cycles[0] + lsu_wait_cycles[1] + lsu_wait_cycles[2] + lsu_wait_cycles[3];

    // Aggregate Dcache statistics across all threads
    assign total_dcache_read_hits = dcache_read_hits[0] + dcache_read_hits[1] + dcache_read_hits[2] + dcache_read_hits[3];
    assign total_dcache_read_misses = dcache_read_misses[0] + dcache_read_misses[1] + dcache_read_misses[2] + dcache_read_misses[3];
    assign total_dcache_write_requests = dcache_write_requests[0] + dcache_write_requests[1] + dcache_write_requests[2] + dcache_write_requests[3];
    assign total_dcache_memory_wait_cycles = dcache_memory_wait_cycles[0] + dcache_memory_wait_cycles[1] + dcache_memory_wait_cycles[2] + dcache_memory_wait_cycles[3];

    // Fetcher
    fetcher #(
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .CACHE_SIZE(CACHE_SIZE)
            ) fetcher_instance (
                .clk(clk),
                .reset(reset),
                .core_state(core_state),
                .current_pc(current_pc),
                .mem_read_valid(program_mem_read_valid),
                .mem_read_address(program_mem_read_address),
                .mem_read_ready(program_mem_read_ready),
                .mem_read_data(program_mem_read_data),
                .fetcher_state(fetcher_state),
                .instruction(instruction),
                .cache_hit_count(cache_hit_count),
                .cache_miss_count(cache_miss_count),
                .cache_total_requests(cache_total_requests),
                .cache_memory_wait_cycles(cache_memory_wait_cycles)
            );

    // Decoder
    decoder decoder_instance (
                .clk(clk),
                .reset(reset),
                .core_state(core_state),
                .instruction(instruction),
                .decoded_rd_address(decoded_rd_address),
                .decoded_rs_address(decoded_rs_address),
                .decoded_rt_address(decoded_rt_address),
                .decoded_nzp(decoded_nzp),
                .decoded_immediate(decoded_immediate),
                .decoded_reg_write_enable(decoded_reg_write_enable),
                .decoded_mem_read_enable(decoded_mem_read_enable),
                .decoded_mem_write_enable(decoded_mem_write_enable),
                .decoded_nzp_write_enable(decoded_nzp_write_enable),
                .decoded_reg_input_mux(decoded_reg_input_mux),
                .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
                .decoded_alu_output_mux(decoded_alu_output_mux),
                .decoded_pc_mux(decoded_pc_mux),
                .decoded_ret(decoded_ret)
            );

    // Scheduler
    wire scheduler_done;
    scheduler #(
                  .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
              ) scheduler_instance (
                  .clk(clk),
                  .reset(reset),
                  .start(start && (thread_count != 0)),
                  .fetcher_state(fetcher_state),
                  .core_state(core_state),
                  .decoded_mem_read_enable(decoded_mem_read_enable),
                  .decoded_mem_write_enable(decoded_mem_write_enable),
                  .decoded_ret(decoded_ret),
                  .lsu_state(lsu_state),
                  .current_pc(current_pc),
                  .next_pc(next_pc),
                  .thread_count(thread_count),
                  .done(scheduler_done),
                  .cache_hit_count(cache_hit_count),
                  .cache_miss_count(cache_miss_count),
                  .cache_total_requests(cache_total_requests),
                  .cache_memory_wait_cycles(cache_memory_wait_cycles),
                  .total_lsu_read_requests(total_lsu_read_requests),
                  .total_lsu_write_requests(total_lsu_write_requests),
                  .total_lsu_wait_cycles(total_lsu_wait_cycles),
                  .total_dcache_read_hits(total_dcache_read_hits),
                  .total_dcache_read_misses(total_dcache_read_misses),
                  .total_dcache_write_requests(total_dcache_write_requests),
                  .total_dcache_memory_wait_cycles(total_dcache_memory_wait_cycles)
              );

    assign done = (thread_count == 0) ? 1'b1 : scheduler_done;

    // Dedicated ALU, LSU, registers, & PC unit for each thread this core has capacity for
    genvar i;
    generate
        for (i = 0;
                i < THREADS_PER_BLOCK;
                i = i + 1) begin : threads
            // ALU
            alu alu_instance (
                    .clk(clk),
                    .reset(reset),
                    .enable(i < thread_count),
                    .core_state(core_state),
                    .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
                    .decoded_alu_output_mux(decoded_alu_output_mux),
                    .rs(rs[i]),
                    .rt(rt[i]),
                    .alu_out(alu_out[i])
                )
                ;

            // Define the write interface from LSU to dcache (per thread)
            wire [THREADS_PER_BLOCK-1:0] lsu_write_valid;
            wire [DATA_MEM_ADDR_BITS-1:0] lsu_write_address [THREADS_PER_BLOCK-1:0];
            wire [DATA_MEM_DATA_BITS-1:0] lsu_write_data [THREADS_PER_BLOCK-1:0];
            wire [THREADS_PER_BLOCK-1:0] lsu_write_ready;

            // LSU - Connect write operations to dcache instead of directly to memory
            lsu lsu_instance (
                    .clk(clk),
                    .reset(reset),
                    .enable(i < thread_count),
                    .core_state(core_state),
                    .decoded_mem_read_enable(decoded_mem_read_enable),
                    .decoded_mem_write_enable(decoded_mem_write_enable),
                    // Read interface remains unchanged
                    .mem_read_valid(lsu_read_valid[i]),
                    .mem_read_address(lsu_read_address[i]),
                    .mem_read_ready(lsu_read_ready[i]),
                    .mem_read_data(lsu_read_data[i]),
                    // Write interface now connects to per-thread signals, later connected to dcache
                    .mem_write_valid(lsu_write_valid[i]),
                    .mem_write_address(lsu_write_address[i]),
                    .mem_write_data(lsu_write_data[i]),
                    .mem_write_ready(lsu_write_ready[i]),
                    .rs(rs[i]),
                    .rt(rt[i]),
                    .lsu_state(lsu_state[i]),
                    .lsu_out(lsu_out[i]),
                    .lsu_read_requests(lsu_read_requests[i]),
                    .lsu_write_requests(lsu_write_requests[i]),
                    .lsu_wait_cycles(lsu_wait_cycles[i])
                );

            // Data Cache (supports both read and write operations with write-through policy)
            dcache #(
                       .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                       .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                       .CACHE_SIZE(CACHE_SIZE)
                   ) dcache_instance (
                       .clk(clk),
                       .reset(reset),
                       // Read interface - LSU side
                       .lsu_read_address(lsu_read_address[i]),
                       .lsu_read_request(lsu_read_valid[i]),
                       .lsu_read_valid(lsu_read_ready[i]),
                       .lsu_read_data(lsu_read_data[i]),
                       // Read interface - Memory side
                       .mem_read_valid(data_mem_read_valid[i]),
                       .mem_read_address(data_mem_read_address[i]),
                       .mem_read_ready(data_mem_read_ready[i]),
                       .mem_read_data(data_mem_read_data[i]),
                       // Write interface - LSU side (per thread)
                       .lsu_write_address(lsu_write_address[i]),
                       .lsu_write_request(lsu_write_valid[i]),
                       .lsu_write_data(lsu_write_data[i]),
                       .lsu_write_valid(lsu_write_ready[i]),
                       // Write interface - Memory side (new)
                       .mem_write_valid(data_mem_write_valid[i]),
                       .mem_write_address(data_mem_write_address[i]),
                       .mem_write_data(data_mem_write_data[i]),
                       .mem_write_ready(data_mem_write_ready[i]),
                       // Performance statistics
                       .dcache_read_hits(dcache_read_hits[i]),
                       .dcache_read_misses(dcache_read_misses[i]),
                       .dcache_write_requests(dcache_write_requests[i]),
                       .dcache_memory_wait_cycles(dcache_memory_wait_cycles[i])
                   );

            // Register File
            registers #(
                          .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                          .THREAD_ID(i),
                          .DATA_BITS(DATA_MEM_DATA_BITS)
                      ) register_instance (
                          .clk(clk),
                          .reset(reset),
                          .enable(i < thread_count),
                          .block_id(block_id),
                          .core_state(core_state),
                          .decoded_reg_write_enable(decoded_reg_write_enable),
                          .decoded_reg_input_mux(decoded_reg_input_mux),
                          .decoded_rd_address(decoded_rd_address),
                          .decoded_rs_address(decoded_rs_address),
                          .decoded_rt_address(decoded_rt_address),
                          .decoded_immediate(decoded_immediate),
                          .alu_out(alu_out[i]),
                          .lsu_out(lsu_out[i]),
                          .rs(rs[i]),
                          .rt(rt[i])
                      );

            // Program Counter
            pc #(
                   .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                   .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
               ) pc_instance (
                   .clk(clk),
                   .reset(reset),
                   .enable(i < thread_count),
                   .core_state(core_state),
                   .decoded_nzp(decoded_nzp),
                   .decoded_immediate(decoded_immediate),
                   .decoded_nzp_write_enable(decoded_nzp_write_enable),
                   .decoded_pc_mux(decoded_pc_mux),
                   .alu_out(alu_out[i]),
                   .current_pc(current_pc),
                   .next_pc(next_pc[i])
               );
        end
    endgenerate
endmodule
