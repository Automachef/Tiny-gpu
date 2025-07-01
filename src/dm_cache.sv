module dm_cache #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 8,
    parameter INDEX_BITS = 3,
    parameter OFFSET_BITS = 2
) (
    input wire clk,
    input wire reset,

    // Only support one consumer, one channel by now,
    // TODO: Support multiple consumers, multiple channels in the future.

    // Consumer Interface (Fetchers / LSUs)
    input wire consumer_read_valid,
    input wire [ADDR_BITS-1:0] consumer_read_address,
    output reg consumer_read_ready,
    output reg [DATA_BITS-1:0] consumer_read_data,
    input wire consumer_write_valid,
    input wire [ADDR_BITS-1:0] consumer_write_address,
    input wire [DATA_BITS-1:0] consumer_write_data,
    output reg consumer_write_ready,

    // Memory Interface (Data / Program)
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data,
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [DATA_BITS-1:0] mem_write_data,
    input wire mem_write_ready
);

localparam TAG_BITS = ADDR_BITS - INDEX_BITS - OFFSET_BITS;
localparam NUM_BLOCKS = 1 << INDEX_BITS; // the number of blocks in cache memory
localparam NUM_DATA = 1 << OFFSET_BITS; // the number of data in one block

typedef struct{
    reg valid;
    reg dirty;
    reg [TAG_BITS-1:0] tag;
    reg [DATA_BITS-1:0] data [0:NUM_DATA-1];
} cache_block;

cache_block cache_mem [0:NUM_BLOCKS-1];

// Only support read by now
// TODO: Support both read and write in the future

reg [DATA_BITS-1:0] read_data_temp [0:NUM_DATA-1];

localparam READ_IDLE = 3'h0;
localparam READ_CHECK = 3'h1;
localparam READ_HIT = 3'h2;
localparam READ_MEM = 3'h3;
localparam READ_MEM_DONE = 3'h4;

reg [2:0] read_state;

always @(posedge clk) begin
    if (reset) begin
      read_state <= READ_IDLE;
      consumer_read_ready <= 1'b0;
      mem_read_valid <= 1'b0;
        for(int i = 0; i < NUM_BLOCKS; i += 1) begin
            cache_mem[i].valid <= 0;
            cache_mem[i].dirty <= 0;
            cache_mem[i].tag <= 0;
            for (int j = 0; j < NUM_DATA; j += 1) begin
              cache_mem[i].data[j] <= 0;
            end
        end
        for (int j = 0; j < NUM_DATA-1; j += 1) begin
            read_data_temp[j] = 0;
        end
    end
    else begin
        case (read_state)
            READ_IDLE: begin
                if (consumer_read_valid) begin
                    read_state <= READ_CHECK;
                end
            end
            READ_CHECK: begin
                automatic reg [TAG_BITS-1:0] tag = consumer_read_address[ADDR_BITS-1:INDEX_BITS+OFFSET_BITS];
                automatic reg [INDEX_BITS-1:0] index = consumer_read_address[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
                automatic reg [OFFSET_BITS-1:0] offset = consumer_read_address[OFFSET_BITS-1:0];
                if ((cache_mem[index].valid) && (tag == cache_mem[index].tag)) begin
                    read_state <= READ_HIT;
                    consumer_read_ready <= 1'b1;
                    consumer_read_data <= cache_mem[index].data[offset];
                end
                else begin
                    read_state <= READ_MEM;
                    mem_read_valid <= 1'b1;
                    mem_read_address <= {consumer_read_address[ADDR_BITS-1:OFFSET_BITS], {OFFSET_BITS{1'b0}} };
                    for (int j = 0; j < NUM_DATA; j += 1) begin
                        read_data_temp[j] <= 0;
                    end
                end
            end
            READ_HIT: begin
                read_state <= READ_IDLE;
                consumer_read_ready <= 1'b0;
            end
            READ_MEM: begin
                if (mem_read_ready) begin
                    automatic reg [OFFSET_BITS-1:0] mem_offset = mem_read_address[OFFSET_BITS-1:0];
                    if (&mem_offset) begin
                        mem_read_valid <= 1'b0;
                        read_state <= READ_MEM_DONE;
                    end
                    else begin
                        mem_read_address[OFFSET_BITS-1:0] <= mem_read_address[OFFSET_BITS-1:0] + 1'b1;
                    end
                    read_data_temp[mem_offset] <= mem_read_data;
                    if (mem_offset == consumer_read_address[OFFSET_BITS-1:0]) begin
                        consumer_read_ready <= 1'b1;
                        consumer_read_data <= mem_read_data;
                    end
                end
                if (consumer_read_ready) begin
                    consumer_read_ready <= 1'b0;
                end
            end
            READ_MEM_DONE: begin
                automatic reg [TAG_BITS-1:0] tag = consumer_read_address[ADDR_BITS-1:INDEX_BITS+OFFSET_BITS];
                automatic reg [INDEX_BITS-1:0] index = consumer_read_address[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
                read_state <= READ_IDLE;
                cache_mem[index].valid <= 1'b1;
                cache_mem[index].dirty <= 1'b0;
                cache_mem[index].tag <= tag;
                for (int j = 0; j < NUM_DATA; j += 1) begin
                    cache_mem[index].data[j] <= read_data_temp[j];
                end
                if (consumer_read_ready) begin
                    consumer_read_ready <= 1'b0;
                end
            end
        endcase
    end
end

endmodule
