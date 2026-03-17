`default_nettype none
`timescale 1ns/1ns

// BLOCK DISPATCH
// > The GPU has one dispatch unit at the top level
// > Manages processing of threads and marks kernel execution as done
// > Sends off batches of threads in blocks to be executed by available compute cores
module dispatch #(
    parameter int NUM_CORES = 2,
    parameter int THREADS_PER_BLOCK = 4,
    parameter int MAX_BLOCKS = 16
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Kernel Metadata
    input wire [7:0] thread_count,

    // Block Priorities: 2 bits per block, packed into a single vector
    // block b's priority = block_priorities[b*2 +: 2]
    // Priority 3 (critical) is dispatched first, priority 0 (low) last
    // Default all-zero = all blocks at lowest priority = FIFO order
    input wire [2*MAX_BLOCKS-1:0] block_priorities,

    // Core States
    input reg [NUM_CORES-1:0] core_done,
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [7:0] core_block_id [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0],

    // Kernel Execution
    output reg done
);
    // Calculate the total number of blocks based on total threads & threads per block
    wire [7:0] total_blocks;
    assign total_blocks = (thread_count + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;

    // Keep track of how many blocks have been processed
    reg [MAX_BLOCKS-1:0] blocks_dispatched; // How many blocks have been sent to cores?
    reg [MAX_BLOCKS-1:0] blocks_done; // How many blocks have finished processing?
    reg start_execution; // EDA: Unimportant hack used because of EDA tooling

    reg [7:0] sel_block_id;
    reg sel_block_found;

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            blocks_dispatched = 0;
            blocks_done = 0;
            start_execution <= 0;

            for (int i = 0; i < NUM_CORES; i++) begin
                core_start[i] <= 0;
                core_reset[i] <= 1;
                core_block_id[i] <= 0;
                core_thread_count[i] <= THREADS_PER_BLOCK;
            end
        end else if (start) begin
            // EDA: Indirect way to get @(posedge start) without driving from 2 different clocks
            if (!start_execution) begin
                start_execution <= 1;
                for (int i = 0; i < NUM_CORES; i++) begin
                    core_reset[i] <= 1;
                end
            end

            // If the last block has finished processing, mark this kernel as done executing
            if (blocks_done == total_blocks) begin
                done <= 1;
            end

            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_reset[i]) begin
                    core_reset[i] <= 0;

                    // Priority selection: scan from priority 3 (critical) down to 0 (low)
                    // Within each priority level, pick the lowest-numbered undispatched block
                    sel_block_id = 0;
                    sel_block_found = 0;

                    for (int p = 3; p >= 0; p = p - 1) begin
                        for (int b = 0; b < MAX_BLOCKS; b = b + 1) begin
                            if (!sel_block_found &&
                                b < total_blocks &&
                                !blocks_dispatched[b] &&
                                block_priorities[b*2 +: 2] == p[1:0]) begin
                                sel_block_id = b[7:0];
                                sel_block_found = 1;
                            end
                        end
                    end

                    if (sel_block_found) begin
                        core_start[i] <= 1;
                        core_block_id[i] <= sel_block_id;
                        core_thread_count[i] <=
                            (sel_block_id == total_blocks - 1) ?
                            thread_count - (sel_block_id * THREADS_PER_BLOCK) :
                                THREADS_PER_BLOCK;

                        // Blocking assignment: next core in this cycle sees updated mask
                        blocks_dispatched[sel_block_id] = 1;
                    end
                end
            end

            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_start[i] && core_done[i]) begin
                    // If a core just finished executing it's current block, reset it
                    core_reset[i] <= 1;
                    core_start[i] <= 0;
                    blocks_done = blocks_done + 1;
                end
            end
        end
    end
endmodule
