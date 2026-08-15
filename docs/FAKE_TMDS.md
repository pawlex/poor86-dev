# Fake TMDS — starting points

**No analysis here yet.** This is a place to start from when the
feasibility study happens. Links and facts only.

The question it will eventually answer: *can the ECP5 drive an HDMI or
DVI display directly, with no transmitter chip?* If yes, the FPGA video
path exists. If no, a real CL-GD5428 is the only display option.

## Prior art — start here

**[ULX3S](https://hackaday.io/project/159108-ulx3s-powerful-ecp5-board-for-open-source-fpga)**
([Crowd Supply](https://www.crowdsupply.com/radiona/ulx3s)) — an
open-source **ECP5-85F** board, the same part class as this project,
that already does exactly this.

- Its **GPDI** connector is electrically **LVDS and TMDS-tolerant**, and
  drives digital monitors and TVs with **no transmitter chip**.
- Serialisation uses the ECP5's own **`ODDRX1F`** primitive.

Working implementations:

| | |
|---|---|
| [lawrie/ulx3s_examples](https://github.com/lawrie/ulx3s_examples/blob/master/hdmi/fake_differential.v) | `hdmi/fake_differential.v` — TMDS encoding reduced from the DVI standard, DDR and SDR modes |
| [hdl-util/hdmi](https://github.com/hdl-util/hdmi/issues/25) | reported working on ULX3S after ECP5-specific serializer changes |

**No custom hardware is needed to answer the question.** A ULX3S is the
test vehicle, and the FPGA family matches.

## The arithmetic that will decide it

Serial rate is **10× the pixel clock**:

| mode | pixel clock | serial rate |
|---|---|---|
| 640×480 @ 60 | 25.175 MHz | ~252 MHz |
| 720×400 @ 70 (VGA text) | 28.322 MHz | ~283 MHz |
| 1024×768 @ 60 | 65 MHz | ~650 MHz |
| 720p @ 60 | 74.25 MHz | ~743 MHz |

## TODO

### 1. Find the ceiling first — this is a go/no-go gate

**Run the existing examples as they are, and record what actually works
and to what extent.** Modes, colour depth, and whether the output is
stable on a real display.

This comes before everything else because it decides whether the rest is
worth doing at all. **If the demonstrated ceiling is something like
320×200×256, that leaves no headroom** — nothing spare for higher modes,
for the overhead of scaling, or for sharing memory bandwidth with the
CPU. At that point the return does not justify building test harnesses,
in hardware or software, and the CL-GD5428 path becomes the answer by
default.

The gate is deliberately cheap: it needs a board and an afternoon, not a
project. **Do not build any test infrastructure before this is known.**

- [ ] Build and run `fake_differential.v` on a ULX3S unmodified. Record
      the modes it achieves.
- [ ] Push it: how far up the mode table can it be taken before it stops
      working, and does it fail cleanly or intermittently?
- [ ] Test against more than one display. Acceptance varies, and a mode
      that works on one monitor is not a result.
- [ ] **Decide go/no-go on the headroom, not on whether it works at
      all.** Working at the minimum is a negative result here.

### 2. Only if the gate passes

The questions below are the actual study, and none of them are worth
opening until the ceiling above is known.

## Questions for the study, when it happens

- What serial rate can the ECP5 actually sustain, for true LVDS pairs
  versus a resistor-network pseudo-differential, at the target speed
  grade?
- **What is the lowest mode a modern display will reliably accept?**
  Low pixel clocks are easy for the FPGA and often refused by modern
  monitors and TVs; 720p is accepted nearly everywhere and is the
  hardest to generate. That tension, not raw FPGA capability, is
  probably the real constraint.
- DVI-compatible signalling or full HDMI? DVI timing over an HDMI
  connector avoids data islands, audio and HDCP entirely, and may be
  sufficient for a DOS machine.
- Does guest resolution need to match output resolution? Scaling
  decouples them at the cost of logic and memory bandwidth.

## Why it matters beyond video

See [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md): if FPGA video exists and
shares CPU memory, scanout is roughly an order of magnitude more traffic
than the CPU generates, and the memory part gets chosen for video
bandwidth rather than CPU latency.

The plan of record's position is that **the memory subsystem must not be
designed around this question mark** — either collapse it early, or give
video its own memory channel so the dependency never exists.
