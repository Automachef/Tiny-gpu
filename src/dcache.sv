`default_nettype none
`timescale 1ns/1ns

// DATA CACHE
// > Provides data caching functionality to reduce data memory access
// > Uses direct-mapped cache structure
// > Each core has its own data cache
// > This implementation is read-only
module dcache #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 8,
    parameter CACHE_SIZE = 32          // Number of cache lines, must be a power of 2
) (
    input wire clk,
    input wire reset,

    // LSU side interface
    input wire [DATA_MEM_ADDR_BITS-1:0] lsu_read_address,
    input wire lsu_read_request,
    output reg lsu_read_valid,
    output reg [DATA_MEM_DATA_BITS-1:0] lsu_read_data,

    // Memory Controller side interface
    output reg mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_MEM_DATA_BITS-1:0] mem_read_data
);
    // Cache parameters
    localparam INDEX_BITS = $clog2(CACHE_SIZE);
    localparam TAG_BITS = DATA_MEM_ADDR_BITS - INDEX_BITS;

    // Cache status
    reg valid [CACHE_SIZE-1:0];
    reg [TAG_BITS-1:0] tags [CACHE_SIZE-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] data [CACHE_SIZE-1:0];

    // Cache control signals
    reg [1:0] dcache_state;
    localparam IDLE = 2'b00;
    localparam MISS = 2'b01;
    localparam WAIT = 2'b10;
    localparam UPDATE = 2'b11;

    // Cache statistics variables
    reg [31:0] hit_count;
    reg [31:0] miss_count;

    // Current request address decomposition
    wire [INDEX_BITS-1:0] index;
    wire [TAG_BITS-1:0] tag;

    // Extract index and tag from address
    assign index = lsu_read_address[INDEX_BITS-1:0];
    assign tag = lsu_read_address[DATA_MEM_ADDR_BITS-1:INDEX_BITS];

    // Cache hit check
    wire dcache_hit;
    assign dcache_hit = valid[index] && (tags[index] == tag);

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            // Reset cache status
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                valid[i] <= 1'b0;
            end
            dcache_state <= IDLE;
            lsu_read_valid <= 1'b0;
            mem_read_valid <= 1'b0;
        end else begin
            case (dcache_state)
                IDLE: begin
                    lsu_read_valid <= 1'b0;
                    mem_read_valid <= 1'b0;

                    if (lsu_read_request) begin
                        if (dcache_hit) begin
                            // Cache hit, return data directly
                            // $display("DCACHE HIT: addr=0x%h, tag=0x%h, index=0x%h", lsu_read_address, tag, index);
                            lsu_read_data <= data[index];
                            lsu_read_valid <= 1'b1;
                            dcache_state <= IDLE;   
                        end else begin
                            // Cache miss, initiate memory read request
                            // $display("DCACHE MISS: addr=0x%h, tag=0x%h, index=0x%h", lsu_read_address, tag, index);
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
                        // $display("DCACHE UPDATE: addr=0x%h, data=0x%h", {tag, index}, mem_read_data);
                        data[index] <= mem_read_data;
                        tags[index] <= tag;
                        valid[index] <= 1'b1;
                        dcache_state <= UPDATE;                        
                    end
                end

                UPDATE: begin
                    // Provide data to LSU
                    lsu_read_data <= data[index];
                    lsu_read_valid <= 1'b1;
                    dcache_state <= IDLE;
                end
            endcase
        end
    end
endmodule
