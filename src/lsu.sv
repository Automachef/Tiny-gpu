`default_nettype none
`timescale 1ns/1ns

// LOAD-STORE UNIT
// > Handles asynchronous memory load and store operations and waits for response
// > Each thread in each core has it's own LSU
// > LDR, STR instructions are executed here
module lsu (
        input wire clk,
        input wire reset,
        input wire enable, // If current block has less threads then block size, some LSUs will be inactive

        // State
        input wire [2:0] core_state,

        // Memory Control Signals
        input wire decoded_mem_read_enable,
        input wire decoded_mem_write_enable,

        // Registers
        input wire [7:0] rs,
        input wire [7:0] rt,

        // Data Memory
        output reg mem_read_valid,
        output reg [7:0] mem_read_address,
        input wire mem_read_ready,
        input wire [7:0] mem_read_data,
        output reg mem_write_valid,
        output reg [7:0] mem_write_address,
        output reg [7:0] mem_write_data,
        input wire mem_write_ready,

        // LSU Outputs
        output reg [1:0] lsu_state,
        output reg [7:0] lsu_out,

        // Performance statistics output
        output wire [31:0] lsu_read_requests,
        output wire [31:0] lsu_write_requests,
        output wire [31:0] lsu_wait_cycles
    );
    localparam IDLE = 2'b00, REQUESTING = 2'b01, WAITING = 2'b10, DONE = 2'b11;

    // Performance statistics variables
    reg [31:0] read_requests;
    reg [31:0] write_requests;
    reg [31:0] wait_cycles;

    // Assign performance statistics to output ports
    assign lsu_read_requests = read_requests;
    assign lsu_write_requests = write_requests;
    assign lsu_wait_cycles = wait_cycles;

    always @(posedge clk) begin
        if (reset) begin
            lsu_state <= IDLE;
            lsu_out <= 0;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;
            // Reset performance statistics
            read_requests <= 0;
            write_requests <= 0;
            wait_cycles <= 0;
        end
        else if (enable) begin
            // If memory read enable is triggered (LDR instruction)
            if (decoded_mem_read_enable) begin
                case (lsu_state)
                    IDLE: begin
                        // Only read when core_state = REQUEST
                        if (core_state == 3'b011) begin
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin
                        mem_read_valid <= 1;
                        mem_read_address <= rs;
                        read_requests <= read_requests + 1;
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        wait_cycles <= wait_cycles + 1;
                        if (mem_read_ready == 1) begin
                            mem_read_valid <= 0;
                            lsu_out <= mem_read_data;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin
                        // Reset when core_state = UPDATE
                        if (core_state == 3'b110) begin
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end

            // If memory write enable is triggered (STR instruction)
            if (decoded_mem_write_enable) begin
                case (lsu_state)
                    IDLE: begin
                        // Only read when core_state = REQUEST
                        if (core_state == 3'b011) begin
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin
                        mem_write_valid <= 1;
                        mem_write_address <= rs;
                        mem_write_data <= rt;
                        write_requests <= write_requests + 1;
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        wait_cycles <= wait_cycles + 1;
                        if (mem_write_ready) begin
                            mem_write_valid <= 0;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin
                        // Reset when core_state = UPDATE
                        if (core_state == 3'b110) begin
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule

