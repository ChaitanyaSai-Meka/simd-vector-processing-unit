# Video Script — SIMD VPU Demo (5 minutes)

**File:** `docs/video_script.md`
**Owner:** Chaitanya Sai Meka (Role 5, Report and Results)
**Recording date:** Saturday, November 14, 2026 — all five together

---

## Timing Overview

| Segment | Speaker | Duration |
|---------|---------|----------|
| 1. Project idea | Lalithendra | 30 s |
| 2. Team introductions | All five | 30 s |
| 3. Block diagram walkthrough | Jagruthi / Lalithendra | 60 s |
| 4. Live `make test` | Rakshita | 60 s |
| 5. Waveform of 4-lane VADD | Dhanvin | 90 s |
| 6. What's next — Phase II | Chaitanya | 30 s |
| **Total** | | **5 min** |

---

## Segment 1 — Project idea (30 s)
**Speaker: Lalithendra**

> "Welcome. Our project is a SIMD Vector Processing Unit — a small but complete
> hardware design that executes one instruction across multiple data lanes in
> parallel. Instead of adding one number at a time, it adds four — or eight — in
> the same clock cycle. This is exactly the idea behind the SIMD extensions in
> modern CPUs and GPUs. We built ours from scratch in Verilog, verified it with
> a Python golden model, and synthesized it on an Artix-7 FPGA target.
> I am Lalithendra, the architecture lead."

---

## Segment 2 — Team introductions (30 s)
**All five, one line each**

*(Each person says their name and role, in order:)*

1. **Lalithendra** — "Architecture lead and integration."
2. **Dhanvin** — "Datapath RTL: the ALU, lane array, and register files."
3. **Jagruthi** — "Control and memory: ISA design, data memory, program counter."
4. **Rakshita** — "Verification: golden model and all testbenches."
5. **Chaitanya** — "Report, synthesis scripts, and results."

---

## Segment 3 — Block diagram (60 s)
**Speakers: Jagruthi and Lalithendra**

*(Show `docs/block_diagram.md` rendered or the exported PNG)*

> **Jagruthi:** "Here is the top-level datapath. When an instruction like VADD v2, v0, v1 is issued,
> `vreg_file` simultaneously outputs all 128 bits of v0 on read port 1 and v1 on read port 2.
> Both are combinational reads — no extra cycle needed."
>
> **Lalithendra:** "Those two flat buses go into `lane_array`. Inside, there are LANES copies —
> four here — of `lane_mux` and `lane_alu`, wired by a generate loop. Lane i takes bits
> `[i×32 +: 32]` from each bus. All four ALUs compute simultaneously.
> The results flow through `result_combiner` and are written back to v2 on the next clock edge.
> One instruction, four additions, one cycle."

---

## Segment 4 — Live `make test` (60 s)
**Speaker: Rakshita**

*(Run in terminal, results visible on screen)*

```bash
make test
```

> "I'll run all our unit tests now. Each testbench is self-checking — it computes
> the expected value using our Python golden model, compares it to the RTL output,
> and prints PASS or FAIL.
>
> You can see `lane_alu_tb` passing every opcode — VADD, VSUB, AND, OR, XOR,
> signed less-than, equal, left shift, right shift — including edge cases like
> INT_MIN and overflow wraparound.
>
> `vreg_file_tb` and `sreg_file_tb` check all eight registers. Notice r0 stays
> zero even when we try to write to it.
>
> `lane_array_tb` runs at LANES equals 1, 4, and 8. All lanes compute in the same
> cycle, and changing one lane's input does not affect the others.
>
> And at the bottom: ALL PASS."

---

## Segment 5 — Waveform of 4-lane VADD (90 s)
**Speaker: Dhanvin**

*(Open GTKWave with the VCD from `make wave`, zoom into one VADD operation)*

> "Let me show you what happens inside the hardware during a VADD.
>
> On the top here is `clk`. Below it, `vs1` and `vs2` — the two input vector buses,
> each 128 bits wide. I've labelled the four 32-bit lanes.
>
> Watch what happens on this rising edge. At the same instant:
> Lane 0 computes 1 plus 10 equals 11. Lane 1 computes 2 plus 11 equals 13.
> Lane 2 computes 3 plus 12 equals 15. Lane 3 computes 4 plus 13 equals 17.
>
> All four additions happen in the same clock cycle. This is SIMD in hardware.
>
> Compare this to LANES equals 1 — a scalar baseline using the same RTL.
> There, only lane 0 runs and you need four sequential instructions to do the same work.
> That is the speedup we measure: approximately 4 times fewer cycles on a pure
> data-parallel benchmark."

---

## Segment 6 — Phase II roadmap (30 s)
**Speaker: Chaitanya**

> "Phase I is the prototype — the datapath, testbenches, and block diagram you
> have just seen. In Phase II we add the full control FSM in RTL, an assembler
> in Python, and run three benchmarks at all four lane counts to get real cycle
> numbers. We will also run Vivado synthesis to measure LUTs, flip-flops, and
> maximum frequency for each lane width. The goal is to show exactly where
> the speedup is linear and where loop overhead limits it.
>
> Thank you — we are Team Lane Breakers."

---

## Production Notes

- **Screen layout:** split terminal (left) + GTKWave or rendered block diagram (right)
- **Resolution:** 1920×1080, 30 fps minimum
- **Audio:** one person speaking at a time; no background music
- **Recording order:** record segments 4 and 5 first (live demos, one take), then segments 1–3 and 6 as voiceover
- **Upload:** replace the `[VIDEO LINK]` placeholder in `README.md` once the video is live
