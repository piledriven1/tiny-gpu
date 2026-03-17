from typing import List, Optional
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from .memory import Memory

async def setup(
    dut, 
    program_memory: Memory, 
    program: List[int],
    data_memory: Memory,
    data: List[int],
    threads: int,
    priorities: Optional[int] = 0
):
    # Setup Clock
    clock = Clock(dut.clk, 25, units="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

    # Load Program Memory
    program_memory.load(program)

    # Load Data Memory
    data_memory.load(data)

    # Set Block Priorities (0 = all lowest priority = FIFO order)
    dut.block_priorities.value = priorities

    # Device Control Register
    dut.device_control_write_enable.value = 1
    dut.device_control_data.value = threads
    await RisingEdge(dut.clk)
    dut.device_control_write_enable.value = 0

    # Start
    dut.start.value = 1
