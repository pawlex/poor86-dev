# Design decisions

The architecture record for Poor86: what is decided, what is open, and
**why** — including the reasoning that was wrong on the way, because a
decision without its rejected alternatives tends to get re-litigated.

Motivation, goals and the organising principle are in
[../README.md](../README.md). This file is the detail beneath them.

Two conventions carried throughout:

- **If a decision would assume a particular memory-subsystem design, it
  is flagged rather than assumed.** The memory subsystem is being
  specified last, deliberately.
- **Corrections stay on the record.** Several conclusions here reversed
  once evidence arrived; the superseded reasoning is kept beside what
  replaced it.

Implementation and the simulation environment live in
[vexrv-cpu-oss](https://github.com/pawlex/vexrv-cpu-oss).

## Decided: one soldered CPU, SX-class bus, 3.3 V

**There is no socket.** All parts are soldered down, and there is exactly
one CPU — a **386/486 SL/SLC-class part in PGA100, 3.3 V VCC**.

That resolves what looked like the hard decision. The cost weighted
heaviest — two bus front ends for a dual-socket board — **does not
exist**. There is one bus, one front end, one set of validation.

### What follows

```
  one SX-class CPU  ->  16-bit data, 24-bit address
                    ->  no PCI (32-bit, anachronistic)
                    ->  no VL-Bus slot; local-bus video still fine
                    ->  ISA-class programming model
                    ->  16 MiB guest RAM ceiling
```

The ceiling is now a property of the machine rather than of which part
someone fitted, which is simpler to design and document against.

### 3.3 V is the important part

**A 3.3 V CPU interfaces directly to the ECP5.** The FPGA's I/O banks
drive and receive LVCMOS33, so the entire CPU bus — every address, data
and control line — connects without level shifters.

At 5 V this would need translation on dozens of signals: parts, board
area, propagation delay on the timing-critical path, and a failure mode
on every one of them. Requiring 3.3 V removes all of it. This is
plausibly the single largest BOM and area saving in the design, and it
is consistent with the mini-ITX and cost goals.

### Why SL/SLC is a good fit beyond the voltage

The SLC-class parts pair a **386SX-style bus with the 486 instruction
set** and a small on-chip cache. So the chipset sees the simpler 16/24
bus while the software sees a 486 — better compatibility for the same
front-end effort. They are also low power, need no heatsink, and come in
a package that suits mini-ITX far better than a 486 PGA with a cooler
on top.

### The 486 part: Am5x86-133

For the record, the 486-class option is an **Am5x86 at 133 MHz**,
abundantly available as NOS — which answers the sourcing concern raised
against period parts elsewhere. It is 486DX4-class with a 16 KiB
write-back L1, and **3.3 V**, so the no-level-shifter property above
holds for it as well.

**Its bus is 33 MHz, not 133.** The 133 is a 4x internal multiplier. The
FPGA chipset only ever has to meet the 33 MHz bus, and against the Fmax
figures already measured on this device — VexRiscv variants at 99-108
MHz, ao486 at 32.87 MHz out-of-context — that is roughly 3x headroom on
the front end. It stays comfortable as the device fills.

### ...and it brings the hardest chipset problem

The Am5x86 is the fast part *and* the difficult one. Its bus is **32-bit,
bursting, pipelined, with cache control** — and with a **write-back L1**,
which is the part that hurts.

What the chipset has to deal with that an SX-class bus does not:

| signal / behaviour | why it is work |
|---|---|
| `BRDY#` / `BLAST#` bursts | 4-transfer cache line fills, not single cycles |
| `KEN#` | the chipset decides, per cycle, what is cacheable |
| `FLUSH#` | forced write-back and invalidate |
| `AHOLD` / `EADS#` / `INV` | snooping — an external address driven *into* the CPU |
| write-back L1 | **the CPU can hold dirty lines the chipset does not have** |

That last row is the real problem, and it is a *coherency* problem rather
than a timing one. Anything else writing guest memory — the ESP32
serving storage, the soft core, any DMA-equivalent — can be writing
underneath a dirty line the CPU has not flushed.

Three ways out, in increasing order of cost:

1. **Never assert `KEN#`.** External memory is uncacheable, the L1 is
   effectively disabled, coherency evaporates. Simplest possible chipset
   — and throws away most of what the 133 MHz part was bought for.
2. **Cacheable but no burst.** Assert `KEN#`, answer each of the four
   transfers with a normal ready rather than `BRDY#`. Line fills cost 4
   cycles instead of a burst, but the cache works. Still needs a
   coherency answer.
3. **Selective cacheability plus snooping.** `KEN#` asserted only for
   regions no other agent writes, snooping via `AHOLD`/`EADS#` for the
   rest. Fastest and hardest.

Note (1) and (2) make the *coherency* question mostly disappear, which is
worth weighing: the difficulty is not evenly distributed across the
options.

**Deliberately deferred.** Burst and caching support are not on the
critical path to a first board. The soft core makes the hardware useful
without them, so this is scheduled after production rather than before
it — and it is another reason the memory subsystem stays open, since the
cacheability and coherency policy is downstream of what sits behind the
BIU.

- [ ] Decide the cacheability and coherency policy when the Am5x86 front
      end is built. Note the existing BIU decision — protocol-correct,
      structured so wait states and bursts can be added later — was taken
      against a simpler bus, and on a write-back 486 bursts and `KEN#`
      change what the front end *is* rather than extending it.

### The risk this sequencing creates, and the cheap insurance

Shipping the board before the hard-CPU front end exists means **the PCB
commits to a bus interface that has never been exercised.** Layout,
termination and pin assignment are frozen at production while the logic
that drives them is still hypothetical. That is a respin risk, and the
mitigations are cheap only if taken up front:

- [ ] **Route every CPU signal to the FPGA**, including ones the first
      chipset ignores — `KEN#`, `FLUSH#`, `AHOLD`, `EADS#`, `BRDY#`,
      `BLAST#`, `INV`, byte enables, everything. A programmable chipset
      can start using a signal later; it cannot use one that was never
      connected. Omitting "unneeded" pins is the single most likely
      cause of a respin here.
- [ ] **Leave spare FPGA I/O and keep banks flexible.** The same
      argument.
- [ ] **Be conservative on the bus at 33 MHz** — trace lengths,
      termination, and clock distribution — since the timing-critical
      path cannot be validated on hardware until the front end exists.
- [ ] Consider whether a first board can be brought up with **no x86
      fitted at all**, which removes NOS sourcing from the bring-up
      critical path entirely.
- [ ] Note the asymmetry this creates between SKUs: the SX-class part
      needs none of this. **The cheap CPU has the cheap chipset and the
      fast CPU has the expensive one**, so the two variants are not
      equally far from done.

### Two CPU options: a bitstream difference, and a footprint problem

If both an SLC-class part and the Am5x86 are offered, they differ in bus
width (16/24 versus 32) and therefore in chipset front end. Two useful
observations:

- **In an FPGA that is a bitstream difference, not a redesign.** The
  front end can be built per variant and selected at configuration time.
  This is a real advantage of putting the chipset in programmable logic
  and is worth exploiting rather than avoiding.
- **The PCB is the harder half.** The packages differ, so this is either
  two board variants or one board carrying both footprints with only one
  populated. That is an area question on a 170 mm square board, not a
  logic question.

### The soft core's role varies by SKU — and that has a consequence

An Am5x86-133 buyer is unlikely to care whether the tiny386 soft core
runs at all. Which implies the soft core matters most at the *other* end
of the range — plausibly a SKU with **no x86 part fitted at all**,
where the VexRiscv running tiny386 *is* the CPU. That is the cheapest
possible BOM and has no period-parts sourcing constraint, which fits the
cost positioning well.

**If that is a shipping configuration, two things recorded elsewhere stop
being true and need revisiting.** Both currently justify themselves on
tiny386 being a validation vehicle only:

1. **"Performance is explicitly not a design input."** True for a
   validation vehicle. False for a SKU somebody buys.
2. **"The guest region is uncached in the MCU."** That was decided so
   guest traffic *reaches the BIU and is observable in Verilator* —
   deliberately trading speed for visibility. As a product configuration
   it means every guest memory access pays a bus round trip, which is
   the dominant cost in an interpreter.

Rough order of magnitude, to make the discussion concrete rather than
abstract: VexRiscv at ~100 MHz against tiny386's ~100 host instructions
per emulated instruction is on the order of **1 M x86 instructions/sec**
— period-plausible for an early 386SX, and genuinely usable for DOS.
**But that estimate assumes cached guest memory.** With every access
crossing the BIU uncached it would be substantially worse, and the gap
is the size of the conflict above.

**Resolved by sequencing: it is both, in order.** The soft core is the
path that gets the hardware design locked in and into production *before*
the hard-CPU chipset is finished. First boards are useful with no x86
part fitted at all; the Am5x86 front end lands later as a bitstream.

That is only possible because the chipset is in programmable logic, and
it is worth stating as a deliberate strategy rather than a happy
accident: **the board can ship before the chipset is complete.**

So the caching question is real but **not now**. Getting something into
the community's hands beats optimising a path nobody has yet used.

- [ ] Revisit "the guest region is uncached in the MCU" when soft-core
      performance actually matters — not before.

- [ ] **Keep one machine definition across variants.** A 486 variant
      *could* support VL-Bus or PCI, but diverging would mean two
      peripheral sets, two BIOS configurations and two software stories.
      The ISA-class definition is very likely still right for both — but
      it should be a decision, not drift.

### Consequences worth recording

- **No CPU choice for the user, and no upgrade path.** The machine is an
  appliance, which fits "a nice package for the enthusiast" but should be
  a deliberate position rather than a side effect.
- **Sourcing.** 3.3 V parts of this era are a narrower field than 5 V
  ones, and this is a build-volume constraint like the GD5428.
- **Terminology.** Documents here say "the hard CPU in the socket". It
  is soldered; the reasoning is unchanged — a real x86 is present and
  therefore the guest-visible interfaces must be period-correct — but
  the phrasing should be corrected as files are touched.
- The GD5428 attach question is simplified too: there is only one bus for
  it to match.

## Decided: no PCI (follows from the above)

**PCI is out.** It pushes real complexity onto the chipset — configuration
space, BAR allocation, interrupt routing — for a device set that is
fixed, known, and entirely ISA-class at the register level (IDE at
`0x1f0`/`0x170`, NE2000 at `0x300`, SB16 at `0x220`, VGA at `0x3c0`,
8042, 8259, 8254, RTC).

This chooses the **programming model the guest sees**, not connectors.
With peripherals as FPGA logic there are no physical slots either way.

### The evidence

SeaBIOS supports non-PCI as a first-class configuration. QEMU's `isapc`
machine loads the **identical `bios.bin`** — one binary, decided at
runtime:

```
addr=00000000fffe0000 size=0x020000 mem=ram name="bios.bin"
...
Detected non-PCI system
ATA controller 1 at 1f0/3f4/0 (irq 14 dev ffffffff)
ATA controller 2 at 170/374/0 (irq 15 dev ffffffff)
Running option rom at c000:0003            <- ISA VGA
DVD/CD [ata1-0: QEMU DVD-ROM ATAPI-4 DVD/CD]
```

Legacy IDE works, drives attach and are bootable, and video comes up
through an ISA option ROM. Our machine with the i440FX/PIIX3 removed
produces the same `Detected non-PCI system` and the same ATA controllers
at `dev ffffffff`, and completes POST.

### Correction: this supersedes the `bios-geometry` plan

An earlier entry recorded drive geometry arriving as a `bios-geometry`
fw_cfg file. **That does not work on a non-PCI machine:**

```c
int boot_lchs_find_ata_device(struct pci_device *pci, ...)
{
    if (!CONFIG_HOST_BIOS_GEOMETRY) return -1;
    if (!pci) return -1;      // support only pci machine for now
```

So geometry falls back to the legacy CMOS type-47 bytes, populated by
the reset-exit vector, plus SeaBIOS's own translation from IDENTIFY.
The CMOS bytes had to be populated anyway for guests that bypass the
BIOS, so this costs a channel rather than a capability.

- [ ] Drop `bios-geometry` from the reset-image plan; keep `bootorder`,
      which does not depend on PCI.

## Video: HDMI on-board, framebuffer in external DRAM

**On-board video is HDMI driven directly from the ECP5** ("fake TMDS" —
differential pairs from the FPGA's own I/O, no transmitter chip). The
**framebuffer lives in external DRAM.**

That is a decision with a dependency attached, and it is the reason the
memory subsystem stays deferred: **the video path crosses it.** Flagged
rather than assumed, per the standing convention.

On-chip is not an option, and the arithmetic is worth keeping so it is
not re-litigated. An LFE5U-85F has 208 EBR x 18,432 bits = 468 KiB
total:

| | bits | EBR at ideal packing |
|---|---|---|
| VGA 256 KiB (4 planes x 64 KiB, no byte enables) | 2.1 Mbit | ~114 of 208 — ~55%, tight but possible |
| SVGA 1 MiB | 8.4 Mbit | impossible |

(An earlier note here applied the ~44% efficiency measured for
*byte-enabled* BRAM to VGA planes, which do not need byte enables. That
was wrong and is corrected above. The conclusion is unchanged for SVGA
and only becomes arguable for plain VGA.)

Driving a CRT does **not** by itself require a real card: an FPGA drives
analog RGB through a DAC with PLL-generated 25.175/28.322 MHz pixel
clocks. Authenticity of *output* and depth of *register compatibility*
are separable questions.

- [ ] **VLB is still on the table** for optional real VGA hardware, as a
      separate path from on-board HDMI. Specification pending; not
      recorded here.

### Two video paths, and they are alternatives worth keeping distinct

| | on-board FPGA video | CL-GD5428 on the local bus |
|---|---|---|
| output | HDMI (fake TMDS from the ECP5) | analogue RGB to a CRT |
| framebuffer | external DRAM, shared | the chip's own DRAM |
| compatibility | as good as the core written | **exact, it is the silicon** |
| FPGA cost | a Cirrus-compatible core | none |
| supply | none | a 1990s part, NOS or salvage |

**If a real GD5428 is fitted, the FPGA does not need a Cirrus core at
all** — which reverses the note recorded earlier that the
Cirrus-compatible core is "load-bearing rather than convenient". It is
load-bearing only for the HDMI path. Whether both paths coexist is
undecided.

Three things to check early:

- [ ] **Bus width against the socket.** VLB *is* the 486 32-bit local
      bus. A 386SX has a 16-bit data bus, so a VLB-attached GD5428
      cannot serve it. The GD542x family also supports a 16-bit ISA-style
      interface, so a dual-socket board may need the chip strapped
      differently per socket — or the VLB path may be 486-only.
- [ ] **Bus arbitration.** The chipset must *not* claim `0x3c0-0x3df`
      or the `0xa0000-0xbffff` aperture when the real chip is present,
      and must let it respond directly.
- [ ] **Supply risk.** A discontinued 1990s part in a product aimed at
      enthusiasts is a sourcing constraint on build volume, and cuts
      against "does not want to spend hundreds on nostalgia" if the part
      is scarce.

**Simulation consequence.** Real silicon cannot be Verilated. The
co-simulation would keep a software Cirrus model for the FPGA path,
and the GD5428 path would be validated on hardware only — the same
class of gap as bus timing, and worth recording as accepted rather than
discovered later.

### Direction: be register-compatible with QEMU's Cirrus model

**This applies to the FPGA video path.** It is unnecessary if a real
GD5428 is fitted, and it is exactly what that chip implements — so the
register list below doubles as the compatibility target either way.

The payoff is that **the video BIOS arrives as a finished package** —
SeaVGABIOS's `clext.c` — rather than being written. QEMU's `isapc`
already loads `vgabios-cirrus.bin`, so ISA Cirrus is a supported
combination, not an improvisation.

**The compatibility surface needed to inherit the BIOS is bounded, and
much smaller than a full Cirrus clone.** Read out of `clext.c`:

| | registers |
|---|---|
| detection | sequencer `0x06`: write `0x92`, read back `0x12` |
| memory size | sequencer `0x0f`, bits 4:3 (and bit 7 for 4 MiB) |
| VCLK / mode | sequencer `0x0b-0x0e`, `0x1b-0x1e`, `0x07`, `0x12`, `0x13`, `0x17`, `0x0a` |
| banking / offset | graphics controller `0x09`, `0x0a`, `0x0b` |
| extended CRTC | `0x1a`, `0x1b`, `0x1d` |
| colour depth | the hidden DAC register (`0x3c6` quad-read sequence) |
| BitBLT | `grdc 0x31` — **reset only** |

Plus a standard VGA core underneath, which `stdvga.c` drives.

**The accelerator is not required.** SeaVGABIOS touches BitBLT exactly
once, to reset it at init, and never issues a blit. That removes the
single most expensive block from the critical path.

The inherited mode set is 640x480, 800x600 and 1024x768 at 8/15/16/24
bpp. Note 1024x768x24 is 2.25 MiB, which is consistent with the
framebuffer living in external DRAM.

Honest limit: this buys **mode setting and VESA VBE**, not accelerated
software. DOS titles and Windows drivers that drive Cirrus BitBLT
directly would need the engine. Most DOS SVGA software uses VBE with
banked or linear framebuffer writes and would be fine.

- [ ] Decide which Cirrus the model claims to be, and make sequencer
      `0x0f` report a size that matches the DRAM actually allocated.
- [ ] **Place `vgabios-cirrus.bin` at `0xc0000`.** With no PCI there is
      no expansion-ROM BAR, so the BIOS finds it by scanning — which is
      exactly what `isapc` does (`Running option rom at c000:0003`).
      That makes the VGA BIOS another reset-vector-placed image.
- [ ] Decide whether BitBLT is ever in scope, or explicitly out.

## Decided in principle: sound synthesis is software

The SB16 / AdLib **register interface** is period-correct, like every
other front end. The **synthesis is not RTL** — it runs as software on a
microcontroller, with a modern output stage.

Two reasons, and the second is the stronger one:

- An OPL FM synthesiser in RTL is real work; in software it is a solved
  problem with a known-good implementation already in the fork
  (`fmopl.c`, plus `sb16.c`, `adlib.c`, `pcspk.c`).
- **The analogue quality of the original is a defect, not a
  characteristic worth reproducing.** A modern I2S DAC is strictly
  better on the axis nobody wants authenticity on.

Worth keeping the distinction clear: *synthesis accuracy* — the
chip-specific OPL behaviour that period music was composed around — is
worth preserving, and a well-tested software core preserves it better
than a fresh RTL implementation would. It is the **output stage** that
should be modern, not the sound.

- [ ] Which microcontroller hosts it is gated on the dividing line
      below. Sample delivery is continuous but low bandwidth, which
      argues for the ESP32; the SB16 register and DMA path is
      timing-coupled and argues for staying on-chip. The split may not
      fall at the same place as the device boundary.
- [ ] `i8257.c` (DMA) is needed for digital audio and is in the fork,
      unvendored so far.

## OPEN, and blocking: the dividing line between the two controllers

**This is the parent decision.** The arbitration questions below, and
the homes of the peripherals still to come (sound, USB, keyboard,
mouse), all wait on it. Nothing here is settled.

### Three tiers, not two

There are three places a peripheral can live, and the soft-core occupies
a genuinely useful middle:

| tier | latency to the guest bus | cost of complex logic |
|---|---|---|
| FPGA RTL | lowest | highest |
| **VexRiscv soft-core** | **on-chip, low** | **low — it is software** |
| ESP32 | off-chip, high | low |

The soft-core can host things too complex for RTL but too
timing-coupled for an off-chip round trip. That middle tier is what
makes the partitioning non-obvious.

### Split each peripheral at the register interface

Not "which tier owns this device" but "which tier owns the *front end*
and which owns the *back end*". The fork already does this consistently,
in three devices:

| device | front end (guest-visible) | back end |
|---|---|---|
| NE2000 | register model | tuntap / slirp / ESP32 WiFi |
| 8042 | register model + PS/2 queue | host keys / socket (`wifikbd.c`) / ESP32 |
| IDE | register model | file / controller-provided storage |

`i8042.c` already carries FreeRTOS mutexes on the PS/2 queue precisely
so another task can inject events. The pattern is load-bearing upstream,
not incidental.

**The front end must stay period-correct and low-latency** whichever
tier runs it — that is what the hard 386SX/486DX in the socket requires.
The back end can live anywhere.

### What decides it

- **How tightly the guest is coupled to device timing.** A guest
  spinning on a status register cannot tolerate an off-chip round trip;
  an event-driven device at human timescale can.
- **Bandwidth.** The `0xa0000` aperture is the extreme case.
- **Implementation-cost asymmetry.** USB host stacks, TCP/IP,
  filesystems and FM synthesis are far cheaper in software. Bus
  protocol timing, DMA and scanout are far cheaper in RTL.

### First-pass reading, to be confirmed rather than assumed

- **Video is the one that cannot go off-chip.** Aperture bandwidth and
  scanout timing rule it out. RTL plus framebuffer memory.
- **Sound** splits: the SB16 register interface and DMA are
  timing-coupled and belong on-chip; FM synthesis does not (`fmopl.c`
  exists). Output can be ESP32 I2S or FPGA-side. Note `sb16.c`,
  `adlib.c`, `fmopl.c`, `pcspk.c` and `i8257.c` are all in the fork.
- **Keyboard and mouse**: front end is already vendored and running.
  Only the event source moves.
- **USB is not a guest-visible device at all for DOS.** It is a back-end
  transport for HID. No USB controller needs modelling — a real scope
  saving, and worth stating so it does not get built by reflex.

### The testbench can answer this empirically

Rather than deciding by intuition: the co-simulation already counts bus
transactions per port, so it can measure how tightly a guest actually
polls each device during a real workload. That is the evidence the
partitioning wants, and it is one of the things the rig exists for.

- [ ] Determine the dividing line. Until then the arbitration items
      below stay open on purpose.

## Design goal: mini-ITX form factor

The motherboard targets **mini-ITX (170 x 170 mm)**, so it lives in a
modern small-footprint case. Not period-correct, deliberately — a
machine that is a burden to keep set up is a machine that does not get
used.

**This is not a new constraint so much as a second justification for the
architecture already chosen.** Every "modern back end" decision also
buys board area:

| decision | area reclaimed |
|---|---|
| WiFi via ESP32 | no RJ45 (tall) or magnetics |
| ESP32 block storage | no drive connectors or bays |
| NTP time | no coin cell or holder |
| HDMI from the FPGA | no VGA card, no slot |
| peripherals as FPGA logic | no discrete 8259/8254/8042/NE2000 packages |

### The tension worth resolving: a physical VLB slot does not fit

Approximate edge budget against 170 mm:

| | length |
|---|---|
| 16-bit ISA connector (98-pin) | ~129 mm |
| VLB extension (116-pin), inline | ~51 mm |
| **ISA + VLB together** | **~180 mm — exceeds one board edge** |
| short ISA card | ~170 mm |
| full-length ISA card | ~333 mm |

A VLB slot is an ISA connector with the VLB connector inline behind it,
and the pair is longer than a mini-ITX board edge. Even a plain 16-bit
ISA slot would consume most of one edge, and the card would overhang
the board and miss the single rear slot opening a mini-ITX case
provides.

So **mini-ITX and a real VLB video card are close to mutually
exclusive**, which points at on-board HDMI being not merely preferable
but the only option that fits — and makes the Cirrus-compatible core
load-bearing rather than a convenience.

The "(kinda)" in "VESA local bus (kinda) video" may already account for
this: a VLB-*like* on-board local bus to the FPGA sidesteps the geometry
entirely, since it needs no connector. Recorded as a question rather
than an assumption.

**Resolved: on-board, not a slot.** The VLB route, if taken, is a
**Cirrus Logic CL-GD5428 down on the board**, connected directly to the
x86 local bus. No connector, so the geometry problem above does not
arise.

### Other things the form factor decides

- [ ] **Power.** DC barrel with on-board regulation is cheaper and
      smaller than an ATX connector, and consistent with the BOM goal.
- [ ] **Rear I/O** within the 159 x 44.5 mm shield: HDMI, USB for HID,
      and little else — no RJ45, no VGA, no serial or parallel unless
      wanted for their own sake.
- [ ] **Socket area and height.** A 486 PGA socket plus heatsink is the
      tall, area-hungry item; a 386SX in PLCC or PQFP is neither. Worth
      checking against low-profile case lids before committing to a
      dual-socket board.
- [ ] ESP32 module placement and antenna keep-out.

## Design goal: reduced BOM at the motherboard layer

**Cost optimisation is a stated goal of the top-most (motherboard)
layer, and it means a reduced bill of materials.** Several decisions
below are consequences of it rather than independent choices, and should
be read that way.

Concretely, giving the ESP32 board controller time, configuration, block
storage and networking removes parts rather than adding software:

| function | discrete parts avoided |
|---|---|
| time / RTC | RTC chip, coin cell, battery holder |
| CMOS persistence | config EEPROM or SPI flash |
| networking | Ethernet MAC/PHY, magnetics, RJ45 |
| block storage | connector, media, and the drive itself |

The FPGA carries period-correct *register interfaces*; the parts those
interfaces used to imply do not have to exist. That is also why
peripherals are FPGA logic rather than discrete period chips — a
discrete 8254, 8259, 8042 and NE2000 is four packages and the board area
to route them, against LUTs and EBRs already paid for.

### Two controllers, not one

The machine has **two** microcontrollers, and they are not redundant in
the trivial sense — they sit in different places and fail differently:

| | ESP32 | VexRiscv soft-core |
|---|---|---|
| where | off-chip, on the board | inside the FPGA |
| reaches | NTP, network, block storage | whatever is on-chip |
| role | primary platform controller | **backup defaults / fallback** |
| BOM | one module | LUTs already paid for |

Concentrating time, configuration, storage and networking in the ESP32
would otherwise make it a **dependency for boot**: without it there is
no configuration, no time and no boot device. The soft-core answers
that. It is present whenever the FPGA is configured, so a fallback path
always exists, and it can serve *synthesised* defaults and run
diagnostics rather than only replaying a static image.

This costs no parts, which is consistent with the goal above.

**It also adds a role to the MCU.** It was a payload host — tiny386 is
one payload, chipset tests and diagnostics are others. It is now also
the fallback platform controller, and that role justifies the core
independently of any payload.

**The reset-exit vector's source is therefore "the platform
controller", either one.** `platform_cfg.c` already models it that way:
what is fixed is the content and the timing, not who supplies it or over
what bus. Nothing needs to change to accommodate this.

- [ ] **Settle the arbitration.** The natural shape is that the
      soft-core serves defaults immediately so the machine can always
      POST, and the ESP32's image overrides when it arrives — which
      answers the earlier "wait or proceed" question in favour of
      proceed. Confirm that, and decide what "catastrophic failure"
      detection looks like: a timeout, a heartbeat, or simply whichever
      controller writes last before reset-exit.
- [ ] Decide how much the fallback should provide. Enough to POST is one
      bar; enough to reach a diagnostic prompt without any off-chip part
      is a higher and more useful one.

## Decided: firmware configuration goes over fw_cfg, not CMOS

Configuration reaches the BIOS through the fw_cfg port interface
(`0x510`/`0x511`) rather than legacy RTC/CMOS registers. Implemented in
`sim/cosim/pc/fw_cfg.c` in [vexrv-cpu-oss](https://github.com/pawlex/vexrv-cpu-oss),
which has no counterpart in tiny386 — that
machine has no fw_cfg, and SeaBIOS falls back to CMOS.

In RTL fw_cfg is a selector register and a blob with an index, and its
contents can be generated at build time. A CMOS/RTC is battery-backed
state, BCD time and an alarm, mostly answering questions the platform
already knows. Adding a configuration item is a table entry rather than
a new register in a fixed 128-byte layout.

The CMOS device stays for time and the shutdown status byte.

- [ ] **fw_cfg is a good first peripheral to move to RTL.** It is the
      cheapest device in the machine and it has a frozen software
      reference to diff against. Moving it is an edit to
      `cosim_port_is_rtl()` plus a Wishbone slave.
- [ ] Decide what else it should carry beyond `etc/e820` — boot order,
      device presence, board revision. Currently only what SeaBIOS needs
      to size memory.

## Decided: CMOS is a compatibility surface, populated at reset-exit

fw_cfg (above) is the platform-to-firmware channel. **CMOS is a
different thing and both are needed**: guest operating systems read CMOS
directly and will never speak fw_cfg. tiny386's own `ide_fill_cmos()`
exists for exactly this — its comment says it fixes "MS-DOS
compatibility mode" in Win9x. SeaBIOS itself never reads those bytes
(`CMOS_DISK_DATA` is defined in `src/hw/rtc.h` and used nowhere).

### What the RTL block is

Measured by driving `0x70`/`0x71` with a computed pattern across all 128
registers: **119 of 128 are pure storage.** So the block is an index
register, a 128x8 SRAM, and a small BCD RTC. Only nine registers carry
behaviour:

| register | behaviour |
|---|---|
| `00,02,04,06,07,08,09` | BCD seconds/minutes/hours/weekday/day/month/year |
| `32` | BCD century — sits *inside* the NVRAM range, so the decode is not a clean split |
| `0A` | UIP read-only; divider and rate-select writable |

Plus `0B` control, `0C` interrupt flags (read-to-clear), `0D` valid-RAM,
and the IRQ8 periodic interrupt driven by `0A`'s rate select.

Storage is ~1 Kbit. One EBR is gross overkill; distributed RAM is the
sensible choice. Either is noise against 208 EBR / 83,640 LUT4.

### Persistence: an ESP32 on the board, not a coin cell

The motherboard layer carries an **ESP32 / WiFi module** as the board
controller. It obtains current time over **NTP**, so the RTC does not
need battery-backed timekeeping.

**Settled:** CMOS writes propagate to the controller, which decides what
persists. No battery-backed state on the FPGA side. The write-back path
is a software matter on the controller, is not on any critical path, and
is deliberately not modelled — it changes nothing about the machine the
guest sees.

Consequence for the model, and it is not cosmetic: the RTC is **seeded
once at reset from an external source and then free-runs**, rather than
continuously reflecting a host clock. A seeded RTC also makes
simulation runs **deterministic**, which the free-running host-time
version is not.

### One control channel: controller -> chipset -> fw_cfg -> SeaBIOS

The board controller feeds configuration to the chipset, which serves it
to the firmware over fw_cfg and materialises the guest's view in CMOS.

**This makes fw_cfg a RAM the chipset writes, not a build-time ROM** —
so boot order, drive geometry, advertised memory and board revision all
change *without re-synthesising a bitstream*. The store and its contents
are separate concerns: `fw_cfg.c` is the store, `platform_cfg.c` decides
what goes in it.

A useful consequence already visible in the model: advertised RAM need
not equal fitted RAM.

### Population: a chipset reset-exit initialisation vector

At reset de-assertion the chipset reads a configuration image and
populates the CMOS SRAM before the CPU begins executing.

- **Transport is TBD (SPI or I2C)** and nothing here assumes one. What
  is fixed is *when* (reset-exit, before first fetch) and *what* (a
  CMOS image plus an RTC seed) — not how it arrives.
- On ECP5 the fallback costs nothing: block RAM initial contents are
  part of the bitstream, so a default image can be preloaded with no
  logic at all.

Drive geometry is **not** an exception to this, though it looked like
one at first — see the block storage section below.

- [ ] **CMOS SRAM is the second RTL peripheral candidate**, after
      fw_cfg. Both then have a frozen software reference to diff
      against.
- [ ] Settle the config transport (SPI vs I2C) when the board
      controller interface is defined.

## Decided: block storage is backed by the ESP32

The board controller services the block-storage back end, as it does the
network. The guest-visible device stays a period-correct IDE/ATA
controller; what sits behind it is the controller's problem, and the
mechanics of that are software to be solved later.

**No spinning disks are supported.** That is a product decision (see
"Who this is for") and it removes the 40-pin header, the cable and the
drive bay along with the drive.

**This settles the drive-geometry question completely, and the reasoning
has moved twice — so the final position is worth stating plainly.**

The original concern was that geometry cannot come from a static image
because it is unknown until the drive answers IDENTIFY. That assumed a
*physical* drive being probed. With no physical drives at all, there is
nothing to discover: **the controller decides what IDENTIFY reports.**
Geometry is not derived, it is declared. There is no discovery step to
lose.

The only remaining question is which channel carries it, and dropping
PCI answered that (below): the legacy CMOS bytes, not a `bios-geometry`
fw_cfg file. Both of these travel the same path as everything else:

- `bios-geometry` as an fw_cfg file, which SeaBIOS already reads —
  `CONFIG_HOST_BIOS_GEOMETRY=y` is set in the fork's config, and
  `boot_lchs_find_ata_device()` looks devices up by a path such as
  `/pci@i0cf8/ide@1,1/drive@0/disk@0`. That matches where
  `piix3_ide_init(pcibus, piix3_devfn + 1)` puts the controller.
- the legacy CMOS type-47 bytes in the reset image, for guests that read
  them directly rather than going through the BIOS.

Nothing has to wait for IDENTIFY, and no SeaBIOS patch is needed.

Open:

- [ ] **Vendor `ide.[ch]` and `piix3_ide_init`**, add the port ranges
      (`0x1f0-0x1f7`/`0x3f6`, `0x170-0x177`/`0x376`) and the 16- and
      32-bit data paths back to the dispatch.
- [ ] Add `bootorder` and `bios-geometry` to the reset-exit image. Both
      are small text blobs; note the current 512-byte per-item cap.
- [ ] Decide whether to carry `ide_fill_cmos()`. SeaBIOS never reads
      those bytes (`CMOS_DISK_DATA` is defined in `src/hw/rtc.h` and used
      nowhere); the fork's comment attributes them to Win9x "MS-DOS
      compatibility mode". Out of scope for DOS, in scope if Windows
      ever is.
- [ ] A disk image for simulation. This is the last thing standing
      between the co-simulation and an actual DOS boot.

### Storage back end: the physical stores — OPEN, parked

**Not being solved now.** The shape below is settled enough to build on;
the remaining choices are lower priority than the socket question above
and are pinned here rather than pursued:

- NOR vs NAND, and the exact capacity
- read-only vs read-write regions, and where the boundary sits
- whether the ESP32 becomes FPGA configuration master
- copy-on-write overlay (NOR base, SD overlay) or a simpler split
- image format: `.iso` versus BIN/CUE, which is also the CD-audio decision
- caching policy between tiers 2 and 3, which is what keeps the
  synchronous ATA path inside its timeouts
- in-band image selection via an `emulink`-style channel, or web UI only


Two physical stores are expected, plus the network. Formats and
read/write policy are undecided; what follows is the shape and the
things worth settling early.

| tier | medium | capacity | role | latency |
|---|---|---|---|---|
| 1 | NOR (or NAND) | ~56 MiB usable | firmware, config, shipped DOS system, recovery — **read-only** | us, fastest in the machine |
| 2 | SD card | GB | **optical images**, writable overlay, cache for tier 3 | ~1 ms |
| 3 | network (SMB) | unbounded | the image library | ~100 ms |

**Tier 2 is not optional, and CD images are why.** A single disc image
is 650-700 MB as `.iso`, and nearer 750 MB as BIN/CUE once Red Book
audio tracks are included — which the CD-audio decision above argues
for. Tier 1 cannot hold even one, at any NOR size that is sensible to
fit. The tiers are complementary rather than alternatives:

- tier 1 is small, immutable and fast — the system
- tier 2 is large and writable — the content
- tier 3 is unbounded and slow — the library

#### Tier 1 may need no new part

**Both controllers already require NOR flash for their own reasons.** An
ESP32 module has integrated flash, and the ECP5 must load its bitstream
from SPI NOR at configuration time — that part is not optional. A
bitstream leaves useful room in a typical 16 Mbit/16 MByte device.

So the question is not "which flash do we add" but "can the flash that
has to exist anyway also carry the BIOS images, the reset-exit
configuration and a recovery set". That is the BOM-reducing answer and
it is consistent with everything else here.

- [ ] **Consider making the ESP32 the FPGA configuration master.** If
      the ESP32 owns the SPI flash and configures the ECP5 rather than
      letting it self-load, then: one flash, no bus arbitration between
      two masters, bitstreams updatable over WiFi, and a recovery
      bitstream becomes possible. It also fits the controller already
      being "the brains". The alternative — sharing one flash between
      ECP5 and ESP32 — needs a mux or arbitration and buys nothing.
- [ ] **RO vs RW is really two questions.** Recovery and golden images
      want to be read-only, because that is what makes the fallback
      trustworthy; configuration wants to be writable. Splitting by
      region rather than by device answers both.
- [ ] NOR vs NAND: NOR is the obvious fit at this size — byte
      addressable, no ECC, no bad-block management, no FTL. NAND only
      earns its complexity at capacities the SD card already covers.
      **The ECP5 configures from SPI NOR and cannot boot from raw NAND**,
      so a NAND choice means a second device regardless.

#### The real question: is the config ROM also bulk storage?

Measured on the actual part — LFE5U-85F, `ecppack`:

| | size |
|---|---|
| bitstream, measured uncompressed | **1,927,725 bytes (1.84 MiB)** |
| **budget: single boot** | **4 MiB** |
| **budget: dual boot** | **8 MiB** |
| left over on a 16 MiB NOR (dual boot) | 8 MiB |
| left over on a 32 MiB NOR (dual boot) | 24 MiB |
| left over on a 64 MiB NOR (dual boot) | 56 MiB |

The measurement sits comfortably inside the budget — 1.84 MiB against a
4 MiB ceiling leaves room for growth without revisiting the part.

(A trivial design compresses to 0.27 MiB, but that is mostly zeros and
not representative. A real design lands nearer 1.2-1.5 MiB compressed.)

**The stated danger is real but is a consequence of one choice, not of
bulk storage itself.** Corruption requiring a JTAG programmer only
follows if the *FPGA self-configures from the shared flash*. Two
mitigations, and the first removes the risk rather than reducing it:

- **ESP32 as configuration master.** If the controller pushes the
  bitstream into the ECP5 over SPI rather than the FPGA loading itself,
  a corrupted bitstream region is recoverable *over WiFi* — the ESP32
  refetches and rewrites it. JTAG stops being the recovery path. The
  ESP32's own firmware lives in its module's integrated flash, which is
  a separate device and never used for bulk.
- **Hardware write protection on the bitstream sectors.** NOR block
  protection and the `WP#` pin can make the bitstream region physically
  unwritable while the bulk region stays writable. Cheap, and it means
  bulk activity *cannot* corrupt configuration.

**Dual boot is itself most of the answer**, and the budget above already
reserves for it. ECP5 multiboot falls back to a golden image when the
primary fails its CRC — so a corrupted primary self-recovers, and the
ESP32 can then rewrite it. That holds *even if the FPGA self-configures*,
provided the golden image sits in write-protected sectors. Combined with
the `WP#` protection above, JTAG stops being the recovery path in every
case except physical damage to the device.

**What the config ROM should and should not carry:**

- **Should**, and this eliminates a part: bitstream and golden copy,
  BIOS and VGA BIOS images, the reset-exit configuration image, and a
  **read-only rescue system**. That last one completes the fallback
  story already decided for the soft-core — with it, the machine boots
  to something with no SD card and no network at all.
- **Should not** be the read-write C: drive. Two reasons: NOR costs
  orders of magnitude more per byte than SD, and **NOR erase latency
  (tens to hundreds of ms per sector) interacts badly with the
  synchronous ATA interface** — the same BSY-polling timeout hazard as
  the network path, but on the write side and unavoidable.

So it **eliminates a dedicated storage flash, not the SD card.**
Read-only bulk on NOR is excellent; read-write bulk on NOR is the wrong
medium.

#### 64 MiB NOR is readily available, and 56 MiB changes the role

With dual boot reserved, a 64 MiB part leaves **56 MiB** — which is not
"a rescue image" territory, it is *a shipped system* territory. A
minimal DOS with drivers and utilities is ~10-20 MB; a period 486 often
shipped with a 40-540 MB drive.

That buys a real product property: **the machine boots to a working DOS
with no SD card fitted and no network reachable.** Out of the box, and
after any failure of the other two tiers. It also completes the fallback
story end to end — soft-core serves defaults, NOR serves a bootable
system.

**And NOR is the *fastest* store in the machine, not the slowest.**
Quad-SPI NOR reads run at tens of MB/s; SD in SPI mode is a few MB/s,
and a period IDE drive managed 2-5 MB/s. The read-only tier is quicker
than everything above it — an inversion worth exploiting rather than
apologising for. Only erase and program are slow, which is exactly why
it stays read-only.

- [ ] **Consider a copy-on-write overlay: NOR base, SD overlay.** The
      guest sees one writable `C:`; reads fall through to NOR, writes
      land on SD. That gives a writable feel over an immutable base, and
      an SD failure loses only the changes rather than the system.
      Resetting to a known-good machine becomes "discard the overlay".

#### Tier 2: SD is slower than it needs to be, which is fine

Worth calibrating: **a period 486-era IDE drive managed roughly 2-5
MB/s.** Even SD in SPI mode outruns that, and the ESP32's 4-bit SDMMC
mode considerably so. The guest cannot tell the difference, and DOS
workloads are light.

**Reliability is the real concern, not speed.** Consumer cards have
opaque wear levelling and corrupt on sudden power loss. Mitigations are
architectural rather than heroic: keep golden images on tier 1, treat
the card as replaceable bulk media, and consider write-back caching with
an explicit flush.

#### Tier 2 as cache is what makes tier 3 safe

This closes the ATA-timeout risk flagged above. ATA is synchronous — the
guest polls BSY — and a ~100 ms network read is long enough to trip BIOS
and driver timeouts. **Caching network images onto the SD card turns a
100 ms path into a ~1 ms one**, and makes the network a library rather
than a live block device. That is a strong argument for the tiering
independent of capacity.

#### Image selection: in-band and out-of-band both have a use

- **Out-of-band** — the web UI. Requires nothing of the guest, and is
  the right answer for setup.
- **In-band** — the guest asks the controller to change images. This has
  precedent and existing code: tiny386's **`emulink`** device is exactly
  such a channel (ports `0xf1f0`/`0xf1f4`), and the fork's SeaBIOS patch
  already uses it for a paravirtual floppy.

The case that justifies in-band is **multi-disc software** asking for
the next disc without leaving the application. Out-of-band works there
too, if reaching for a phone mid-game is acceptable.

- [ ] Decide whether in-band selection is in scope. It needs a guest-side
      utility; out-of-band needs nothing.

### ATAPI CD-ROM: emulated by the controller, network-backed (TBD)

**No physical optical media either.** Nobody wants to maintain a shelf
of discs, so the ATAPI device exists to mount *images*, not to read
discs. Presented to the guest as an **ATAPI device on the IDE channel**,
emulated by the ESP32, backing store likely over the network (SMB),
mounted through a web UI on the controller. Mechanics TBD.

That makes the storage story uniform: **no physical media anywhere, every
path controller-served.** No drive, no connector, no cable, no bay, no
tray.

Two things already settled in our favour:

- **No BIOS work.** SeaBIOS boots El Torito already — QEMU's `isapc`
  attaches `DVD/CD [ata1-0: QEMU DVD-ROM ATAPI-4 DVD/CD]` on the ISA
  IDE channel with no PCI in sight. Another inherit-don't-own case.
- **No extra front end.** ATAPI is a packet interface carried over the
  same IDE registers, so it costs nothing beyond the IDE controller
  already planned. The fork's `ide.c` has `ide_attach_cd()` alongside
  `ide_attach()`.

Two things to watch:

- [ ] **Latency against a synchronous interface.** ATA is synchronous —
      the guest polls BSY and waits. A network-backed read over WiFi can
      be hundreds of milliseconds, and BIOS and driver timeouts exist.
      Read-ahead and caching on the controller are the obvious
      mitigation, but this is a real failure mode rather than a
      performance nicety, and it applies to the hard disk path too.
- [ ] **Booting is not using.** El Torito gets the machine started from
      a CD; reaching the drive from DOS afterwards needs a CD-ROM driver
      plus MSCDEX in the guest. That is guest software rather than
      hardware, but it should not come as a surprise when someone
      expects a drive letter. The web UI could hide it by also offering
      a floppy image carrying the driver.
- [ ] **Image format, and CD audio.** Worth settling early because it
      is cheap now and awkward later. **`.iso` carries a data track
      only.** A large share of the period CD software worth running uses
      Red Book audio tracks, which needs BIN/CUE or CHD instead.
      Supporting only `.iso` quietly excludes that content.

      The architecture makes this *easier* than the original, not
      harder: CD audio historically went out an analogue cable from the
      drive to the sound card, and here both ends are software on the
      controller, so the tracks can simply be mixed digitally.
- [ ] **Media change.** Mounting and unmounting through the web UI is a
      media-change event, and ATAPI has unit-attention semantics that
      DOS drivers rely on. The trigger is a web request rather than an
      eject button, but the guest-visible behaviour still has to be
      right.

## Decided: networking is NE2000, serviced by the ESP32

The board controller provides the network. The guest-visible device is
an **NE2000** — "good enough for DOS", which has packet drivers and
mTCP for it. ISA at `0x300`, IRQ 9.

**This is a vendoring job, not a write.** The fork's `ne2000.c` already
carries three backends behind one seam (`net_open`, `qemu_send_packet`,
`ne2000_step`): `USE_TUNTAP`, `USE_SLIRP`, and an ESP32 path. The ESP32
branch already sources its MAC from the WiFi station address:

```c
#else
    esp_read_mac(s->macaddr, ESP_MAC_WIFI_STA);
#endif
```

So the intended hardware arrangement is already implemented upstream.

Open:

- [ ] **Vendor `ne2000.[ch]`** and add it to the port dispatch
      (`0x300-0x30f`, `0x310` ASIC, `0x31f` reset) and to
      `pc_machine_poll()`.
- [ ] **MAC address should come from the reset-exit vector**, not a
      compile-time constant. It is configuration like everything else,
      and the NE2000's 16-byte PROM — the MAC duplicated byte-wise with
      a `0x57 0x57` signature — is populated exactly the way the CMOS
      image is. `isa_ne2000_init()` takes no MAC argument today, so this
      needs one small API addition.
- [ ] **Pick the simulation backend.** slirp needs no privileges and
      gives the guest outbound access; tuntap is closer to real hardware
      but needs setup. Neither matches the ESP32 path, so this is a
      testbench choice, not a design one.
- [ ] Packet buffer is 16 KiB — one EBR.



## Design goal: modern memory — which makes the cache the central choice

**The main store should be a modern memory part.** What "modern" means
precisely is **not yet defined**, and this section records the goal and
the tension it creates rather than a decision.

Two characteristics are wanted:

- **Synchronous, not asynchronous.** Clocked, pipelined, with a defined
  command protocol — not the FPM/EDO-style asynchronous DRAM of the
  period, with its `RAS`/`CAS`/`OE`/`WE` timing to be met in the
  controller.
- **Burstable.** Long transfers amortised against a fixed setup cost.

### The mismatch, stated plainly

**Modern memory is bandwidth-oriented. A 386 or 486 is latency-bound.**
They want opposite things, and this is the central problem of the memory
subsystem rather than an implementation detail.

| | what it does |
|---|---|
| 386SX | **no burst at all.** Every access is its own address-then-data cycle, 16 bits wide |
| 486 | bursts **only** for cache line fills — four transfers, 16 bytes. Everything else is a single cycle |
| modern synchronous memory | pays a fixed setup cost (row activate, CAS latency, bus turnaround), then streams cheaply |

So the CPU issues exactly the access pattern that modern memory is worst
at: **small, frequently random, one at a time.**

### The trap

**Bursting buys bandwidth and usually costs latency.** Wider bursts,
deeper pipelines and higher clocks all improve throughput while making
the first word arrive later. A 386SX asking for two bytes does not care
about GB/s — it cares how many nanoseconds pass before the data is
there. Optimising the memory subsystem on the obvious metric makes the
machine *slower*.

Some rough calibration, illustrative rather than exact:

- A 386SX at 25 MHz has a 40 ns clock, so a two-cycle access is an ~80 ns
  budget.
- An Am5x86 on a 33 MHz bus has a 30 ns clock; a four-transfer burst at
  2-1-1-1 is five cycles, roughly 150 ns for 16 bytes.

Against modern parts those budgets are generous — **but only if the row
is already open and the controller adds little of its own.** A random
access that misses the open row pays activate and precharge on top, and
that is the case the CPU generates most.

### Why the cache is therefore the important design choice

**The cache is the impedance matcher between the two.** It is what turns
the CPU's small, random, latency-sensitive accesses into the memory's
preferred large sequential ones, and it is the only place that
conversion can happen.

- On a hit, memory latency is invisible.
- On a miss, a line fill is exactly the long sequential burst the memory
  wants — so the miss path is *where the memory's strength is used*.
- Line size is the knob with the sharpest trade: longer lines burst more
  efficiently and waste more fill on poor locality.

**Memory choice and cache design are therefore one decision, not two.**
Choosing a burst-oriented part commits to a cache whose line size and
fill policy are matched to that part's efficient burst length. Choosing
them separately produces a controller that is fast on paper and slow in
the machine.

This also connects to a problem already recorded: the Am5x86's
**write-back L1** means the CPU can hold dirty lines the chipset does not
have, so write policy and coherency are part of the same decision
(see the Am5x86 bus section above).

### Candidates already in the tree

Observation, not decision — the KiCad libraries carry symbols for both a
parallel **PSRAM** (`IS66WVE4M16`) and a **HyperRAM**
(`IS66WVH8M8ALL`). Those two bracket the trade neatly:

- **HyperRAM** is extremely pin-efficient, which matters against an FPGA
  I/O budget, but has high initial latency and is strongly
  burst-oriented — the extreme case of the tension above.
- **Parallel PSRAM** costs pins and gives lower access latency.

The right answer depends on the cache, which is the point of this
section.

- [ ] Define what "modern" means concretely, **together with** the cache
      line size, associativity and write policy — not before them.
- [ ] Establish the latency budget from the CPU side first, since that is
      the fixed constraint; bandwidth is the free variable.
