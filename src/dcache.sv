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
    input wire mem_write_ready
);
    // Cache parameters
    localparam INDEX_BITS = $clog2(CACHE_SIZE);
    localparam TAG_BITS = DATA_MEM_ADDR_BITS - INDEX_BITS;

    // Cache status
    reg valid [CACHE_SIZE-1:0];
    reg [TAG_BITS-1:0] tags [CACHE_SIZE-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] data [CACHE_SIZE-1:0];

    // Cache control signals - Extended to include write states
    reg [2:0] dcache_state;
    localparam IDLE = 3'b000;
    localparam MISS = 3'b001;
    localparam WAIT = 3'b010;
    localparam UPDATE = 3'b011;
    localparam WRITE = 3'b100;         // New state for write operations
    localparam WRITE_WAIT = 3'b101;    // New state for waiting for write to complete

    // Cache statistics variables
    reg [31:0] hit_count;
    reg [31:0] miss_count;
    reg [31:0] write_count;

    // Current request address decomposition
    wire [INDEX_BITS-1:0] read_index;
    wire [TAG_BITS-1:0] read_tag;
    wire [INDEX_BITS-1:0] write_index;
    wire [TAG_BITS-1:0] write_tag;

    // Extract index and tag from addresses
    assign read_index = lsu_read_address[INDEX_BITS-1:0];
    assign read_tag = lsu_read_address[DATA_MEM_ADDR_BITS-1:INDEX_BITS];
    assign write_index = lsu_write_address[INDEX_BITS-1:0];
    assign write_tag = lsu_write_address[DATA_MEM_ADDR_BITS-1:INDEX_BITS];

    // Cache hit check
    wire dcache_read_hit;
    wire dcache_write_hit;
    assign dcache_read_hit = valid[read_index] && (tags[read_index] == read_tag);
    assign dcache_write_hit = valid[write_index] && (tags[write_index] == write_tag);

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            // Reset cache status
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                valid[i] <= 1'b0;
            end
            dcache_state <= IDLE;
            lsu_read_valid <= 1'b0;
            lsu_write_valid <= 1'b0;
            mem_read_valid <= 1'b0;
            mem_write_valid <= 1'b0;
        end else begin
            case (dcache_state)
                IDLE: begin
                    lsu_read_valid <= 1'b0;
                    lsu_write_valid <= 1'b0;
                    mem_read_valid <= 1'b0;
                    mem_write_valid <= 1'b0;

                    // Check for write request first (priority over read)
                    if (lsu_write_request) begin
                        // Update cache if there's a hit (write-through)
                        if (dcache_write_hit) begin
                            // $display("DCACHE WRITE HIT: addr=0x%h, tag=0x%h, index=0x%h, data=0x%h", lsu_write_address, write_tag, write_index, lsu_write_data);
                            data[write_index] <= lsu_write_data;
                        end else begin
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
                            // Cache hit, return data directly
                            // $display("DCACHE HIT: addr=0x%h, tag=0x%h, index=0x%h", lsu_read_address, read_tag, read_index);
                            lsu_read_data <= data[read_index];
                            lsu_read_valid <= 1'b1;
                            dcache_state <= IDLE;
                        end else begin
                            // Cache miss, initiate memory read request
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
                    if (mem_read_ready) begin
                        // Data has returned, update cache
                        // $display("DCACHE UPDATE: addr=0x%h, data=0x%h", {read_tag, read_index}, mem_read_data);
                        data[read_index] <= mem_read_data;
                        tags[read_index] <= read_tag;
                        valid[read_index] <= 1'b1;
                        dcache_state <= UPDATE;
                    end
                end

                UPDATE: begin
                    // Provide data to LSU
                    lsu_read_data <= data[read_index];
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