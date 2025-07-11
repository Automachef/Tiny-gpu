`default_nettype none
`timescale 1ns/1ns

// ICACHE
// > Provides instruction caching functionality to reduce program memory access
// > Uses direct-mapped cache structure
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
    input wire [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data
);
    // Cache parameters
    localparam INDEX_BITS = $clog2(CACHE_SIZE);
    localparam TAG_BITS = PROGRAM_MEM_ADDR_BITS - INDEX_BITS;

    // Cache status
    reg valid [CACHE_SIZE-1:0];
    reg [TAG_BITS-1:0] tags [CACHE_SIZE-1:0];
    reg [PROGRAM_MEM_DATA_BITS-1:0] data [CACHE_SIZE-1:0];
    
    // Cache control signals
    reg [1:0] icache_state;
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
    assign index = fetcher_address[INDEX_BITS-1:0];
    assign tag = fetcher_address[PROGRAM_MEM_ADDR_BITS-1:INDEX_BITS];

    // Cache hit check
    wire icache_hit;
    assign icache_hit = valid[index] && (tags[index] == tag);

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            // Reset cache status
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                valid[i] <= 1'b0;
            end
            icache_state <= IDLE;
            fetcher_read_valid <= 1'b0;
            mem_read_valid <= 1'b0;
        end else begin
            case (icache_state)
                IDLE: begin
                    fetcher_read_valid <= 1'b0;
                    mem_read_valid <= 1'b0;

                    if (fetcher_read_request) begin
                        if (icache_hit) begin
                            // Cache hit, return data directly
                            // $display("ICACHE HIT: addr=0x%h, tag=0x%h, index=0x%h", fetcher_address, tag, index);
                            fetcher_read_data <= data[index];
                            fetcher_read_valid <= 1'b1;
                            icache_state <= IDLE;
                        end else begin
                            // Cache miss, initiate memory read request
                            // $display("ICACHE MISS: addr=0x%h, tag=0x%h, index=0x%h", fetcher_address, tag, index);
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
                    if (mem_read_ready) begin
                        // Data has returned, update cache
                        data[index] <= mem_read_data;
                        tags[index] <= tag;
                        valid[index] <= 1'b1;
                        icache_state <= UPDATE;
                    end
                end

                UPDATE: begin
                    // Provide data to Fetcher
                    // $display("ICACHE UPDATE: addr=0x%h, data=0x%h", {tag, index}, data[index]);
                    fetcher_read_data <= data[index];
                    fetcher_read_valid <= 1'b1;
                    icache_state <= IDLE;
                end
            endcase
        end
    end
endmodule