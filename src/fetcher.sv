`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > Retrieves the instruction at the current PC from program memory via instruction cache
// > Each core has its own fetcher and instruction cache
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter CACHE_SIZE = 16  // Cache size, must be a power of 2
) (
    input wire clk,
    input wire reset,

    // Execution State
    input wire [2:0] core_state,
    input wire [7:0] current_pc,

    // Program Memory (connects to memory through cache)
    output wire mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher Output
    output reg [2:0] fetcher_state,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction
);
    localparam IDLE = 3'b000,
        FETCHING = 3'b001,
        FETCHED = 3'b010;

    // Interface between instruction cache and fetcher
    reg cache_read_request;
    wire cache_read_valid;
    wire [PROGRAM_MEM_DATA_BITS-1:0] cache_read_data;

    // Instantiate instruction cache
    icache #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .CACHE_SIZE(CACHE_SIZE)
    ) icache (
        .clk(clk),
        .reset(reset),

        // Fetcher side interface
        .fetcher_address(current_pc),
        .fetcher_read_request(cache_read_request),
        .fetcher_read_valid(cache_read_valid),
        .fetcher_read_data(cache_read_data),

        // Memory side interface
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data)
    );

    always @(posedge clk) begin
        if (reset) begin
            fetcher_state <= IDLE;
            cache_read_request <= 0;
            instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
        end else begin
            case (fetcher_state)
                IDLE: begin
                    // Start fetching when core_state = FETCH
                    if (core_state == 3'b001) begin
                        fetcher_state <= FETCHING;
                        cache_read_request <= 1;  // Request instruction through cache
                    end
                end
                FETCHING: begin
                    // Once the request is sent, turn off the request signal
                    cache_read_request <= 0;

                    // Wait for cache to return data
                    if (cache_read_valid) begin
                        fetcher_state <= FETCHED;
                        instruction <= cache_read_data;  // Fetch instruction from cache
                    end
                end
                FETCHED: begin
                    // Reset when core_state = DECODE
                    if (core_state == 3'b010) begin
                        fetcher_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule