`default_nettype none
`timescale 1ns/1ns

// SCHEDULER
// > Manages the entire control flow of a single compute core processing 1 block
// 1. FETCH - Retrieve instruction at current program counter (PC) from program memory
// 2. DECODE - Decode the instruction into the relevant control signals
// 3. REQUEST - If we have an instruction that accesses memory, trigger the async memory requests from LSUs
// 4. WAIT - Wait for all async memory requests to resolve (if applicable)
// 5. EXECUTE - Execute computations on retrieved data from registers / memory
// 6. UPDATE - Update register values (including NZP register) and program counter
// > Each core has it's own scheduler where multiple threads can be processed with
//   the same control flow at once.
// > Technically, different instructions can branch to different PCs, requiring "branch divergence." In
//   this minimal implementation, we assume no branch divergence (naive approach for simplicity)
module scheduler #(
        parameter THREADS_PER_BLOCK = 4
    ) (
        input wire clk,
        input wire reset,
        input wire start,

        // Control Signals
        input wire decoded_mem_read_enable,
        input wire decoded_mem_write_enable,
        input wire decoded_ret,

        // Memory Access State
        input wire [2:0] fetcher_state,
        input wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

        // Current & Next PC
        output reg [7:0] current_pc,
        input wire [7:0] next_pc [THREADS_PER_BLOCK-1:0],
        input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,
        // Execution State
        output reg [2:0] core_state,
        output reg done,

        // Cache performance statistics input
        input wire [31:0] cache_hit_count,
        input wire [31:0] cache_miss_count,
        input wire [31:0] cache_total_requests,
        input wire [31:0] cache_memory_wait_cycles
    );
    localparam IDLE = 3'b000, // Waiting to start
               FETCH = 3'b001,       // Fetch instructions from program memory
               DECODE = 3'b010,      // Decode instructions into control signals
               REQUEST = 3'b011,     // Request data from registers or memory
               WAIT = 3'b100,        // Wait for response from memory if necessary
               EXECUTE = 3'b101,     // Execute ALU and PC calculations
               UPDATE = 3'b110,      // Update registers, NZP, and PC
               DONE = 3'b111;        // Done executing this block

    // Performance counters for each pipeline stage
    reg [31:0] idle_cycles;
    reg [31:0] fetch_cycles;
    reg [31:0] decode_cycles;
    reg [31:0] request_cycles;
    reg [31:0] wait_cycles;
    reg [31:0] execute_cycles;
    reg [31:0] update_cycles;
    reg [31:0] total_cycles;
    reg [31:0] total_instructions;

    always @(posedge clk) begin
        if (reset) begin
            current_pc <= 0;
            core_state <= IDLE;
            done <= 0;
            // Reset performance counters
            idle_cycles <= 0;
            fetch_cycles <= 0;
            decode_cycles <= 0;
            request_cycles <= 0;
            wait_cycles <= 0;
            execute_cycles <= 0;
            update_cycles <= 0;
            total_cycles <= 0;
            total_instructions <= 0;
        end
        else begin
            // Increment total cycle counter
            total_cycles <= total_cycles + 1;

            // Increment stage-specific counters
            case (core_state)
                IDLE: begin
                    idle_cycles <= idle_cycles + 1;
                    // Here after reset (before kernel is launched, or after previous block has been processed)
                    if (start) begin
                        // Start by fetching the next instruction for this block based on PC
                        core_state <= FETCH;
                    end
                end
                FETCH: begin
                    fetch_cycles <= fetch_cycles + 1;
                    // Move on once fetcher_state = FETCHED
                    if (fetcher_state == 3'b010) begin
                        core_state <= DECODE;
                    end
                end
                DECODE: begin
                    decode_cycles <= decode_cycles + 1;
                    // Decode is synchronous so we move on after one cycle
                    core_state <= REQUEST;
                end
                REQUEST: begin
                    request_cycles <= request_cycles + 1;
                    // Request is synchronous so we move on after one cycle
                    core_state <= WAIT;
                end
                WAIT: begin
                    // Wait for all LSUs to finish their request before continuing
                    automatic reg any_lsu_waiting;
                    wait_cycles <= wait_cycles + 1;
                    any_lsu_waiting = 1'b0;
                    for (int i = 0; i < thread_count; i++) begin
                        // Make sure no lsu_state = REQUESTING or WAITING
                        if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin
                            any_lsu_waiting = 1'b1;
                            break;
                        end
                    end

                    // If no LSU is waiting for a response, move onto the next stage
                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end
                EXECUTE: begin
                    execute_cycles <= execute_cycles + 1;
                    // Execute is synchronous so we move on after one cycle
                    core_state <= UPDATE;
                end
                UPDATE: begin
                    update_cycles <= update_cycles + 1;
                    if (decoded_ret) begin
                        // If we reach a RET instruction, this block is done executing
                        done <= 1;
                        core_state <= DONE;
                        // Print performance statistics when done
                        $display("=== SCHEDULER PERFORMANCE STATISTICS ===");
                        $display("Total Cycles: %d", total_cycles);
                        $display("Total Instructions: %d", total_instructions);
                        $display("IDLE cycles: %d (%.1f%%)", idle_cycles, (idle_cycles * 100.0) / total_cycles);
                        $display("FETCH cycles: %d (%.1f%%)", fetch_cycles, (fetch_cycles * 100.0) / total_cycles);
                        $display("DECODE cycles: %d (%.1f%%)", decode_cycles, (decode_cycles * 100.0) / total_cycles);
                        $display("REQUEST cycles: %d (%.1f%%)", request_cycles, (request_cycles * 100.0) / total_cycles);
                        $display("WAIT cycles: %d (%.1f%%)", wait_cycles, (wait_cycles * 100.0) / total_cycles);
                        $display("EXECUTE cycles: %d (%.1f%%)", execute_cycles, (execute_cycles * 100.0) / total_cycles);
                        $display("UPDATE cycles: %d (%.1f%%)", update_cycles, (update_cycles * 100.0) / total_cycles);
                        $display("Average cycles per instruction: %.2f", total_cycles * 1.0 / total_instructions);
                        $display("--- FETCH STAGE ANALYSIS ---");
                        $display("FETCH takes %.1f%% of total time, detailed analysis:", (fetch_cycles * 100.0) / total_cycles);
                        $display("Instruction Cache Statistics:");
                        $display("- Total requests: %d", cache_total_requests);
                        $display("- Cache hits: %d", cache_hit_count);
                        $display("- Cache misses: %d", cache_miss_count);
                        if (cache_total_requests > 0) begin
                            $display("- Hit rate: %.1f%%", (cache_hit_count * 100.0) / cache_total_requests);
                            $display("- Miss rate: %.1f%%", (cache_miss_count * 100.0) / cache_total_requests);
                        end
                        $display("- Memory wait cycles: %d", cache_memory_wait_cycles);
                        $display("- Average wait per miss: %.1f cycles", cache_miss_count > 0 ? (cache_memory_wait_cycles * 1.0) / cache_miss_count : 0.0);
                        $display("========================================");
                    end
                    else begin
                        // TODO: Branch divergence. For now assume all next_pc converge
                        current_pc <= next_pc[thread_count-1];
                        total_instructions <= total_instructions + 1;

                        // Update is synchronous so we move on after one cycle
                        core_state <= FETCH;
                    end
                end
                DONE: begin
                    // no-op
                end
            endcase
        end
    end
endmodule
