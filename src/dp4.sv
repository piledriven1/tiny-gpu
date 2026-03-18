`timescale 1ns/1ns

// 4-LANE DOT PRODUCT
// > Purely combinational: computes a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]
// > Each input packs four 8-bit unsigned values into a 32-bit word
// > Unused lanes should be zero-padded (0 * x = 0, contributes nothing)
module dp4 (
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] result
);

    // Extract 8-bit lanes
    logic [7:0] a0, a1, a2, a3;
    logic [7:0] b0, b1, b2, b3;

    assign a0 = a[7:0];
    assign a1 = a[15:8];
    assign a2 = a[23:16];
    assign a3 = a[31:24];

    assign b0 = b[7:0];
    assign b1 = b[15:8];
    assign b2 = b[23:16];
    assign b3 = b[31:24];

    // Intermediate products (wider to avoid overflow)
    logic [15:0] p0, p1, p2, p3;

    assign p0 = a0 * b0;
    assign p1 = a1 * b1;
    assign p2 = a2 * b2;
    assign p3 = a3 * b3;

    // Accumulate (adder tree)
    logic [16:0] sum0, sum1;
    logic [17:0] final_sum;

    assign sum0 = p0 + p1;
    assign sum1 = p2 + p3;
    assign final_sum = sum0 + sum1;

    // Output (extend to 32 bits)
    assign result = {14'b0, final_sum};

endmodule
