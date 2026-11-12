# dmem — Data Memory

**File:** `rtl/dmem.v`
**Owner:** Jagruthi Pulumati (Role 3, Control and Memory)

---

## What it does

`dmem` is the data memory for the VPU. It has one wide read/write port of `LANES*DW` bits. A single address accesses one **lane-group**: all `LANES` consecutive 32-bit words for one vector element group.

- **Address `A`** accesses words `[A×LANES .. A×LANES+LANES-1]` of the logical array.
- With LANES=4 and DW=32, the port is 128 bits wide — one full vector read or write per cycle.
- Memory contents can be preloaded from a hex file at simulation start via `$readmemh("dmem_init.hex", mem)`.

## Why it is built this way

A single wide port means one VLD or VST instruction loads or stores an entire vector in one cycle, with no need to serialize individual lane accesses. This is what gives the VPU its bandwidth advantage over a scalar processor with LANES=1 (which accesses only 32 bits per cycle).

The async read matches the FSM design: in DECODE/EXECUTE state, the control unit presents the address and `dmem` returns `rdata` combinationally in the same cycle. The write happens synchronously at the end of that cycle, keeping the FSM simple.

## Timing

- **Read:** asynchronous (combinational). `rdata` is valid within gate delay after `addr` is set.
- **Write:** synchronous. Data is written to `mem[addr]` on the **next rising clock edge** after `we=1`.

## Worked example: VLD at address 2 (LANES=4)

Pre-state: `mem[2] = {0x000000AA, 0x000000BB, 0x000000CC, 0x000000DD}` (lanes 3..0)

Control signals: `we=0`, `addr=2`

Result: `rdata = {0x000000AA, 0x000000BB, 0x000000CC, 0x000000DD}`

Lane 0 gets `0xDD`, lane 1 gets `0xCC`, lane 2 gets `0xBB`, lane 3 gets `0xAA`.
