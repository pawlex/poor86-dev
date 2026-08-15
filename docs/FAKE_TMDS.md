# Fake TMDS — starting points

**No analysis here yet.** This is a place to start from when the
feasibility study happens. Links and facts only.

The question it will eventually answer: *can the ECP5 drive an HDMI or
DVI display directly, with no transmitter chip?* If yes, the FPGA video
path exists. If no, a real CL-GD5428 is the only display option.

## Test vehicles — what is on hand, and what each can answer

**No ULX3S, and none is being bought.** Two boards already here cover the
question between them — but not the same half, and one of them cannot
help at all. Worth stating why, so it is not re-examined later.

### Tang Nano 9K — answers the blocking question

Gowin **GW1NR-9** with an HDMI connector. Sipeed's own examples do
640×480@60, and community projects run 720p and 720×576@50.

This is the right instrument for **display acceptance**, which is the
question the floorplan actually waits on. Whether a monitor accepts
720×400@70 or 640×480@60 is a property of *the monitor*, and it does not
care which vendor's silicon generated the timing.

**What it does not test: the fake-differential technique.** The Tang Nano
drives HDMI through Gowin's **true LVDS output buffers** (`TLVDS_OBUF`)
and a hard 10:1 serialiser (`OSER10`) — real differential drivers, not a
resistor network. So it says nothing about signal integrity of emulated
differential, and should not be cited as if it did.

### MachXO2 — cannot reach DVI rates, and the margin is not close

Two boards here: `LCMXO2-1200ZE-1TG144C` and `LCMXO2-4000HC-4TG144C`.
Both are the **slowest speed grade** of their family. From the MachXO2
Family Data Sheet (FPGA-DS-02056-4.3):

| limit | value |
|---|---|
| **Table 3.25**, Maximum sysI/O Buffer Performance — **LVDS25E** | **150 MHz** |
| `fDATA`, DDRX1 Output Data Speed | **300 / 250 / 208 Mbps** by grade |
| `fDDRX1`, DDRX1 SCLK frequency | 150 / 125 / 104 MHz |

**640×480 DVI needs 252 Mb/s per lane.** The `-4` part tops out at **208
Mb/s**, and the ZE `-1` is slower still. Even the fastest MachXO2 grade
reaches only 300 Mb/s — which would clear 640×480 by a slim margin and
nothing else.

**So the MachXO2 boards are not video test vehicles.** Not marginal,
not worth attempting: the emulated-LVDS buffer alone is capped at 150 MHz
before the fabric is even considered.

### What nothing on hand can answer

**Signal integrity of an AC-coupled emulated differential output at TMDS
rates.** The Tang Nano uses real LVDS drivers; the MachXO2 cannot reach
the rate. Only an ECP5 driving the real coupling network answers it.

That is acceptable, because the technique is not the risk. It is
documented in the ECP5 datasheet with a termination scheme (Figure 3.1),
it ships working on the ULX3S, and there are multiple public
implementations. **The residual risk is this board's own layout and
termination**, which no borrowed hardware could have de-risked anyway.

### How the output is actually coupled — capacitors, not resistors

**Correction.** Earlier notes here described the interface as a resistor
network. **That is wrong**, and it is worth recording why, because the
mistake is an easy one to repeat.

**The ULX3S GPDI lines are series AC-coupled — 220 nF capacitors, 100 nF
on a later fork.** No resistor network. And that is the correct approach
for driving a DVI/HDMI *sink*, for a reason specific to how the sink is
built:

- **A TMDS sink terminates each line with 50 Ω to AVCC (3.3 V)**, and
  that termination is what establishes the DC bias.
- **Driving push-pull LVCMOS33 into that directly fights the bias.**
- **Series capacitors block the DC**, so the LVCMOS swing rides on the
  bias the sink has already set.

Industry guidance for TMDS coupling is **75–200 nF**, which is exactly
the range the ULX3S sits in.

**Where the resistor idea came from — and why it does not apply.**
Lattice's Figure 3.1 (§3.16, LVDS25E) *is* a resistor network, and it is
the figure this document already cites. But it emulates **LVDS**, which
is a different target: a ~1.2 V common mode into a 100 Ω differential
termination at the receiver. TMDS into an HDMI sink is a different load
with a different bias, and the resistor scheme does not carry across.

**The two are not interchangeable, and the datasheet figure is not the
one to build from here.** For BOM purposes this is a series capacitor per
line, and the value is a real design input rather than a detail.

### A note on the ULX3S reports

The ULX3S carries **`LFE5U-85F-6BG381C` — speed grade -6, the slowest.**
That reframes the 720p reports rather than confirming them: 720p is 743
Mb/s against a -6 guaranteed GDDRX2 ceiling of **624 Mb/s**, so those
results run roughly **19% above datasheet spec**.

Read correctly, that is evidence Lattice's numbers are conservative —
they are guaranteed over temperature and voltage. **It is not evidence
that 720p is safe to design on.** Design to the specified rate; treat the
overshoot as margin someone else happened to find.

---

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

---

## What the datasheet already settles — no hardware needed

Source: **ECP5/ECP5-5G Family Data Sheet, FPGA-DS-02012-1.9.** Three
facts, in the order they bind.

### 1. Emulated differential works on every bank

> *"All I/O banks support emulated differential I/O using the LVCMOS33D
> I/O type."* — §3.14.3

This confirms the position already recorded: fake TMDS is not
bank-restricted. Bank 8 remains excluded here by **our own reservation**,
not by any capability of the silicon.

### 2. But the *gearing* is left/right only — and gearing sets the ceiling

> *"On the left and right sides, the output register block can support
> 1x, 2x and 7:1 gearing enabling high speed DDR interfaces... On the top
> side, the banks support 1x gearing."* — §2

> *"The I/Os on the top and bottom banks do not have LVDS input and
> output buffer, and gearing logic, but can use LVCMOS to emulate most of
> differential output signaling."* — §2

**The buffer is available everywhere; the serialiser is not.** That
distinction is the whole finding. Emulated differential output on the top
bank is real, but it is stuck at 1x gearing, which caps the rate.

### 3. The rates

| output path | available on | max data rate |
|---|---|---:|
| **GDDRX1** (1x gearing) | **any side, incl. top** | **500 Mb/s** |
| **GDDRX2** (2x gearing) | **left and right only** | **624 / 700 / 800 Mb/s** (-6 / -7 / -8) |
| DDR71 (7:1) | left and right only | ECLK 262.5 / 310 / 378 MHz |

### Which modes each allows

Serial rate is 10× the pixel clock, per lane.

| mode | pixel clock | Mb/s | 1x — any edge | 2x -6 | 2x -7 | 2x -8 |
|---|---|---:|:-:|:-:|:-:|:-:|
| 720×400 @70 — VGA text | 28.322 MHz | 283 | **yes** | yes | yes | yes |
| 640×480 @60 | 25.175 MHz | 252 | **yes** | yes | yes | yes |
| 800×600 @60 | 40.0 MHz | 400 | **yes** | yes | yes | yes |
| 1024×768 @60 | 65.0 MHz | 650 | no | no | yes | yes |
| 1280×720 @60 — 720p | 74.25 MHz | 743 | no | no | no | **yes** |
| 1280×1024 @60 | 108.0 MHz | 1080 | no | no | no | no |

### This agrees with the field report

The ULX3S DVI example is reported working at **720p, with bad pixels at
1280×1024.** 1280×1024@60 is 1080 Mb/s — above even the -8 ceiling of
800. **The datasheet and the field result independently agree**, which is
worth considerably more than either on its own.

### What it means for this board

- **Every mode DOS natively uses fits on any edge, including the top**,
  with margin: 252 and 283 Mb/s against a 500 Mb/s floor.
- **1024×768 requires a left/right edge and at least a -7 part.**
- **720p requires a left/right edge and a -8 part.**
- **The headroom test in the gate below is passed on paper.** The worst
  case is 800×600, not the 320×200 that would have killed the path.

---

## The arithmetic that will decide it

Serial rate is **10× the pixel clock**:

| mode | pixel clock | serial rate |
|---|---|---|
| 640×480 @ 60 | 25.175 MHz | ~252 MHz |
| 720×400 @ 70 (VGA text) | 28.322 MHz | ~283 MHz |
| 1024×768 @ 60 | 65 MHz | ~650 MHz |
| 720p @ 60 | 74.25 MHz | ~743 MHz |

---

## Two things this changes

**1. Speed grade is now a decision, and it was never recorded.** Nothing
in this repository states which grade of LFE5U-85F is intended. It now
has a video consequence: -6 tops out at 800×600, -7 reaches 1024×768, and
only -8 reaches 720p. It should be chosen deliberately rather than by
whatever is in stock.

**2. HDMI on the top edge caps video at 800×600 — permanently.** The
floorplan currently takes HDMI from PT slack, and
[PLACEMENT.md](PLACEMENT.md) claimed placement was free among PT/PL/PR.
**That claim was wrong**, and it was wrong in the expensive direction: it
is a board-spin mistake, not a bitstream one. PL carries memory and PR
carries the CPU bus, so moving video to a geared edge is not free — it
competes with the two widest buses on the board.

That decision does not need making yet, because it depends on the one
question the datasheet cannot answer.

---

## The question that is left

**The FPGA is no longer the constraint — the display is.**

Every mode DOS actually produces is comfortably within reach on any edge.
What is not known is whether a modern monitor will *accept* those modes.
720×400@70 and 640×480@60 are exactly the timings modern displays are
most likely to refuse, and 720p — accepted nearly everywhere — is the one
mode that needs both the best silicon and the contested edges.

So the experiment narrows from *"find the ceiling"* to a single question:

> **What is the lowest mode a real display will reliably accept?**

If the answer is 640×480, video is cheap: any edge, any speed grade, and
the floorplan stands as drawn. If the answer is 720p, video costs a -8
part and a left/right edge, and it has to be argued against memory and
the CPU bus for the pins.

That is a much cheaper experiment than the original gate, and it still
needs a board and an afternoon rather than a project.

---

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

**Revised: the FPGA half is settled on paper, so the gate is now a
display-acceptance test on hardware already here.**

- [ ] **Read the EDID of every display that matters**, before touching an
      FPGA. Established Timings I names 720×400@70 and 640×480@60
      explicitly. Costs nothing and may answer most of it.
- [ ] **Drive the candidate modes from the Tang Nano 9K** — 720×400@70,
      640×480@60, 800×600@60 — and record which are accepted, refused, or
      accepted-but-wrong.
- [ ] **Test more than one display.** Acceptance varies, and a mode that
      works on one monitor is not a result.
- [ ] **Cross-check against a PC modeline** where a display refuses a
      mode, to separate "the display rejects this timing" from "the
      FPGA's timing is out of tolerance."
- [ ] **Record the answer as a placement input**, since it decides whether
      HDMI can stay on PT: 640×480 accepted → PT is fine and costs
      nothing; 720p required → a geared edge and a -8 part, argued against
      memory and the CPU bus.

### 2. Only if the gate passes

The questions below are the actual study, and none of them are worth
opening until the ceiling above is known.

## Questions for the study, when it happens

- What serial rate can the ECP5 actually sustain, for true LVDS pairs
  versus an AC-coupled pseudo-differential, at the target speed grade?
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
