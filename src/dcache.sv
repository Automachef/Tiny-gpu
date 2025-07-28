`default_nettype none
`timescale 1ns/1ns

// DATA CACHE
// > Provides data caching functionality to reduce data memory access
// > Uses direct-mapped cache structure
// > Each core has its own data cache
// > Now supports both read and write operations with write-through policy
module dcache #(
        parameter DATA_MEM_ADDR_BITS = 8,
        parameter DATA_MEM_DATA_BITS = 8,
        parameter CACHE_SIZE = 32          // Number of cache lines, must be a power of 2
    ) (
        input wire clk,
        input wire reset,

        // LSU side interface - Read
        input wire [DATA_MEM_ADDR_BITS-1:0] lsu_read_address,
        input wire lsu_read_request,
        output reg lsu_read_valid,
        output reg [DATA_MEM_DATA_BITS-1:0] lsu_read_data,

        // LSU side interface - Write (new)
        input wire [DATA_MEM_ADDR_BITS-1:0] lsu_write_address,
        input wire lsu_write_request,
        input wire [DATA_MEM_DATA_BITS-1:0] lsu_write_data,
        output reg lsu_write_valid,

        // Memory Controller side interface - Read
        output reg mem_read_valid,
        output reg [DATA_MEM_ADDR_BITS-1:0] mem_read_address,
        input wire mem_read_ready,
        input wire [DATA_MEM_DATA_BITS-1:0] mem_read_data,

        // Memory Controller side interface - Write
        output reg mem_write_valid,
        output reg [DATA_MEM_ADDR_BITS-1:0] mem_write_address,
        output reg [DATA_MEM_DATA_BITS-1:0] mem_write_data,
        input wire mem_write_ready,

        // Performance statistics output
        output wire [31:0] dcache_read_hits,
        output wire [31:0] dcache_read_misses,
        output wire [31:0] dcache_write_requests,
        output wire [31:0] dcache_memory_wait_cycles
    );
    // Cache parameters for 2-way set associative
    localparam WAYS = 2;                                    // 2-way set associative
    localparam SETS = CACHE_SIZE / WAYS;                    // Number of sets
    localparam INDEX_BITS = $clog2(SETS);                  // Bits for set index
    localparam TAG_BITS = DATA_MEM_ADDR_BITS - INDEX_BITS; // Bits for tag

    // Cache storage - 2-way set associative
    reg valid [WAYS-1:0][SETS-1:0];                        // Valid bits for each way
    reg [TAG_BITS-1:0] tags [WAYS-1:0][SETS-1:0];         // Tags for each way
    reg [DATA_MEM_DATA_BITS-1:0] data [WAYS-1:0][SETS-1:0]; // Data for each way

    // LRU replacement policy - 1 bit per set (0=way0 LRU, 1=way1 LRU)
    reg lru [SETS-1:0];

    // Cache control signals - Extended to include write states
    reg [2:0] dcache_state;
    localparam IDLE = 3'b000;
    localparam MISS = 3'b001;
    localparam WAIT = 3'b010;
    localparam UPDATE = 3'b011;
    localparam WRITE = 3'b100;         // New state for write operations
    localparam WRITE_WAIT = 3'b101;    // New state for waiting for write to complete

    // Cache statistics variables
    reg [31:0] read_hit_count;
    reg [31:0] read_miss_count;
    reg [31:0] write_count;
    reg [31:0] memory_wait_cycles;

    // Assign performance statistics to output ports
    assign dcache_read_hits = read_hit_count;
    assign dcache_read_misses = read_miss_count;
    assign dcache_write_requests = write_count;
    assign dcache_memory_wait_cycles = memory_wait_cycles;

    // Current request address decomposition
    wire [INDEX_BITS-1:0] read_set_index, write_set_index;
    wire [TAG_BITS-1:0] read_tag, write_tag;

    // Extract set index and tag from address
    assign read_set_index = lsu_read_address[INDEX_BITS-1:0];
    assign read_tag = lsu_read_address[DATA_MEM_ADDR_BITS-1:INDEX_BITS];
    assign write_set_index = lsu_write_address[INDEX_BITS-1:0];
    assign write_tag = lsu_write_address[DATA_MEM_ADDR_BITS-1:INDEX_BITS];

    // Cache hit check for 2-way set associative
    wire read_way0_hit, read_way1_hit, write_way0_hit, write_way1_hit;
    wire dcache_read_hit, dcache_write_hit;
    wire read_hit_way, write_hit_way;  // Which way hit (0 or 1)

    assign read_way0_hit = valid[0][read_set_index] && (tags[0][read_set_index] == read_tag);
    assign read_way1_hit = valid[1][read_set_index] && (tags[1][read_set_index] == read_tag);
    assign dcache_read_hit = read_way0_hit || read_way1_hit;
    assign read_hit_way = read_way1_hit;  // 0 if way0 hit, 1 if way1 hit

    assign write_way0_hit = valid[0][write_set_index] && (tags[0][write_set_index] == write_tag);
    assign write_way1_hit = valid[1][write_set_index] && (tags[1][write_set_index] == write_tag);
    assign dcache_write_hit = write_way0_hit || write_way1_hit;
    assign write_hit_way = write_way1_hit;  // 0 if way0 hit, 1 if way1 hit

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            // Reset cache status for 2-way set associative
            for (i = 0; i < SETS; i = i + 1) begin
                valid[0][i] <= 1'b0;
                valid[1][i] <= 1'b0;
                lru[i] <= 1'b0;  // Initialize LRU bits
            end
            dcache_state <= IDLE;
            lsu_read_valid <= 1'b0;
            lsu_write_valid <= 1'b0;
            mem_read_valid <= 1'b0;
            mem_write_valid <= 1'b0;
            // Reset performance statistics
            read_hit_count <= 0;
            read_miss_count <= 0;
            write_count <= 0;
            memory_wait_cycles <= 0;
        end
        else begin
            case (dcache_state)
                IDLE: begin
                    lsu_read_valid <= 1'b0;
                    lsu_write_valid <= 1'b0;
                    mem_read_valid <= 1'b0;
                    mem_write_valid <= 1'b0;

                    // Check for write request first (priority over read)
                    if (lsu_write_request) begin
                        // Update cache if there's a hit (write-through)
                        write_count <= write_count + 1;
                        if (dcache_write_hit) begin
                            // Update cache in the hitting way (write-through policy)
                            // Update LRU: mark the other way as LRU
                            lru[write_set_index] <= ~write_hit_way;
                            // $display("DCACHE WRITE HIT: addr=0x%h, way=%d", lsu_write_address, write_hit_way);
                            if (write_hit_way) begin
                                data[1][write_set_index] <= lsu_write_data;
                            end
                            else begin
                                data[0][write_set_index] <= lsu_write_data;
                            end
                        end
                        else begin
                            // $display("DCACHE WRITE MISS: addr=0x%h, tag=0x%h, index=0x%h, data=0x%h",lsu_write_address, write_tag, write_index, lsu_write_data);
                            // For write miss in write-through, we don't need to allocate a cache line
                            // Just write directly to memory
                        end

                        // Always write to memory (write-through policy)
                        // $display("DCACHE MEMORY WRITE: addr=0x%h, data=0x%h", lsu_write_address, lsu_write_data);
                        mem_write_valid <= 1'b1;
                        mem_write_address <= lsu_write_address;
                        mem_write_data <= lsu_write_data;
                        dcache_state <= WRITE;
                    end
                    // Check for read request if no write request
                    else if (lsu_read_request) begin
                        if (dcache_read_hit) begin
                            // Cache hit, return data from the hitting way
                            read_hit_count <= read_hit_count + 1;
                            // Update LRU: mark the other way as LRU
                            lru[read_set_index] <= ~read_hit_way;
                            // $display("DCACHE HIT: addr=0x%h, way=%d", lsu_read_address, read_hit_way);
                            lsu_read_data <= read_hit_way ? data[1][read_set_index] : data[0][read_set_index];
                            lsu_read_valid <= 1'b1;
                            dcache_state <= IDLE;
                        end
                        else begin
                            // Cache miss, initiate memory read request
                            read_miss_count <= read_miss_count + 1;
                            // $display("DCACHE MISS: addr=0x%h, tag=0x%h, index=0x%h", lsu_read_address, read_tag, read_index);
                            mem_read_address <= lsu_read_address;
                            mem_read_valid <= 1'b1;
                            dcache_state <= MISS;
                        end
                    end
                end

                MISS: begin
                    if (mem_read_ready) begin
                        // Memory request has been accepted, waiting for data return
                        mem_read_valid <= 1'b0;
                        dcache_state <= WAIT;
                    end
                end

                WAIT: begin
                    memory_wait_cycles <= memory_wait_cycles + 1;
                    if (mem_read_ready) begin
                        // Data has returned, update cache using LRU replacement
                        automatic reg replace_way;
                        replace_way = lru[read_set_index];  // LRU way to replace

                        data[replace_way][read_set_index] <= mem_read_data;
                        tags[replace_way][read_set_index] <= read_tag;
                        valid[replace_way][read_set_index] <= 1'b1;

                        // Update LRU: mark the other way as LRU
                        lru[read_set_index] <= ~replace_way;

                        dcache_state <= UPDATE;
                    end
                end

                UPDATE: begin
                    // Provide data to LSU from the way that was just updated
                    automatic reg updated_way;
                    updated_way = ~lru[read_set_index];  // The way that was just updated (opposite of current LRU)
                    // $display("DCACHE UPDATE: addr=0x%h, way=%d", lsu_read_address, updated_way);
                    lsu_read_data <= data[updated_way][read_set_index];
                    lsu_read_valid <= 1'b1;
                    dcache_state <= IDLE;
                end

                WRITE: begin
                    // Wait for memory controller to acknowledge the write request
                    if (mem_write_ready) begin
                        // Write-through operation statistics
                        // $display("DCACHE WRITE-THROUGH: state=memory_update, addr=0x%h, data=0x%h", mem_write_address, mem_write_data);
                        mem_write_valid <= 1'b0;
                        dcache_state <= WRITE_WAIT;
                    end
                end

                WRITE_WAIT: begin
                    // Write operation is complete, notify LSU
                    lsu_write_valid <= 1'b1;
                    dcache_state <= IDLE;
                end
            endcase
        end
    end
endmodule
