`default_nettype none
`timescale 1ns/1ns

// REGISTER FILE
// > Each thread within each core has it's own register file with 13 free registers and 3 read-only registers
// > Read-only registers hold the familiar %blockIdx, %blockDim, and %threadIdx values critical to SIMD
module registers #(
    parameter int THREADS_PER_BLOCK = 4,
    parameter int THREAD_ID = 0,
    parameter int DATA_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some registers will be inactive

    // Kernel Execution
    input reg [7:0] block_id,

    // State
    input reg [2:0] core_state,

    // Instruction Signals
    input reg [3:0] decoded_rd_address,
    input reg [3:0] decoded_rs_address,
    input reg [3:0] decoded_rt_address,

    // Control Signals
    input reg decoded_reg_write_enable,
    input reg [1:0] decoded_reg_input_mux,
    input reg [DATA_BITS-1:0] decoded_immediate,

    // Thread Unit Outputs
    input reg [DATA_BITS-1:0] alu_out,
    input reg [DATA_BITS-1:0] lsu_out,
    input reg [DATA_BITS-1:0] dp4_out,

    // Registers
    output reg [7:0] rs,
    output reg [7:0] rt,
    output reg [7:0] rd,

    // dp4 packed outputs (4 consecutive registers packed into 32 bits)
    output reg [31:0] rs_packed,
    output reg [31:0] rt_packed
);
    localparam reg [1:0] ARITHMETIC = 2'b00,
        MEMORY = 2'b01,
        CONSTANT = 2'b10,
        DP4 = 2'b11;

    // 16 registers per thread (13 free registers and 3 read-only registers)
    reg [7:0] registers[0:15];

    always @(posedge clk) begin
        if (reset) begin
            // Empty rs, rt
            rs <= 0;
            rt <= 0;
            rd <= 0;
            rs_packed <= 32'b0;
            rt_packed <= 32'b0;
            // Initialize all free registers
            registers[0] <= 8'b0;
            registers[1] <= 8'b0;
            registers[2] <= 8'b0;
            registers[3] <= 8'b0;
            registers[4] <= 8'b0;
            registers[5] <= 8'b0;
            registers[6] <= 8'b0;
            registers[7] <= 8'b0;
            registers[8] <= 8'b0;
            registers[9] <= 8'b0;
            registers[10] <= 8'b0;
            registers[11] <= 8'b0;
            registers[12] <= 8'b0;
            // Initialize read-only registers
            registers[13] <= 8'b0;              // %blockIdx
            registers[14] <= THREADS_PER_BLOCK; // %blockDim
            registers[15] <= THREAD_ID;         // %threadIdx
        end else if (enable) begin
            // [Bad Solution] Shouldn't need to set this every cycle
            registers[13] <= block_id; // Update the block_id when a new block is issued from dispatcher

            // Fill rs/rt/rd when core_state = REQUEST
            if (core_state == 3'b011) begin
                rs <= registers[decoded_rs_address];
                rt <= registers[decoded_rt_address];
                rd <= registers[decoded_rd_address];

                // Pack 4 consecutive registers for dp4 (zero-pads if address > 12)
                rs_packed <= {registers[decoded_rs_address + 3],
                              registers[decoded_rs_address + 2],
                              registers[decoded_rs_address + 1],
                              registers[decoded_rs_address]};
                rt_packed <= {registers[decoded_rt_address + 3],
                              registers[decoded_rt_address + 2],
                              registers[decoded_rt_address + 1],
                              registers[decoded_rt_address]};
            end

            // Store rd when core_state = UPDATE
            if (core_state == 3'b110) begin
                // Only allow writing to R0 - R12
                if (decoded_reg_write_enable && decoded_rd_address < 13) begin
                    unique case (decoded_reg_input_mux)
                        ARITHMETIC: begin
                            // ADD, SUB, MUL, DIV
                            registers[decoded_rd_address] <= alu_out;
                        end
                        MEMORY: begin
                            // LDR
                            registers[decoded_rd_address] <= lsu_out;
                        end
                        CONSTANT: begin
                            // CONST
                            registers[decoded_rd_address] <= decoded_immediate;
                        end
                        DP4: begin
                            // DOT
                            registers[decoded_rd_address] <= dp4_out;
                        end
                    endcase
                end
            end
        end
    end
endmodule
