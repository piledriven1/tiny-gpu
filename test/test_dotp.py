import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

@cocotb.test()
async def test_matmul_dot(dut):
    # 2x2 Matrix Multiplication using the DOT instruction
    #
    # A = [[1, 2],   B = [[5, 6],   C = A x B = [[19, 22],
    #      [3, 4]]        [7, 8]]                 [43, 50]]
    #
    # Memory layout:
    #   A row-major at 0-3:    [1, 2, 3, 4]
    #   B column-major at 4-7: [5, 7, 6, 8]   (col0=[5,7], col1=[6,8])
    #   C output at 8-11
    #
    # Each thread i computes C[row][col] where row=i/2, col=i%2
    # Loads A row into R1,R2 and B column into R5,R6
    # R3,R4,R7,R8 stay zero from reset → dp4 zero-pads unused lanes
    # DOT R9, R1, R5 computes R1*R5 + R2*R6 + R3*R7 + R4*R8

    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    program = [
        # i = blockIdx * blockDim + threadIdx
        0b0101101011011110, # MUL R10, %blockIdx, %blockDim
        0b0011101010101111, # ADD R10, R10, %threadIdx

        # row = i / N, col = i % N
        0b1001101100000010, # CONST R11, #2
        0b0110110010101011, # DIV R12, R10, R11              ; row = i / 2
        0b0101100111001011, # MUL R9, R12, R11               ; row * N
        0b0100100110101001, # SUB R9, R10, R9                ; col = i - row*N

        # Load A[row*N], A[row*N+1] into R1, R2
        0b0101000111001011, # MUL R1, R12, R11               ; R1 = row * N
        0b1001101100000001, # CONST R11, #1
        0b0011001000011011, # ADD R2, R1, R11                ; R2 = row*N + 1
        0b0111000100010000, # LDR R1, R1                     ; R1 = A[row*N]
        0b0111001000100000, # LDR R2, R2                     ; R2 = A[row*N+1]

        # Load B[baseB+col*N], B[baseB+col*N+1] into R5, R6
        0b1001101100000010, # CONST R11, #2
        0b0101010110011011, # MUL R5, R9, R11                ; R5 = col * N
        0b1001101100000100, # CONST R11, #4                  ; baseB
        0b0011010101011011, # ADD R5, R5, R11                ; R5 = baseB + col*N
        0b1001101100000001, # CONST R11, #1
        0b0011011001011011, # ADD R6, R5, R11                ; R6 = baseB + col*N + 1
        0b0111010101010000, # LDR R5, R5                     ; R5 = B_col[0]
        0b0111011001100000, # LDR R6, R6                     ; R6 = B_col[1]

        # Dot product: dp4({R4,R3,R2,R1}, {R8,R7,R6,R5}) → R9
        0b1010100100010101, # DOT R9, R1, R5

        # Store result at baseC + i
        0b1001101100001000, # CONST R11, #8                  ; baseC
        0b0011101110111010, # ADD R11, R11, R10              ; baseC + i
        0b1000000010111001, # STR R11, R9

        0b1111000000000000  # RET
    ]

    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [
        1, 2, 3, 4,    # Matrix A (2x2 row-major)
        5, 7, 6, 8,    # Matrix B (2x2 column-major): col0=[5,7], col1=[6,8]
    ]

    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    data_memory.display(12)

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        format_cycle(dut, cycles)

        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(12)

    # Verify C = A x B
    expected = [19, 22, 43, 50]
    for i, exp in enumerate(expected):
        result = data_memory.memory[i + 8]
        assert result == exp, f"C[{i//2},{i%2}]: expected {exp}, got {result}"

    logger.info("All results correct!")
    logger.info(f"C = {[data_memory.memory[8+i] for i in range(4)]}")
