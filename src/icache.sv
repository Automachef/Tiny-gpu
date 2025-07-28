`default_nettype none
`timescale 1ns/1ns

// ICACHE - 2-Way Set Associative with LRU Replacement
// > Provides instruction caching functionality to reduce program memory access
// > Uses 2-way set associative cache structure with LRU replacement
// > Each core has its own instruction cache
module icache #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter CACHE_SIZE = 16          // Number of cache lines, must be a power of 2
) (
    input wire clk,
    input wire reset,

    // Fetcher side interface
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_address,
    input wire fetcher_read_request,
    output reg fetcher_read_valid,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data,

    // Program Memory side interface
    output reg mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Performance statistics output
    output wire [31:0] cache_hit_count,
    output wire [31:0] cache_miss_count,
    output wire [31:0] cache_total_requests,
    output wire [31:0] cache_memory_wait_cycles
);
    // Cache parameters for 2-way set associative
    localparam WAYS = 2;                                    // 2-way set associative
    localparam SETS = CACHE_SIZE / WAYS;                    // Number of sets
    localparam INDEX_BITS = $clog2(SETS);                  // Bits for set index
    localparam TAG_BITS = PROGRAM_MEM_ADDR_BITS - INDEX_BITS; // Bits for tag

    // Cache storage - 2-way set associative
    reg valid [WAYS-1:0][SETS-1:0];                        // Valid bits for each way
    reg [TAG_BITS-1:0] tags [WAYS-1:0][SETS-1:0];         // Tags for each way
    reg [PROGRAM_MEM_DATA_BITS-1:0] data [WAYS-1:0][SETS-1:0]; // Data for each way
    
    // LRU replacement policy - 1 bit per set (0=way0 LRU, 1=way1 LRU)
    reg lru [SETS-1:0];

    // Cache control signals
    reg [1:0] icache_state;
    localparam IDLE = 2'b00;
    localparam MISS = 2'b01;
    localparam WAIT = 2'b10;
    localparam UPDATE = 2'b11;
    
    // Cache statistics variables
    reg [31:0] hit_count;
    reg [31:0] miss_count;
    reg [31:0] total_requests;
    reg [31:0] memory_wait_cycles;

    // Current request address decomposition
    wire [INDEX_BITS-1:0] set_index;
    wire [TAG_BITS-1:0] tag;

    // Extract set index and tag from address
    assign set_index = fetcher_address[INDEX_BITS-1:0];
    assign tag = fetcher_address[PROGRAM_MEM_ADDR_BITS-1:INDEX_BITS];

    // Cache hit check for 2-way set associative
    wire way0_hit, way1_hit;
    wire icache_hit;
    wire hit_way;  // Which way hit (0 or 1)
    
    assign way0_hit = valid[0][set_index] && (tags[0][set_index] == tag);
    assign way1_hit = valid[1][set_index] && (tags[1][set_index] == tag);
    assign icache_hit = way0_hit || way1_hit;
    assign hit_way = way1_hit;  // 0 if way0 hit, 1 if way1 hit

    // Assign performance statistics to output ports
    assign cache_hit_count = hit_count;
    assign cache_miss_count = miss_count;
    assign cache_total_requests = total_requests;
    assign cache_memory_wait_cycles = memory_wait_cycles;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            // Reset cache status for 2-way set associative
            for (i = 0; i < SETS; i = i + 1) begin
                valid[0][i] <= 1'b0;
                valid[1][i] <= 1'b0;
                lru[i] <= 1'b0;  // Initialize LRU bits
            end
            icache_state <= IDLE;
            fetcher_read_valid <= 1'b0;
            mem_read_valid <= 1'b0;
            // Reset statistics
            hit_count <= 0;
            miss_count <= 0;
            total_requests <= 0;
            memory_wait_cycles <= 0;
        end else begin
            case (icache_state)
                IDLE: begin
                    fetcher_read_valid <= 1'b0;
                    mem_read_valid <= 1'b0;

                    if (fetcher_read_request) begin
                        total_requests <= total_requests + 1;
                        if (icache_hit) begin
                            // Cache hit, return data from the hitting way
                            hit_count <= hit_count + 1;
                            // Update LRU: mark the other way as LRU
                            lru[set_index] <= ~hit_way;
                            // $display("ICACHE HIT: addr=0x%h, way=%d", fetcher_address, hit_way);
                            fetcher_read_data <= hit_way ? data[1][set_index] : data[0][set_index];
                            fetcher_read_valid <= 1'b1;
                            icache_state <= IDLE;
                        end
                        else begin
                            // Cache miss, initiate memory read request
                            miss_count <= miss_count + 1;
                            // $display("ICACHE MISS: addr=0x%h", fetcher_address);
                            mem_read_address <= fetcher_address;
                            mem_read_valid <= 1'b1;
                            icache_state <= MISS;
                        end
                    end
                end

                MISS: begin
                    if (mem_read_ready) begin
                        // Memory request has been accepted, waiting for data return
                        mem_read_valid <= 1'b0;
                        icache_state <= WAIT;
                    end
                end

                WAIT: begin
                    memory_wait_cycles <= memory_wait_cycles + 1;
                    if (mem_read_ready) begin
                        // Data has returned, update cache using LRU replacement
                        automatic reg replace_way;
                        replace_way = lru[set_index];  // LRU way to replace
                        
                        data[replace_way][set_index] <= mem_read_data;
                        tags[replace_way][set_index] <= tag;
                        valid[replace_way][set_index] <= 1'b1;
                        
                        // Update LRU: mark the other way as LRU
                        lru[set_index] <= ~replace_way;
                        
                        icache_state <= UPDATE;
                    end
                end

                UPDATE: begin
                    // Provide data to Fetcher from the way that was just updated
                    automatic reg updated_way;
                    updated_way = ~lru[set_index];  // The way that was just updated (opposite of current LRU)
                    // $display("ICACHE UPDATE: addr=0x%h, way=%d", fetcher_address, updated_way);
                    fetcher_read_data <= data[updated_way][set_index];
                    fetcher_read_valid <= 1'b1;
                    icache_state <= IDLE;
                end
            endcase
        end
    end
endmodule
