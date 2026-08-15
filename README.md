# Poor86

A 386/486-class PC motherboard, in mini-ITX, built around a real x86 CPU
and an FPGA chipset — with every part of the machine that nobody loves
replaced by something modern.

It boots DOS. It has no hard disk, no battery, no expansion slots, no
drive bays, and no shelf of discs. It fits in a case you can live with.

---

## Why

### Love of the game

The interesting engineering is still here. A 486 local bus with burst
transfers, write-back cache control and coherency is a genuinely hard
problem, and building a chipset front end for it in programmable logic
is the kind of work that is worth doing for its own sake. The memory
subsystem and the bus interface caching are the heart of this project —
and they are deliberately scheduled **last**, because starting with the
best part is how the other ninety percent never gets finished.

### Giving back

The retro community has already solved most of the practical problems of
keeping these machines alive — floppy emulators, IDE replacements,
sound cards on modern microcontrollers, video scalers, USB adapters.
They exist as separate projects, separate purchases and separate wiring.

This assembles them into one board, and gives the work back: open
hardware, open RTL, and an entirely open toolchain (yosys, nextpnr,
Verilator — no vendor tools anywhere in the flow). Fixes found in
upstream projects go back upstream.

### The effort is already worth it, finished or not

This sat as an idea for years. Not for lack of interest — for lack of
time against its scope. It spans PCB design, an FPGA chipset, period bus
protocols, firmware, x86 emulation and controller software, and each of
those is somebody's full-time specialism. Any one of them is a weekend.
All of them together is a wall.

These sub-projects had been put off for years because they are hard —
but they are hard in a specific way that is worth naming, because it
changes what to do about them. **Most of them are wide, not deep.**

A deep problem needs insight you do not yet have. A wide one needs you
to be fluent in a domain you are not fluent in: the SeaBIOS source tree,
a Cirrus register map, an ECP5 memory primitive, the ATAPI packet
interface. Every step is tractable; the cost is the ramp-up, and it
resets every time you put the project down. That is precisely why wide
problems stall on evenings and weekends — the evening goes on reloading
context and never reaches the work.

Very little of the progress here came from cleverness. A months-old
question about the bus was answered by running one existing emulator
configuration. The peripheral models turned out to already exist in a
fork of the project. The video BIOS itself specified what the hardware
must implement, once somebody read it. None of that was hard. It was
*unread*.

Which leaves the genuinely deep part — the memory subsystem and the bus
interface caching — as the smallest fraction of the work, and the part
the author is actually equipped for. The wall was never the interesting
problem. It was the dozen uninteresting ones standing in front of it.

Working with an AI assistant (Claude) is what got past them. **And the
point worth making plainly is this: even if the board is never finished,
the effort has not been wasted.** Real problems have been solved, and they
stand on their own:

- **A working co-simulation harness.** An x86 interpreter running
  natively drives real RTL through a Wishbone bus-functional model, so
  chipset logic can be developed and regression-tested without a CPU in
  the simulation. It is reusable well beyond this project.
- **SeaBIOS completes POST against it**, on a non-PCI ISA machine with a
  deliberately minimal device set — a reproducible configuration, not a
  one-off.
- **A real bug found upstream**, in the tiny386 interpreter: its
  instruction-fetch cache retained a physical address for MMIO pages,
  reading out of bounds. Fixed, documented, and a candidate to send
  back.
- **A bounded specification for Cirrus-compatible video**, derived by
  reading what the video BIOS actually touches rather than guessing —
  including the finding that the blitter is not required at all.
- **Measured budgets rather than assumed ones** — bitstream size, block
  RAM limits, LUT and timing figures across candidate cores.

The larger shift is harder to point at but matters more. **A great deal
of this design has moved from "it could be done, with caveats" into an
active plan** — decisions made, alternatives eliminated for stated
reasons, and the reasoning written down where it can be checked. The
caveats that remain are now specific and small enough to attack.

Every decision here is the author's. The assistance is in reach and
throughput, and in not losing the reasoning between sessions — which,
for a project this wide worked on in evenings, turns out to be the
binding constraint.

**So this is also a case study**, kept in the open so it can be judged
rather than claimed. What has characterised it: check for the existing
thing before building a new one; measure instead of arguing; and keep
the corrections on the record — several conclusions in
[docs/PLAN_OF_RECORD.md](docs/PLAN_OF_RECORD.md) reversed once evidence arrived,
and the superseded reasoning still sits beside what replaced it.

There is a lot of noise about what this technology is for. This is one
answer: **real engineering problems, not cat videos.**

### Not just nostalgia

Nostalgia would mean reproducing a 1993 machine faithfully, defects
included, and accepting that it is expensive, fragile and annoying to
own. That is a museum piece.

The aim is different: **the era should be accessible to people who were
priced out of it, and pleasant enough to actually use.** Period hardware
has become scarce and costly; a working machine is now several hundred
pounds of separate purchases plus ongoing maintenance. This should cost
a fraction of that and ask nothing of its owner beyond plugging it in.

That said — the specific machines are not arbitrary. **A 386SX was the
author's first computer, and a 486SLC2 the first upgrade, paid for with
paper-round money.** Those configurations are a requirement, not a
technical trade-off. Everything modern in this design exists so that
*those* machines can be delivered without the burden that otherwise
makes them unusable.

---

## The organising principle

> **Authenticity is required at the guest-visible register interface.
> Everything behind it should be modern.**

A real x86 is soldered to this board. It, and the DOS software above it,
can only see registers and bus cycles — so that is the only place
period-correctness buys anything. Behind that boundary, reproducing 1993
is cost without benefit, and frequently worse: analogue output stages,
battery-backed NVRAM and spinning media are things to be rid of, not
honoured.

| | authentic front end | modern back end |
|---|---|---|
| storage | IDE / ATAPI registers | controller-served images |
| network | NE2000 registers | WiFi |
| keyboard, mouse | 8042 and PS/2 | USB HID |
| video | Cirrus-compatible registers | HDMI, or real CL-GD5428 for a CRT |
| RTC and CMOS | 128 legacy registers | NTP, no battery |
| sound | SB16 / AdLib registers | software synthesis, modern DAC |

Two corollaries that have saved a great deal of work:

- **Do not own what you can inherit.** SeaBIOS and SeaVGABIOS already
  support this machine. Shape the hardware so their existing code paths
  apply, rather than writing or patching firmware.
- **Do not reinvent what already exists.** Check first. Most of what
  this project needs has been found rather than written.

---

## Goals

- **Boots DOS**, on real x86 silicon, out of the box, with nothing
  attached.
- **mini-ITX (170 x 170 mm)**, in a case that can live on a desk.
- **Low bill of materials.** Every function moved into the FPGA or the
  board controller is a part that does not have to be bought, fitted or
  sourced.
- **Open end to end** — hardware, RTL, and toolchain.
- **No maintenance burden.** No battery to replace, no drive to fail, no
  media to store.
- **Usable by someone who is not the author**, which is a higher bar
  than working.

### Non-goals

- Museum-grade period accuracy behind the register interface.
- Expansion slots. There are none, and the form factor could not hold
  them anyway.
- Windows. DOS is the target; anything further is a bonus.
- Being the fastest anything. A period machine that works beats a fast
  one that does not exist.

---

## What is on the board

- **A soldered x86.** A 386/486 SL/SLC-class part, or an **Am5x86-133**
  — abundant as NOS, 486DX4-class, and the part that makes the machine
  more than a curiosity. **3.3 V is a requirement**, because it lets the
  entire CPU bus connect to the FPGA without level shifters — plausibly
  the largest single saving in the design.
- **An ECP5 FPGA** carrying the chipset and the peripherals, so a
  discrete 8259, 8254, 8042 and NE2000 are LUTs rather than packages.
- **An ESP32** as board controller: NTP for the clock, WiFi for the
  network, and the back end for storage.
- **A RISC-V soft core** inside the FPGA, which serves fallback
  configuration when the controller is unavailable, and which can run an
  x86 interpreter so that a board works with no period CPU fitted at all.
- **Video**, either from the FPGA over HDMI, or a real **CL-GD5428** on
  the local bus for driving a CRT.

---

## Sub-projects

| repo | what it is |
|---|---|
| [vexrv-cpu-oss](https://github.com/pawlex/vexrv-cpu-oss) | the RISC-V soft core, the x86 interpreter payload, and the Verilator co-simulation the chipset is developed against |
| [ao486-cpu-oss](https://github.com/pawlex/ao486-cpu-oss) | the ao486 486-class x86 soft core packaged for the open toolchain — Verilator regression suite, plus synthesis and place-and-route with no vendor tools. Places and routes on an ECP5-85F at 32.87 MHz |
| [tiny386](https://github.com/pawlex/tiny386) | fork of the x86 interpreter, ported to bare-metal RV32 |
| [ecp5-oss-skeleton](https://github.com/pawlex/ecp5-oss-skeleton) | ECP5 project template and the block-RAM findings behind it |

Firmware comes from [SeaBIOS](https://www.seabios.org/) and SeaVGABIOS,
unmodified where possible.

---

## Status

Early. The schematics and library work are in `PCB/`; reference material
is in `Data/`.

On the simulation side, SeaBIOS already completes POST against the
chipset model in Verilator, with real RTL in the transaction path.

**The memory subsystem and the bus interface caching are deliberately
unspecified.** They are the most interesting part of the work and they
are being left until the rest is done.
