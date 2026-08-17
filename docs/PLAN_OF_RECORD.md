# Plan of record

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

## Status: nothing here is built, and almost nothing is chosen

**Read this first.** *Plan of record* is meant literally: this is the
currently-agreed plan, and it is expected to change. It is not a
specification and it is not a commitment.

No hardware exists. Nothing is committed to, nothing is irreversible,
and several conclusions in this document reversed within the
conversation that produced them. What exists is a co-simulation, some
measurements, and a set of things that have been **ruled out**.

That is not a weak position. **Ruling something out is forward
progress, and the more durable kind** — an elimination backed by a
reason survives new information, where a selection made early usually
does not. "PCI is out, because the bus is 16-bit and SeaBIOS supports
non-PCI as a first-class configuration" stays true regardless of what
comes next. "We will use serial PSRAM" would not.

So the headings are labelled by what they actually are:

| label | meaning |
|---|---|
| **Requirement** | given as a constraint, not derived here. Not up for re-derivation. |
| **Eliminated** | ruled out, with a reason intended to outlive the moment |
| **Direction** | the current preference and its reasoning. **Not settled.** |
| **Design goal** | a property the machine should have |
| **OPEN** | actively unresolved, and blocking something |

A record is allowed to hold two positions in tension; a specification is
not. **This is a record.** Where two sections disagree — and some do,
marked *Contested* — that is the document working correctly, not a
defect to be tidied away.

## Requirement: one soldered CPU, SX-class bus, 3.3 V

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

**A.** **Never assert `KEN#`.** External memory is uncacheable, the L1 is
   effectively disabled, coherency evaporates. Simplest possible chipset
   — and throws away most of what the 133 MHz part was bought for.
**B.** **Cacheable but no burst.** Assert `KEN#`, answer each of the four
   transfers with a normal ready rather than `BRDY#`. Line fills cost 4
   cycles instead of a burst, but the cache works. Still needs a
   coherency answer.

**C.** **Selective cacheability plus snooping.** `KEN#` asserted only for
   regions no other agent writes, snooping via `AHOLD`/`EADS#` for the
   rest. Fastest and hardest. A behavioural sketch of this one exists —
   see [BIU_MEMSS.md](BIU_MEMSS.md), **Concept C** — which is an
   exploration, not a proposal.

Note (A) and (B) make the *coherency* question mostly disappear, which is
worth weighing: the difficulty is not evenly distributed across the
options.

**Deliberately deferred.** Burst and caching support are not on the
critical path to a first board. The soft core makes the hardware useful
without them, so this is scheduled after production rather than before
it — and it is another reason the memory subsystem stays open, since the
cacheability and coherency policy is downstream of what sits behind the
BIU.

- [ ] **Masked writes, or full cache-line writes with read-fill?**
      Does the memory controller honour byte enables via `DQM`, or does it
      only ever write whole lines — turning any partial write into a
      **read-modify-write**?

      **The cost of getting it wrong is latency, on the path the whole
      design is organised around.** An RMW pays a full read before the
      write: `tRCD` + `CL` ≈ 60 ns at 66 MHz, against a 30 ns CPU cycle.
      **`DQM` masking costs nothing** — the two pins are already in the
      budget and SDRAM supports it natively.

      **The 32→16 split maps byte enables cleanly.** A 32-bit CPU write is
      two 16-bit SDRAM cycles, so `BE0`/`BE1` become the first cycle's
      `DQM[1:0]` and `BE2`/`BE3` the second. No encoding problem.

      **But it is coupled to the cache policy below, and may be moot.**
      With **write-back plus write-allocate**, partial writes land in the
      cache and lines are written back whole — `DQM` is then barely
      exercised. With **write-through, no-allocate, or any uncached
      region**, partial writes reach memory directly and masking becomes
      essential. **Decide the cache policy first; this follows from it.**

      **The video path does not share the question.** QSPI PSRAM is
      byte-addressable — a write command carries a byte address — so the
      write-combining buffer flushes only its dirty bytes with no masking
      and no RMW. **This is an SDRAM-side question only.**

      **Worth exploring — a write-allocate queue.** Rather than draining a
      partial write immediately, hold it briefly and see whether adjacent
      writes follow. Sequential patterns — `REP STOSD`, `memcpy`, structure
      initialisation — then coalesce into **full lines, which need neither
      masking nor RMW.**

      **Not write-back caching.** No tag array, no coherency claim, no
      snoop obligation outward; a bounded queue that drains eagerly on
      idle, on fill, or on a read that touches it. It sits *below* the
      cache and therefore does not complicate the cache policy — which is
      what makes it explorable independently of the decision above.

      > **The same structure as the video write-combining buffer**, one
      > level over: lines, dirty masks, flush when full. **Two instances of
      > one design rather than two designs** — worth building it
      > parameterised.

      **One difference from the video instance — and it is not read
      volume.** The video memory controller is **read-dominated**: scanout
      streams ~47 MB/s at 1024×768 and is by far its heaviest traffic.
      What is rare there is *host* reads coming back up.

      **The distinction that matters is which reads must be coherent with
      pending writes:**

      | | dominant reader | needs coherency with the buffer? |
      |---|---|---|
      | **video MC** | **scanout** | **no** — a pixel one frame late is invisible |
      | | host read-modify-write | yes, but rare → *flush-on-read* is cheap |
      | **main memory MC** | **CPU** | **yes, always** → must snoop |

      > **So "flush on read" on the video side means *host* reads only.**
      > Applying it to scanout would flush the buffer on every burst and
      > **destroy the write combining it exists for.** The dominant reader
      > deliberately bypasses the buffer entirely.

      On the main-memory side the dominant reader is also the one needing
      coherency, so **snooping is mandatory** — at four to eight entries a
      comparator array, not a CAM in the expensive sense.

      **It reduces how often masking is needed; it does not remove the
      need.** Genuinely scattered byte writes still reach memory alone.

      > **HARDWARE DECIDED: `DQM[1:0]` are *present* — routed to the
      > connector and to the FPGA.** Two pins, already counted inside the
      > group of 40.
      >
      > **Present, not enabled.** Whether the controller drives them
      > meaningfully is an RTL question and stays open below. **This does
      > not wait on the protocol** — the pins are the irreversible layer,
      > the protocol is not, so the board carries the capability and the
      > RTL decides whether to exercise it. Same ordering the mezzanine
      > specification follows.

- [ ] **OPEN — where does the write-allocate queue sit in the coherency
      protocol?** This is the part still to reconcile, and it is separate
      from the cache policy question below.

      **The queue is a third place data can live** — after the 486's
      internal write-back L1 and the FPGA's L2 — and anything that reads
      memory must account for it.

      | reader | obligation |
      |---|---|
      | CPU reads | snoop the queue — comparator array, 4–8 entries |
      | the L2 | ordering against a line that is both cached and queued |
      | external masters / DMA | must not read stale memory behind a pending write |
      | video scanout | **none** — separate PSRAM, never CPU traffic |

      **Three shapes to choose between:**

      1. **Flush before any external access.** Simplest and obviously
         correct; costs latency on every DMA touch.
      2. **Snoop the queue alongside the L2.** No flush penalty, more
         logic, and the queue joins the `AHOLD`/`EADS`/`HITM`/`INV`
         machinery rather than hiding beneath it.
      3. **Keep it non-coherent and CPU-region-only.** Cheapest, but
         limits where it may be used and needs the boundary defined.

      **Decide this before the queue is built, not after** — it determines
      whether the queue is a private optimisation beneath the coherency
      domain or a participant inside it, and that is structural rather than
      tunable.

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

### One BIU per CPU variant, sharing everything below it

**The BIU is per-variant, not universal.** The SX-class BIU omits `KEN#`
and burst because its CPU has neither; the Am5x86 BIU carries them from
the start, because retrofitting burst restructures a front end rather
than extending it.

This follows from decisions already made rather than adding a new idea:

- **The cache is already the abstraction boundary.** If DRAM width is
  invisible *above* it, CPU bus protocol should be invisible *below* it.
  Swappable BIUs is that same principle applied upward.
- **Only one is instantiated per bitstream**, so two source modules cost
  no area — the "bitstream difference, not a redesign" argument again.
- **It matches the sequencing.** The SX BIU can be finished, verified and
  shipping while the Am5x86 one is still being developed. A single
  unified BIU could not be: the easy path would be blocked on the hard
  one.
- Each module is smaller, with a smaller state space, and is therefore
  easier to verify than one conditional-laden module spanning both.

#### The requirement this creates

**Every BIU must present an identical interface to L2.** If the two hand
the cache different contracts, the variation has not been eliminated —
it has been pushed downstream into the cache, which then has to handle
both. That buys two front ends *and* a more complicated back end, which
is worse than either alternative.

So the L2-facing interface is fixed **first**, and the BIUs conform to
it. It must not emerge from whichever BIU happens to get written first.

#### The divergence risk, which needs active care

**Address decode, region cacheability and the posted-write buffer are
common to both BIUs.** Copy-pasted into two modules they *will* diverge
silently — one receives a fix the other does not, and the difference
surfaces as a bug in whichever variant was not being tested that week.

They want factoring into shared blocks, leaving each BIU as genuinely
only the bus-protocol layer. **This is the specific thing that makes or
breaks the multi-BIU model**, and it is a discipline rather than a
design: nothing prevents the duplication except deciding not to.

#### SX-class parts may have L1 — design for its presence

**Settled: assume an SX-class CPU may carry an L1.** The reference for
the capable end is the **TI 486SXLC2** — 386SX-pin-compatible, but with
an on-die cache and clock doubling. So "SX-class" describes the *bus*,
not the absence of a cache, and the SX BIU cannot assume there is
nothing above it.

That reopens the L1 write policy question on the cheap variant. SX-class
caches differ by vendor in whether they are write-through or write-back,
and the difference is not cosmetic: **write-through makes the coherency
problem largely vanish on that variant; write-back reproduces the
Am5x86's problem on the cheap CPU.** Unverified for the specific parts.

##### Settled: only cached SX-class parts are designed for

**Assume L1 is present.** The SX BIU is built for a CPU that has a
cache, and no BIU variant is written for an uncached part.

The 3.3 V requirement had largely decided this already. Uncached
SX-class parts are overwhelmingly **5 V**, which puts them outside the
supported set on voltage grounds before cache is considered at all — the
Intel 386SX-16 among them. The lone 3.3 V uncached candidate is the
**AMD 386SXL**, and holding a design decision open for a single part of
uncertain availability is not a trade worth making.

Nor would anyone reasonably choose an uncached 386SX-16 on this
platform, given what else it can be built with.

**What this buys:** `KEN#` and `FLUSH#` are always present, the SX BIU
has one shape rather than two, and the multi-BIU set stays at two
members rather than three.

**What it does not do is foreclose anything.** The CPU is soldered, so a
board is built for one part regardless; an uncached part would simply
leave the cache control signals unused, which the BIU can be
reconfigured for if it ever matters. This is "not designed for", not
"cannot work".

##### One tension worth naming, not reopening

The requirement provenance records **two** machines as the reason the
project exists: a 386SX as a first computer, and a 486SLC2 as the first
upgrade. This decision keeps the SLC2 class and excludes the plain 386SX
— on voltage and availability, which are real constraints rather than
preferences.

Recorded so it is a conscious trade rather than a silent drift. If the
386SX specifically matters more than the reasoning above, this is the
decision to revisit, and the cost of revisiting it is one more BIU
variant.

- [ ] **Compare the datasheets across the cached SX-class parts** — TI
      486SXLC2, Cyrix 486SLC, IBM 486SLC2 — and establish whether their
      pinouts actually agree. The original framing of this task was
      "most advanced versus least advanced"; with the uncached parts out
      of scope, the real question is whether the *cached* parts are
      mutually compatible.

      The trap remains renaming rather than addition: cache and
      power-management control on these parts lands on pins the base
      386SX pinout used differently or left unconnected. A pin that is
      NC on one part and `FLUSH#` on another is invisible in a pin-count
      comparison and fatal in layout.

      **This is precisely the case the "route every CPU signal to the
      FPGA" rule exists for.** The BIU can be told which part is fitted
      at bitstream time; the PCB cannot be told anything after
      fabrication.

#### What this resolves

- **The burst contradiction dissolves.** "Structured so bursts can be
  added later" and "bursts change what the front end is" are both true,
  scoped to different BIUs. Neither statement was wrong; the assumption
  of a single BIU spanning both variants was.
- **The SX cost becomes precise.** Not "2x or 1.2x" — **the BIU doubles,
  the memory subsystem does not.** Two front ends, one cache, one LLC,
  one memory controller.

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

## Eliminated: PCI (follows from the above)

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

## Direction: HDMI on-board, framebuffer in external DRAM

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

### OPEN: can HDMI be driven the cheap way, and does video share memory?

Two questions, in order, because the first gates the second — and the
second gates the memory part, which gates the cache.

#### 1. Can "fake TMDS" from the ECP5 actually drive a display?

Driving the DVI/HDMI differential pairs directly from FPGA outputs, with
no transmitter chip. If this does not work the FPGA video path does not
exist, a real CL-GD5428 becomes the only display option, and scanout
leaves the memory subsystem entirely.

**Starting points, links and the arithmetic are in
[FAKE_TMDS.md](FAKE_TMDS.md).** Short version: the ULX3S is an ECP5-85F
board that already does this over a TMDS-tolerant LVDS connector using
the ECP5's own `ODDRX1F`, with two open implementations to work from —
so **no custom hardware is needed to answer the question.**

- [ ] Run the feasibility study. Not started, and not urgent *provided*
      the decoupling below is taken.

#### 2. If FPGA video exists, does its framebuffer share CPU memory?

This is the coupling that makes the question urgent rather than
cosmetic:

| video path | framebuffer | scanout on the memory subsystem |
|---|---|---|
| CL-GD5428 | the chip's own DRAM | **none** |
| FPGA to HDMI | external DRAM | **~135 MB/s** at 1024x768x24 |

**If both paths are options on the same PCB, the shared case wins by
default** — the board must support FPGA video whether or not a GD5428 is
fitted, so the memory has to carry scanout regardless.

The chain worth keeping in view: **which video output -> which memory
part -> what the cache must do.** An apparently peripheral display
decision sits upstream of the memory subsystem and the cache.

#### Governing principle: do not design the memory subsystem around video

**The video unit is a question mark, and the memory subsystem must not
be designed around a question mark.** Everything downstream of the
memory choice — the cache, the LLC, the thing this project is actually
for — would then be resting on an unresolved display decision.

Two ways out, and they are not exclusive:

- **Collapse the question mark early.** Prove or disprove fake-TMDS
  output on existing hardware, before it can constrain anything. Cheap,
  and see the prior art below.
- **Decouple permanently: give video its own memory channel.** Serial
  parts make an extra channel nearly free in pins, and unpopulated
  footprints cost nothing in BOM. The two clients then separate
  entirely — CPU memory chosen for latency, video memory for bandwidth,
  both video paths supportable, no arbitration, and **no dependency of
  the memory subsystem on the video decision at all.**

The second is the stronger answer, because it holds even if the video
decision changes later. It reduces a coupled architectural question to a
pin-assignment decision.

#### Proposed resolution: video never touches the SDRAM

**The objection to sharing is not bandwidth.** SDRAM has ample bandwidth for CPU and video together. **The objection is what
sharing does to the memory controller** — and to the ordering this
document already commits to.

- **It breaks the stated design order.** *"Establish the latency budget
  from the CPU side first; it is the fixed constraint."* **A latency
  budget cannot be fixed if a scanout engine may interrupt it.** Sharing
  turns the fixed constraint into a variable one.
- **The two access patterns are pathological for each other.** Scanout is
  long and sequential; CPU access is short and random. In a page-based
  memory **each closes the other's open row**, so the cost appears as
  latency variance rather than as a bandwidth shortfall that could be
  budgeted.
- **It makes the arbiter a real-time problem.** Video has hard deadlines
  and the CPU does not, so video must win — which means CPU latency is
  set by video activity, and contention bugs only appear under load.

**Both private-memory options are already on the board:**

| | capacity | scanout ceiling | cost |
|---|---|---|---|
| **BRAM** | 468 KB total | 640×480×8 = **300 KB, 64% of it** | competes directly with the L2 cache |
| **QSPI PSRAM** | 8 MB | ~38 MB/s → **640×480×8 at ~66% used** | half-duplex; CPU writes need combining |

##### Decided: two QSPI PSRAMs, ganged ×8

**One ×4 device is a little shy; two are comfortable.** They share `CLK`
and chip select — being ganged, they behave as one device — with separate
data nibbles. The FPGA drives both nibbles identically during command and
address, then reads **8 bits per clock** and assembles bytes from the two
halves. The NOR stays on the same bus using `D[3:0]` and its own select.

| | pins |
|---|---:|
| **common `CLK`**, shared by all three devices | 1 |
| PSRAM A — `D[3:0]` + `CS_A` | 5 |
| PSRAM B — `D[7:4]` + `CS_B` | 5 |
| NOR — own `D[3:0]` + `CS_N` | 5 |
| **total** | **16** |

**The NOR gets its own data lines.** Video scanout is continuous and
real-time, so sharing wires with the flash means a NOR read can stall a
scanout burst — **a visible artifact, not a latency statistic.** The
common clock is retained: all three run at the same rate and ignore it
while deselected, so the separation costs data lines and selects rather
than a second clock domain.

##### The framebuffer is not a coherency domain

**The consumer does not care**, and that single fact carries more of this
design than it first appears.

**A stale read differs in *category*, not degree:**

| | stale read means |
|---|---|
| main memory | wrong computation — silent corruption, wrong results, possibly a crash |
| **framebuffer** | **one frame shows old pixels** — a tear, gone on the next refresh |

**So scanout neither snoops nor flushes.** No comparator on the hot path,
no stall waiting for a buffer to drain, and **the real-time deadline is
protected structurally rather than by careful arbitration.** The write
buffer is free to be as lazy as it likes — which is precisely what makes
it coalesce well.

**This is the period contract, not a compromise.** Video hardware never
promised coherency. That is why `while (inp(0x3DA) & 8);` exists — a DOS
programmer waits for vertical retrace because synchronisation was always
the software's job. **A program that wrote during active scanout tore on
a real VGA, and will tear here, for the same reason.** Matching that is
authenticity rather than laziness, and any driver writer already knows
the rule: **get the frame into memory before scanout reaches it, or own
the result.**

**The boundary is precise: coherency is required where data is *computed
on*, not where it is *displayed*.** A host read-modify-write — XOR
sprites, masked blits — is arithmetic and must see written data. That is
why host reads flush the buffer and scanout reads bypass it.

> **And it is what made the single-master architecture possible.** Had the
> framebuffer required coherency with the CPU's view of main memory,
> giving video its own memory would have created a coherency problem
> spanning two controllers. **Because it does not, the separation is
> free** — the whole private-video-memory decision rests on this property.

##### Clock it at 66 MHz — CPUCLK × 2, the SDRAM domain

**Ganged ×8 delivers one full byte per data clock.** At **66 MHz that is
~62 MB/s effective**, which meets the scanout requirement with margin —
and 66 MHz is not chosen for the arithmetic. **It is CPUCLK × 2, the
clock the SDRAM already runs on.**

- **One memory clock domain** for both memories, rather than an 84 MHz
  oddball beside a 66 MHz one.
- **Fixed phase relationship to the CPU**, which is the property the
  memory section already insists on rather than treating clocks as
  independent.
- **Well below the part's 144 MHz ceiling**, so the interface is run
  conservatively — good for signal integrity, and at 66 Mb/s per pin it
  is trivially inside 1× gearing on **any** bank.

**Burst length is set by `tCEM`, not by the 1 K page.** Choose a
power-of-two that divides 1024 *and* fits inside `tCEM`, and the wrap
boundary is never reached — the wrap behaviour becomes unreachable by
construction rather than something to work around.

| burst | clocks + 14 overhead | duration | verdict | effective |
|---:|---:|---:|---|---:|
| 256 B | 526 | 7.97 µs | at the 8 µs limit — no margin | 64.2 MB/s |
| **128 B** | 270 | 4.09 µs | **safe at 85 °C — chosen** | **62.6 MB/s** |
| 64 B | 142 | 2.15 µs | safe at 105 °C as well | 59.5 MB/s |

**The result is robust: 59–64 MB/s across the whole practical range**, so
the ~60 MB/s planning figure holds whichever burst size and temperature
grade are finally used. **Take 64 B if the 105 °C grade is fitted** — it
costs 5% and removes a thermal dependency.

**Burst boundaries double as preemption points.** `CS` rises every 128
bytes regardless, so pending CPU writes are slotted between scanout
bursts with no interrupt logic and no partial-burst abort. At 640×480,
scanout occupies ~31% of the device, leaving room for roughly two write
bursts between each scanout burst.

##### Decided: a write-combining buffer. Open: its width

**The buffer is wanted** — writes must be absorbed while scanout is
active, and the arithmetic below shows there is no tolerable alternative.
**What waits on the part survey is one number: the line width.**

> **Design rule: line size ≡ burst length.** They cannot be chosen
> independently.
>
> - **Line larger than burst** — a full line needs several bursts,
>   introducing partial flushes and the bookkeeping that goes with them.
> - **Line smaller than burst** — a burst cannot be filled from one line,
>   so several must be gathered, wasting burst capacity on every flush.
>
> **So the survey does not merely inform this buffer, it dimensions it.**
> That is why the constant is worth getting right before the RTL is
> written rather than after.

**Why something is needed.** The PSRAM is half-duplex, so a CPU write
arriving mid-burst waits for the burst to finish — **~4 µs at 128 bytes,
about 135 CPU clocks at 33 MHz, on every write.** That is not survivable
for software that draws directly to video memory, which is all of it.

**Sketch: a write-combining buffer whose line size is the burst size.**

```
4 lines × <burst> bytes, each with { base address, dirty mask }
  CPU write  → hits an open line, or allocates one
  line full  → flush as a single burst write
  no line    → evict LRU
```

Matching line to burst is the point: `REP STOSD`, the common DOS
full-screen fill, then coalesces into whole-burst writes rather than
dozens of separate command and address sequences.

**Cost is negligible** — one `DP16KD` covers data and tags, **1 block of
208**, so it does not meaningfully compete with the L2.

**Depth is invariant under the survey; only width moves.** A 486 at
33 MHz sustains a 32-bit write every 2 clocks — ~60 ns, ~66 MB/s — so the
writes arriving during one scanout burst are:

| burst | duration | writes arriving | bytes | lines needed |
|---:|---:|---:|---:|---:|
| 64 B | 2.15 µs | ~36 | 142 | **2.2** |
| 128 B | 4.09 µs | ~68 | 270 | **2.1** |

**Both land at ~2.2 lines**, because accumulation and burst duration
scale together. **Four lines is comfortable either way**, so the depth
decision does not depend on the survey outcome — only the width does.

**Two coherency cases, wanting different answers:**

- **Scanout need not snoop it.** A pixel one frame late is invisible, and
  is what period hardware did anyway. Do not build that path.
- **CPU reads must see buffered writes** — period software does
  read-modify-write on video memory for XOR sprites and masked blits.
  Simplest correct rule: **a CPU read of the framebuffer region flushes
  the buffer first.** Reads there are far rarer than writes.

**What it does not fix**, and should not be expected to: sustained
full-rate writing still throttles. Scanout takes ~31% of the device at
640×480, leaving ~43 MB/s for writes against a 486's ~66 MB/s of
back-to-back `STOSD`. A full-screen clear therefore runs ~35% slower than
the CPU could manage alone — **bounded and predictable, versus 135-clock
stalls on every write without it.**

##### Open — survey QSPI PSRAMs for a lowest common denominator

**Do not design against one vendor's part.** The controller should be
portable across manufacturers, so the constants must be the worst case
across a candidate set rather than the best case of a favourite.

- [ ] **Survey the field** — AP Memory `APS6404L`, Espressif
      `ESP-PSRAM64`, ISSI serial PSRAM, and the Chinese second sources —
      and record, per part: **page size, `tCEM` by temperature grade, max
      QPI clock, wrap behaviour, dummy-cycle count, command set, and
      supply voltage.**
- [ ] **Take the minimum of each**, not the typical.
- [ ] **Parameterise the controller** — burst length, dummy cycles, page
      size and the QPI-entry sequence belong in parameters or a small
      init table, **not hardcoded in the state machine.** A different part
      should be a constant change, not a redesign. Vendor initialisation
      sequences differ more than anything else.

**Preliminary — the LCD looks close to free.** Taking the worst values
already seen (1 K page, `tCEM` 3 µs at 105 °C):

| | value | result at 66 MHz |
|---|---|---|
| safe burst under 3 µs `tCEM` | **64 B** | 142 clocks, 2.15 µs |
| effective throughput | | **59.5 MB/s** |
| against the 128 B best case | | 62.6 MB/s — **a 5% difference** |

**So designing for the lowest common denominator costs about 5% and still
meets the ~60 MB/s target.** The survey is therefore expected to move a
constant rather than the architecture — but it should be run before the
constant is fixed, not after.

##### The separate chip selects are the useful part

The two PSRAMs have **independent selects**, not a shared one, and that
single extra pin buys a choice the RTL can make at runtime:

- **Assert both together — ganged ×8.** 8 bits per clock, **~60 MB/s
  streamed**, which is the scanout figure everything above is designed
  around.
- **Assert them separately — two independent ×4 devices.** ~30 MB/s each,
  but **scanout and CPU writes can then proceed concurrently** on
  different devices.

That second mode **eliminates the half-duplex contention outright** rather
than buffering around it: video streams buffer A from one device while
the CPU draws buffer B on the other, and they swap at vblank. Double
buffering falls out of the wiring instead of costing bandwidth.

30 MB/s streamed still covers 640×480×8 (18.4 average) comfortably. So the
choice is **bandwidth or concurrency, decided in the bitstream** — and
both remain available on the same board.

**~60 MB/s streamed.** Design against the *average* rate, not the peak:
active video is only ~73% of frame time, and the line buffer absorbs the
blanking gaps.

| mode, 8 bpp | peak | **streamed average** | at 60 MB/s |
|---|---:|---:|---|
| 640×480 @60 | 25.2 | **18.4** | 31% |
| 800×600 @60 | 40.0 | **28.8** | 48% |
| 1024×768 @60 | 65.0 | **47.2** | 79% |
| 800×600 @60, 16 bpp | 80.0 | **57.6** | 96% — the ceiling |

**Two consequences beyond the bandwidth.**

- **It largely dissolves the write-combining problem**, which was the real
  objection to a single device. At ~31% utilisation for 640×480 there is
  two-thirds of the device free for CPU framebuffer writes, turning a hard
  real-time buffering problem into an ordinary one.
- **It moves FPGA video from "DOS modes only" to genuine SVGA**, which
  changes what the CL-GD5428 mezzanine is for — from *the* video answer to
  a period-authenticity option.

**Capacity is irrelevant and free:** 16 MB against the **2 MiB** the
framebuffer actually wants, which is itself period-correct — GD5428-era
cards shipped 512 KB to 2 MB.

- [ ] **Budget consequence: 198 → 202, leaving 3 spare.** That is
      uncomfortably tight, so this **effectively decides the `A24-A31`
      pin-saver** (194, 11 spare) — which this document already argues for
      on other grounds, since 16 MB is the SX-class ceiling and makes the
      CPU variants agree rather than diverge.
- [ ] **Length-match the two devices' data lines to each other.** Shared
      clock, SDR at 84 MHz — not the strict matching of a DDR bus, but
      they are not unrelated nets either.

**Preferred: QSPI PSRAM as the video memory, with a BRAM line buffer.**
8 MB is far more than any DOS mode needs — a period GD5428 shipped with
512 KB — and it leaves the BRAM for the L2 cache, which is what hides
SDRAM latency from the CPU. **Spending 64% of BRAM on a framebuffer would
damage the CPU path to solve a video problem.**

**Scaling does not change this.** The framebuffer is read at *guest*
resolution and upscaled on the fly into the TMDS path, so memory traffic
is set by the guest's mode, not the output mode. **Even if the display
gate forces 720p output, memory traffic stays at 640×480 rates** — which
decouples this decision from G2's outcome.

**The resulting architecture is single-master everywhere:**

- **SDRAM** — CPU only. Latency-optimised. One master, simple controller.
- **QSPI PSRAM** — video only. Sequential scanout, plus CPU writes through
  a combining buffer.
- **BRAM** — L2 for the CPU, line buffer for video.
- **HyperRAM** — **dropped.** No workload fits it: the CPU is
  latency-bound and HyperRAM is high-latency and narrow, while video is
  served by the QSPI pair. A part with no job is not a hedge, and its
  BGA25 would have had to be populated on every prototype to be testable
  at all. Removing it frees 12 pins and leaves the ECP5 as the board's
  only BGA.

- [ ] **Design the write-combining buffer.** This is the real work, not
      the bandwidth. QSPI PSRAM is half-duplex, so an uncombined CPU write
      waits for an in-flight burst — ~6 µs at 84 MHz, roughly 200 wait
      states at 33 MHz. Period software writes directly to video memory,
      so this determines whether it feels like a 486 or like treacle.
- [ ] **Confirm the 84 MHz linear-burst limit** on the specific part. x4
      linear burst crossing page boundaries is limited to 84 MHz; the
      133 MHz figure is for page-bounded or x1 access. **The lower number
      is the one scanout hits.**
- [ ] **Accept the ceiling: 640×480×8 bpp.** 800×600 needs 40 MB/s and
      does not fit. If FPGA video must exceed 640×480, this resolution
      fails and shared memory returns — with all of the above.

- [ ] Decide whether video gets a dedicated channel. **This is a
      pin-assignment decision and must be made before layout freezes**,
      alongside the other items in that class.
- [ ] With that decided, the memory subsystem can be specified against
      the CPU alone — which is where the latency and four-word-ceiling
      reasoning applies cleanly, rather than being contested by scanout
      bandwidth.

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
- [ ] **Decide whether BitBLT and the hardware cursor are in scope.**

      > **Correction to an earlier claim.** It was argued that neither is
      > needed *because SeaBIOS does nothing with them*. **The premise is
      > true and the reasoning is wrong** — firmware was never the
      > consumer that matters.

      **Verified from source:**

      | | finding |
      |---|---|
      | SeaVGABIOS `clext.c` | only **resets** the blitter at init (`GR31 ← 0x04, 0x00`); never draws with it |
      | SeaVGABIOS cursor | uses **`swcursor.c`**, a software cursor XOR'd onto the framebuffer |
      | QEMU `cirrus_vga.c` | **implements both**; the blitter is roughly a third of the file — ROP tables, pattern fill, colour expand, CPU→video and video→video |

      **The real consumer is Windows 3.x with the Cirrus driver** — window
      blits, and the hardware cursor for the mouse pointer. **A 486 with
      32 MB and SVGA is a natural Windows 3.11 machine**, so this is not a
      hypothetical. DOS applications overwhelmingly write the framebuffer
      directly and never touch the blitter.

      **So the question is really: is Windows in scope?** And the two video
      paths answer it differently:

      | path | blitter |
      |---|---|
      | **CL-GD5428 on the mezzanine** | **in real silicon — nothing to implement** |
      | **FPGA video**, if it claims to be a Cirrus | **~a third of QEMU's model, in RTL** |

      > **If BitBLT or the hardware cursor are ever built, build them on
      > the shadow.** *Tinker-later, not now.*
      >
      > A blitter operating on the **cacheable SDRAM master copy** is a
      > far smaller problem than one operating on PSRAM: reads hit L2,
      > writes are page hits, and **the blitter never touches PSRAM at
      > all** — the existing dirty-tile DMA propagates the result exactly
      > as it does for CPU drawing. Same for a hardware cursor, which is
      > composited into the shadow.
      >
      > **So acceleration reduces to "a second writer of the shadow"**,
      > reusing the whole path already designed rather than needing a
      > parallel one. And the register interface stays **era-correct**, so
      > period drivers drive it unmodified.
      >
      > **Nice-to-have. Not required, not gating, and it needs no hardware
      > changes** — it is entirely RTL on the shadow side of the DMA, so
      > nothing about it constrains the board, the pin budget or the
      > prototype. Recorded only so that if the blitter is ever attempted,
      > it is attempted on the right side of the DMA.

      **There is a clean way out.** SeaVGABIOS also ships **`bochsvga`** —
      plain VGA plus VBE with a linear framebuffer, no acceleration.
      That covers **every DOS mode** and sidesteps Cirrus emulation
      entirely. **Cirrus acceleration then lives only on the mezzanine,
      in the real chip, for anyone who wants Windows.**

      **The field was surveyed before choosing.** Every freely available
      model was examined, and `bochsvga` survives on merit rather than by
      default:

      | model | verdict |
      |---|---|
      | **Bochs VBE / `bochsvga`** | **chosen.** 11 registers, 2 I/O ports, VESA LFB, DOS-complete, Win9x drivers exist |
      | **Cirrus `CL-GD54xx`** | period-correct and the original target, but the blitter is ~⅓ of QEMU's model in RTL — **deferred, not rejected** |
      | **QXL** | **rejected** — PCI-only, a SPICE shim rather than a controller, no DOS or Win9x drivers |
      | real `CL-GD5428` on the mezzanine | still available, in **real silicon**, if period authenticity is wanted |

      **The intended arc, recorded so the sequence is deliberate rather
      than reactive:**

      1. **Now — `bochsvga`.** Smallest thing that is DOS-complete and
         drives Windows unaccelerated.
      2. **When features are needed — the dual-framebuffer model.** Shadow
         in cacheable SDRAM, dirty-tile DMA to PSRAM.
      3. **Then — BLIT and cursor on the shadow**, and with them the
         **pivot to the Cirrus model.**

      > **Cirrus is *not* a superset of Bochs VBE — checked.** They are
      > two different extension schemes over a shared VGA core:
      >
      > | | extension mechanism |
      > |---|---|
      > | Bochs VBE | **separate ports** `0x1CE`/`0x1CF`, own 11-register space |
      > | Cirrus | **the existing VGA ports** — `0x3C4/5` sequencer, `0x3CE/F` graphics — with extended indices |
      >
      > QEMU's Cirrus registers only `0x3B0–0x3DF` and references DISPI
      > nowhere. **So the pivot replaces the register layer rather than
      > extending it.**
      >
      > **What carries over is the expensive part**: legacy VGA decode,
      > framebuffer, scanout, palette, banking window, and the entire
      > shadow / DMA / write-buffer infrastructure, which lives below the
      > register layer.
      >
      > **What does not: mode setting — and it is a bigger step than the
      > blitter.** Bochs VBE is *"tell it the resolution"*; **Cirrus is
      > *"program the CRTC yourself"***, which is what the `ccrtc_*` tables
      > in `clext.c` are doing. Mitigation: **pattern-match programmed CRTC
      > values against known modes** rather than implementing a general
      > CRTC — appropriate anyway, since output is a fixed HDMI mode with
      > scaling.

      > **And weigh it against the design philosophy, not only against
      > effort.** *"Program the CRTC yourself"* is the **old
      > way**; Bochs VBE's *"tell it the resolution"* is the new one.
      > Adopting Cirrus to gain a blitter means **taking a step backwards
      > on the axis this project is explicitly organised around** —
      > *period where it has to be, modern where it can be.* That cost is
      > real and belongs in the decision, not just the RTL estimate.
      >
      > **But the CRTC question may already be latent in the DOS
      > requirement.** Period software does not only set modes through
      > `INT 10h`: **Mode X and the tweaked modes reprogram the CRTC
      > directly** — 320×240, unchained VGA, split-screen and panning
      > tricks. Doom and much of the demoscene depend on it.
      >
      > **Resolved — and it was a false choice.** `bochsvga` is not *"the
      > DISPI interface instead of VGA"*. It is **the complete legacy VGA
      > core — CRTC, sequencer, chain-4, planar modes — *plus* DISPI**
      > bolted on for high resolutions. That is exactly why **Doom runs
      > under `-vga std`**: Mode Y's unchaining and CRTC pokes are served
      > by the VGA core underneath, not by the VBE extension.
      >
      > **So the CRTC is owed by the `bochsvga` path itself**, the moment
      > DOS compatibility is in scope. Cirrus never introduced it.
      >
      > **What Cirrus actually adds on this axis is incremental**:
      > *extended* CRTC registers (`CR19`/`CR1A`/`CR1B`, addressing
      > overflow) on top of a CRTC that already exists. **The design-philosophy
      > objection therefore largely evaporates** — the step was taken when
      > DOS compatibility was accepted, and it was taken knowingly.

      > **Which is where the project wanted to be from the start.** The
      > Cirrus path was never abandoned — it was **deferred until the
      > infrastructure that makes it cheap exists.** Building the shadow
      > first turns the blitter from "a third of QEMU's model against
      > PSRAM" into "a second writer of cacheable SDRAM." **Same
      > destination, reached at a fraction of the cost, and nothing along
      > the way is thrown out.**

      - [x] **DECIDED — `bochsvga` is the video model.** VESA VBE with a
            linear framebuffer, DOS-complete, eleven registers behind two
            I/O ports. **Windows 9x works via `vmdisp9x`/VBEMP**,
            unaccelerated. The blitter question does not arise.

            **The Cirrus model stays available for blit and cursor
            support later, if and when it is deemed necessary** — built on
            the SDRAM shadow, per the note above. **Nothing gates on it**,
            and it needs no hardware change, so it can be taken up at any
            point or never.

            *Costs one `#define`* — see below.

      > **`bochsvga` needs one `#define` changed from stock.** Its LFB
      > address is compile-time:
      >
      > ```c
      > u32 lfb_addr = VBE_DISPI_LFB_PHYSICAL_ADDRESS;   // 0xE0000000
      > if (CONFIG_VGA_PCI && bdf >= 0) { ... }          // PCI BAR only
      > SET_VGA(VBE_framebuffer, lfb_addr);
      > ```
      >
      > With no PCI the constant stands. **Drivers take `PhysBasePtr` from
      > the VBE mode-info block, so they follow the VGA BIOS** — only
      > `VBE_DISPI_LFB_PHYSICAL_ADDRESS` in `vgasrc/bochsvga.h` needs
      > changing, not the drivers.
      >
      > **What it costs depends on where it is pointed:**
      >
      > | LFB | address bus | memory hole |
      > |---|---|---|
      > | stock `0xE0000000` | **full 32-bit** | none — sits above RAM |
      > | patched inside 16 MB | **pin-saver survives** | **hole carved from RAM** |
      >
      > **Against the stated goal of unmodified firmware this is a fork**,
      > though about the smallest one available.

      > **QXL — inspected, rejected.** Three independent
      > disqualifications: it is **PCI-only** (five BARs, config space,
      > PCI interrupts) and this machine has no PCI; it is a **SPICE
      > shim rather than a display controller**, calling
      > `spice_qxl_*` to hand commands to a server that does the actual
      > rendering; and it has **no DOS or Win9x drivers** — a DOS guest
      > falls back to plain VGA even under QEMU. Category-mismatched
      > rather than merely unsuitable.
      >
      > **Worth keeping from it: the ring-buffer model.** The guest writes
      > commands into a ring in shared memory and the device consumes them
      > asynchronously, so **the CPU queues work instead of stalling on
      > it.** That is the right shape if acceleration is ever *offloaded*
      > — to the ESP32 or a soft core — rather than implemented in RTL.
      >
      > **The guest-driver requirement is exclusive; the device is not.**
      > QXL embeds `VGACommonState` — **the same VGA core `-vga std`
      > uses** — so QXL is, structurally, *bochs VGA plus a ring offload*.
      > A ring could therefore be **added on top later** exactly as QXL
      > builds it on top of VGA. What stays exclusive is the driver:
      > **no period software will ever submit to a ring**, so it buys
      > nothing for the target workload.
      >
      > **DECIDED — parked in favour of the write path.** The only
      > conceivable consumer is Win 3.11 or 9x, and those already work
      > unaccelerated. **Effort goes instead to LFB support in `bochsvga`
      > and a strong write-combining buffer in the VGA memory core**,
      > because **both target paths are write-bound**:
      >
      > | path | bottleneck |
      > |---|---|
      > | DOS | writes the framebuffer directly |
      > | Windows, unaccelerated driver | CPU blits — memcpy to framebuffer |
      > | ring buffer | **neither — no period driver exists to use it** |
      >
      > **The write buffer is leverage on three questions at once:** DOS
      > speed, Windows tolerability, and — by making unaccelerated Windows
      > acceptable — **it weakens the case for the Cirrus blitter too.**
      > A ring is leverage on none of them.

      > **PHASING — stub now, implement during optimisation.**
      >
      > | phase | video memory path | cost |
      > |---|---|---|
      > | **1 — bring-up** | **CPU reads and writes PSRAM directly** | **slow, and accepted.** Correct, simple, and enough to get pixels on a screen |
      > | **2 — optimisation** | shadow in cacheable SDRAM, dirty-tile DMA | fast; added when schedule allows |
      >
      > **Design the stub in phase 1**: the framebuffer aperture decode
      > should be **switchable between PSRAM-direct and shadow**, and the
      > DMA should have its hook present but unpopulated. **No hardware
      > impact either way** — both paths use the same pins, so this gates
      > nothing on the board.
      >
      > **Two notes so phase 2 costs no rework:**
      >
      > - **"Host reads always come from main memory" is a phase-2
      >   property, not a day-one rule.** In phase 1 host reads do hit
      >   PSRAM, slowly.
      > - **So the write buffer's host-read flush rule is needed in phase
      >   1** and simply **stops being exercised in phase 2.** Implement
      >   it; it becomes dead code rather than something to remove.

      **Idea worth exploring — shadow framebuffer in SDRAM, DMA to
      PSRAM.** For Windows specifically: **let the CPU write the
      framebuffer into main memory**, and have a background DMA move dirty
      regions into the QSPI PSRAM.

      **Both sides get the memory that suits them:**

      | | |
      |---|---|
      | CPU writes | land in **SDRAM — ~30 ns page hits, 133 MB/s, cacheable** — instead of contended half-duplex PSRAM |
      | DMA writes | **perfectly sequential**, so every burst is full and command overhead amortises away, where scattered CPU writes pay it constantly |
      | PSRAM | reduced to what it is best at: **write-in-bulk, read-continuously** |

      **And transforms become cacheable — which is the strongest argument
      of the three.** Unaccelerated blitting *is* read-modify-write: a ROP
      reads the destination, combines, writes back. Every such read on the
      direct path is a **half-duplex PSRAM read contending with scanout**,
      microseconds each, **and it forces a write-buffer flush besides.**
      In a cacheable SDRAM shadow those reads hit **L2 at ~1 cycle.**

      | operation | direct to PSRAM | shadow in SDRAM |
      |---|---|---|
      | write | contended, half-duplex | ~30 ns page hit, 133 MB/s |
      | **read (ROP, sprite mask, palette)** | **µs — and flushes the write buffer** | **L2 hit, ~1 cycle** |
      | scanout | unchanged | unchanged |

      **So the shadow does not merely make writes faster — it makes
      transforms possible at all**, and it **removes the host-read flush
      penalty** recorded against the PSRAM write buffer, because the CPU
      stops reading PSRAM entirely.

      > **This is what `PCD`/`PWT` were retained for.** The shadow region
      > is marked cacheable while the PSRAM aperture stays uncached —
      > page-level cacheability driven outward by the CPU, which is
      > exactly the case those pins were kept to serve.

      **Dirty-region tracking is the enabler, not an optimisation.**

      | | |
      |---|---:|
      | write budget during blanking (4.57 ms @ 62 MB/s) | ~283 KB |
      | spare during active scan (12.1 ms @ ~13 MB/s) | ~157 KB |
      | **per frame** | **~440 KB** |
      | full 1024×768×8 frame | **768 KB** |

      **A whole frame does not fit in a frame's budget**, so blind copying
      fails. A tile-dirty bitmap is cheap — 64×64 tiles gives 192 bits —
      and typical GUI updates sit far inside the budget.

      > **INVARIANT: host reads always come from main memory.** The CPU
      > never reads PSRAM — there is no path for it to. That single rule
      > collapses several problems rather than mitigating them:
      >
      > - **The host-read flush rule is deleted, not reduced.** It was
      >   recorded against the PSRAM write buffer as a real cost; with this
      >   invariant no host read can reach PSRAM, so the rule is vacuous.
      > - **The PSRAM sees exactly two access patterns** — sequential DMA
      >   writes, sequential scanout reads. **No read arbitration, no
      >   snoop, no flush logic.** Two masters with fixed, non-overlapping
      >   roles.
      > - **SDRAM is authoritative; PSRAM is derived state.** Nothing ever
      >   reads back from it, so a corrupted tile **self-heals on the next
      >   dirty update and cannot propagate** into the machine.
      >
      > It also sharpens the earlier principle: the framebuffer is not a
      > coherency domain because **there is nothing left to be coherent
      > with.**

      **Refined — two copies, synchronised at two different rates.**

      | | |
      |---|---|
      | **master copy** | **SDRAM, cacheable.** All drawing and all transforms happen here |
      | **scanout copy** | **PSRAM.** Written only by DMA, read only by scanout |
      | **full sync** | **once per mode switch** — 768 KB, ~12 ms, during a transition where nothing is being watched |
      | **incremental** | **dirty tiles via DMA during blanking**, steady state |

      **That split is what makes the arithmetic work.** The ~440 KB/frame
      budget only ever has to carry *dirty tiles*, never a whole frame —
      the whole-frame copy happens at mode switch where latency is
      invisible. A full-screen repaint spills to two frames, and even that
      beats the CPU writing 768 KB into PSRAM directly.

      **The memory is already paid for:** the second rank is the
      `A13/CS1` pin already decided — **32 MB, of which a 2 MiB shadow is
      noise.**

      > **This does not break the single-master rule, and it is worth
      > saying why.** SDRAM gains a second reader in the DMA, which looks
      > like the thing the private-video-memory decision existed to
      > prevent. It is not: **that argument was about a master with a hard
      > real-time deadline.** Scanout cannot wait; **this DMA always can.**
      > It has no deadline, reads sequentially in page-hit bursts, and
      > yields to the CPU on demand — so it adds no latency *variance* to
      > the path the design is organised around. **A polite second master,
      > not a competing one.**

      - [ ] **Mode-selectable, not global.** DOS software writes `0xA0000`
            and expects pixels now; a shadow path adds a frame of latency
            and would break per-scanline effects. **DOS keeps the direct
            path; Windows uses the shadow.**
      - [ ] **Coherency: the DMA must see the CPU's writes.** If the
            shadow region is cacheable and write-back, the DMA reads
            stale data. Either mark it **write-through**, or have the DMA
            snoop. Write-through to SDRAM is still far faster than
            anything the PSRAM path offers.
      - [ ] Costs: a DMA engine, the dirty bitmap, **double storage** (768
            KB in each memory — both have room), and one frame of latency.

      **This is the shadow-framebuffer/deferred-I/O pattern** that QEMU and
      Linux `fbdev` both use, which is a point in its favour: well-trodden,
      and it fits the machine's existing split of fast-writes memory versus
      stream-out memory.

      > **Note — DOS uses the linear framebuffer too.** It is not a
      > Linux-era feature. **VBE 2.0 introduced the LFB for DOS
      > extenders**, and protected-mode DOS software used it heavily.
      > The split is by vintage, not by operating system:
      >
      > | path | used by |
      > |---|---|
      > | 64 KB banked window at `0xA0000`, via `BANK` | **VBE 1.2, real-mode DOS** |
      > | linear framebuffer at a high address | **VBE 2.0, protected-mode DOS** (DOS4GW-era titles) |
      >
      > **Both are DOS paths, so the FPGA owes both.** Banking is not
      > legacy dead weight that can be skipped.

      **Windows 9x drivers for the Bochs adapter exist and are
      maintained** — [vmdisp9x](https://github.com/JHRobotics/vmdisp9x)
      (explicitly supports Bochs VBE and QEMU `std-vga`),
      [VBEMP 9x](https://bearwindows.zcm.com.au/vbe9x.htm),
      [boxv9x](https://github.com/phkelley/boxv9x), and `qemumini.drv`.
      **So choosing `bochsvga` does not cost Windows support.**

      **What it costs is acceleration.** Every one of those drivers is an
      unaccelerated framebuffer driver: each blit is a CPU memory copy.

      | | Windows | drawing |
      |---|---|---|
      | **Bochs VBE + VBEMP/vmdisp9x** | works, high res | **CPU-bound** — drags, scrolls, menus all memcpy |
      | **Cirrus, real GD5428 on mezzanine** | works | **blitter does it**, no CPU |
      | Cirrus emulated in FPGA | works | blitter in RTL |

      **Sharper here than on a PC**: a 640×480×8 full-screen blit is
      ~300 KB against a ~62 MB/s video path **shared with scanout**, so
      multiple milliseconds per operation with the CPU stalled throughout.

      **But keep perspective — Windows on a 486 was sluggish on real
      hardware.** Win 3.11 was the realistic target for this class of
      machine, and unaccelerated may be period-honest rather than a
      failure. **That judgement, not the RTL cost, is what should decide
      this.**

## Direction: sound synthesis is software

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

## Direction: firmware configuration over fw_cfg, not CMOS

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

## Direction: CMOS as a compatibility surface, populated at reset-exit

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

## Direction: block storage backed by the ESP32

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

## Direction: networking via NE2000, serviced by the ESP32

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



## Decided: all ECP5 VCCIO rails are 3.3 V

**Every VCCIO bank runs at 3.3 V.** One I/O voltage across the whole
device.

This removes a class of constraint rather than merely settling one.
Banks that share a VCCIO rail must share a voltage, so a mixed-voltage
design forces signal groups into particular banks and can strand I/O
that is electrically fine but at the wrong potential. With a single rail
there is nothing to resolve: **signal groups are assigned to banks by
geometry alone.**

It follows naturally from the rest of the design — the CPU is a 3.3 V
part chosen so its bus reaches the FPGA without level shifters, and
fake-TMDS video drives ordinary 3.3 V I/O. **The mezzanine is 3.3 V and
not 5 V tolerant**, a hard specification, so no legacy voltage reaches
the baseboard at all: a daughterboard needing 5 V translates on the
daughterboard.

Consequence for layout: the pin budget and bank allocation have no
voltage dimension, and the level-shifter footprints recorded as
insurance in [BOARD.md](BOARD.md) protect the CPU-bus margin only, not a
bank-voltage decision.

## Reserved: ECP5 bank 8 is configuration and DFx only

**Bank 8 of the LFE5U-85F CABGA381 is reserved. Nothing but
configuration and DFx may be assigned to it without an explicit waiver
recorded here.**

All 13 of its balls carry configuration functions:

```
D0-D7 / IO0-IO7      SPI flash data
MOSI, MISO, MOSI2, MISO2
CSSPIN, CSON, CS1N, SN/CSN
HOLDN/DI/BUSY/CEN, DOUT, WRITEN
```

This is the interface the FPGA boots through. Anything else placed there
either collides with configuration or silently constrains it — and the
failure would appear at bring-up, on a board that cannot be reprogrammed
to fix it.

**Permitted without a waiver:**

- SPI NOR configuration flash
- QSPI PSRAM sharing that bus (one chip select), since it is on the flash
  bus by design
- DFx — JTAG, test points, bring-up and debug access

**Requires a waiver:** anything else. The waiver goes in this file, names
the signal, and states why no other bank will serve.

This was nearly got wrong once already: a placement draft assigned HDMI
to bank 8 on the grounds that it had differential pair sites and was too
small to be useful for a bus. See [PLACEMENT.md](PLACEMENT.md).

## Nomenclature: cache levels

**Canonical for this project. Any document using these terms differently
is wrong and should be corrected, not reinterpreted.**

| level | is | notes |
|---|---|---|
| **L1** | the CPU's **on-die** cache | **May or may not exist.** A plain 386SX has none; an SLC-class part has a small one; the Am5x86 has 16 KiB write-back. Where coherency problems live, because it is the one cache the chipset cannot see into. |
| **L2** | the **chipset** cache | Inside the FPGA. May be direct-mapped or N-way set-associative. |
| **L3** | **external** cache | Most likely direct-mapped, or some other form of streaming buffer. |
| **LLC** | whichever level is **last before far memory** | A **role, not a number** — it may be L2, L3, or a distinct on-die structure. Use LLC in architecture text; name the mechanism (e.g. "stream buffer") only when describing a specific implementation. Concept C's LLC is an on-die stream buffer, and it has **no L3 at all**. |

Two things follow that are easy to get wrong:

- **"The cache" is ambiguous** in any sentence where both the CPU's and
  the chipset's could be meant. The write-back coherency problem is an
  **L1** problem; the associativity and BRAM-budget discussions are
  **L2** problems.
- **L1 being optional is a real design variable**, not a footnote. The
  SX-class and Am5x86 paths differ in whether L1 exists at all, which
  changes what L2 is compensating for.

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

### What a cache costs to build here, measured

The one hard resource figure available so far, and it comes from a
measurement already paid for in
[ao486-cpu-oss](https://github.com/pawlex/ao486-cpu-oss). On an
LFE5U-85F there are **two separate memory pools**, and a cache wants
both:

| pool | size on the 85F | suits |
|---|---|---|
| EBR (`DP16KD`, 18 Kbit each) | 208 blocks | data arrays — density |
| distributed RAM (RAM LUTs) | 10,455 | tag stores, small FIFOs, line buffers — async read |

The distinction matters because **tags want an async or single-cycle
read** to resolve a hit without adding a pipeline stage, which is what
distributed RAM is for; data arrays want density, which is what EBR is
for. Sizing them against the wrong pool is an easy mistake.

The measurement: **ao486 consumes 260 RAM LUTs — 2%** — leaving roughly
**10,195 for everything else**, cache ways included. Its 12 EBR of 208
is similarly light. So on the hard-CPU path, where no x86 soft core is
instantiated at all, essentially the entire budget of both pools is
available to the chipset and its cache.

Worth stating because the instinct is to assume an FPGA design is
LUT-limited. Here the general LUT4 pool is what a soft x86 core makes
expensive; **the pools a cache actually competes for are close to
untouched.**

### ao486's role here: traffic generator, not bus model

Recorded to head off a wrong assumption. **ao486 does not have a 486
bus interface.** Its top-level memory port is Avalon-MM —
`avm_address`, `avm_burstcount`, `avm_waitrequest`, `avm_readdatavalid`
— with cache control reduced to a single `cache_disable` input. There is
no `ADS#`, `BRDY#`, `BLAST#`, `KEN#`, `FLUSH#`, `AHOLD` or `EADS#`.

So it **cannot** validate the chipset's 486 front end, and the
cycle-accurate 486 BFM recorded against the BIU work stands as written.
It is a 486-compatible CPU, not a 486 bus master.

What it *is* good for is the layer this section cares about. A real
486 core running real software produces **realistic memory traffic** —
access sizes, burst counts, locality, reuse — and that is exactly the
evidence needed to choose a cache line size, associativity and write
policy, and to estimate a hit rate. Transaction level is the wrong layer
for bus protocol and the right one for cache design.

That makes it potentially useful **earlier** than "when real hardware
needs it": a trace from ao486 running DOS would let the cache be designed
against measurement rather than intuition, which is the same empirical
approach already sketched for sizing on-chip memory.

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

### External evidence: M8SBC-486

A working homebrew 486 with an FPGA chipset —
[M8SBC-486](https://github.com/maniekx86/M8SBC-486), Spartan II, VHDL
sources published, runs MS-DOS, FreeDOS and Linux. The same topology as
this project, and the first outside evidence bearing on the burst and
cache question.

Read from its constraints file and chipset sources:

| present | absent |
|---|---|
| `ADS#`, `RDY#`, **`KEN#`**, `BS8#`, `BS16#` | **`BRDY#`, `BLAST#`** |
| `W/R#`, `M/IO#`, `D/C#`, `BE0-3` | `FLUSH#`, `AHOLD`, `EADS#`, `INV` |

Cacheability comes from address decode —
`OUT_KEN <= '0' WHEN ((ROM_CACHE = '0') OR (RAM_CACHE = '0')) ELSE '1';`
— with a known bug acknowledged in their own source
(`-- To fix: doesn't work on ROM`). There is no burst anywhere; the only
`BRDY` in the tree is a datasheet quote in a comment. It also drives
`BS8#`/`BS16#` for dynamic bus sizing, and uses **4 MB of parallel
SRAM** at a 24 MHz FSB.

**So "selective cacheability by address region, no burst, no snooping"
is a proven working point**, not a theoretical compromise — it runs real
operating systems on real 486 silicon. That materially de-risks
deferring burst support. It also arrived independently at parallel SRAM,
which the four-word ceiling above argues for on separate grounds.

**The instructive part is its pin budget.** That FPGA uses **91 pins
total and taps only 8 bits of CPU data.** The data path never crosses
it: SRAM and ISA sit directly on the CPU data bus behind transceivers,
and the FPGA is a *control plane* — address decode, strobes, clocks —
tapping 8 bits for its own internal peripherals. Simpler and far
cheaper in I/O. It was considered here and rejected, for the reason
below.

### Direction: the cache data array lives in FPGA block RAM

**The cache is N-way set associative, and its data array is on-chip.**
That decision is what rules out the control-plane-only architecture
above, so the two belong together.

**Associativity is the reason, and it is a hard one.** A direct-mapped
cache can keep its data external — one lookup, one bank, one access.
**N-way requires all N ways to be read simultaneously** so the tag
comparison can select among them in the same cycle. Externally that
means N independent banks: N sets of address pins, N data buses, N
chips, scaling with associativity. On-chip block RAM provides those
parallel reads for nothing.

So keeping the data external does not merely limit capacity — **it caps
the design at direct-mapped**, the associativity with the worst
conflict-miss behaviour. That is the opportunity being protected here,
and it is the part of the machine most worth designing.

**The budget supports it.** On the hard-CPU path no x86 soft core is
instantiated, so essentially the whole pool is available:

| | EBR used |
|---|---|
| total on an LFE5U-85F | 208 blocks = 468 KiB |
| 128 KiB data array | ~57 (27%) |
| 256 KiB data array | ~114 (55%) |

Period 486 boards shipped 128-512 KiB of L2, so this range is both
era-appropriate and comfortable.

Two things fall out neatly:

- **A 16-byte line is exactly one 486 burst.** Four transfers, sixteen
  bytes: one fill is one burst, with no partial-line handling and no
  multi-burst fills. The line size the CPU wants and the line size the
  memory delivers efficiently are the same number.
- **Tags are nearly free.** A 256 KiB 4-way with 16-byte lines is 4096
  sets, and against a machine with far less than 4 GiB populated the
  tags land around 8-16 bits — roughly 16-32 KiB total. A candidate for
  distributed RAM precisely because of the async-read argument above,
  keeping the hit decision out of the block RAM read latency.

ECP5 block RAM is genuinely dual-port, so a fill write and a CPU-side
read can proceed concurrently rather than contending — which matters
more on a non-blocking design than the capacity does.

**The accepted cost:** this forces the full CPU data bus into the FPGA,
and with it the pin count M8SBC-486 avoided. That is the trade, taken
deliberately.

### The CPU is not the only client, and may not be the dominant one

Everything above reasons about CPU access patterns. **The video decision
puts the framebuffer in external DRAM, described as shared** — and if
that is the same memory, the analysis above is being drawn from the
*minority* client.

| client | wants | rough traffic |
|---|---|---|
| CPU | low latency, small random accesses | ~10-20 MB/s at 33 MHz |
| video scanout | sustained bandwidth, purely sequential | 1024x768x24 @ 60 Hz ≈ **135 MB/s** |

Scanout is an order of magnitude larger, entirely sequential, and
latency-insensitive — it is the one client that genuinely *wants*
burst-oriented memory. If the two share a channel, the part gets chosen
for video bandwidth and the CPU's latency problem becomes something
solved on top of that choice rather than by it. Which is precisely what
Concept C does.

The figure scales hard with mode: 640x480x8 is ~18 MB/s, 1024x768x24 is
~135 MB/s. So the decision depends on which modes are actually
supported, not on video in the abstract.

- [ ] **Decide whether the framebuffer shares guest memory or has its
      own.** Separate lets CPU memory be chosen purely for latency and
      video purely for bandwidth, decoupling two requirements that pull
      in opposite directions — at the cost of a second part.
      [BIU_MEMSS.md](BIU_MEMSS.md) notes a cheaper variant of the same
      idea: a second *channel* rather than a second part, which serial
      memory makes nearly free in pins.
- [ ] Until that is settled, treat the latency-versus-bandwidth
      conclusion above as provisional.

### And this is the real justification for deferring the memory subsystem

The deferral is recorded elsewhere as discipline — not starting with the
most interesting part, so the surrounding work gets finished. **That is
true but it is the weaker reason. The stronger one is that the ordering
is simply correct.**

The dependency runs one way:

```
  CPU latency budget   (fixed -- the CPU is chosen)
        |
        v
  cache: line size, associativity, write policy
        |
        v
  memory subsystem     (the free variable)
```

The memory subsystem is **downstream of the cache, which is downstream
of a latency budget set by the CPU.** Specifying it first means
optimising a component before its requirements exist — and the instinct
one optimises on, bandwidth, is precisely the one that hurts here.

The failure mode is concrete and worth naming: **a high-bandwidth memory
subsystem that cripples the bus interface with latency.** Deep
pipelining, transaction reordering, long bursts and elaborate scheduling
all improve throughput and all delay the first word. If the BIU cannot
hide that — because the cache is small, or the line size is mismatched,
or a region is deliberately uncached — the result is better memory
numbers and a slower machine. It would be entirely possible to build
something impressive in isolation that makes this machine worse.

So the memory subsystem is not being avoided. **It is waiting for its
requirements**, which do not exist until the CPU-side budget is
established and the cache is designed.

### The four-word ceiling inverts the usual choice

**A 486 burst is four transfers. Sixteen bytes. That is the entire
amortisation window**, and there is nothing longer anywhere in the
machine — the SX has no burst at all.

A memory part with a long fixed setup cost cannot amortise it across
four words; the setup simply dominates every access. Which means the
usual instinct — pick the part with the best sustained bandwidth — is
backwards here. **Low latency beats high bandwidth, and it is not close.**

**Contested.** [BIU_MEMSS.md](BIU_MEMSS.md) (Concept C) argues the
opposite: accept a high-latency serial part and ensure the CPU never
sees the latency, hiding steady state behind L2 and transitions behind
the LLC stream buffer. That buys fewer pins, lower cost per megabyte and
a smaller package. The two positions cannot both be right, and the
difference between them is an L2 hit-rate figure — measurable, and not
yet measured. Do not treat the paragraph below as settled.

That likely favours **parallel SRAM or parallel PSRAM**: more pins, no
row activation to hide, access latency close to the CPU's own budget.
And it likely disfavours HyperRAM, whose pin efficiency is attractive
against an FPGA I/O budget but whose high initial latency wants long
bursts that this machine will never issue.

Capacity is not the constraint it would normally be. A 386SX cannot
address beyond 16 MiB at all, and a DOS machine wants single-digit
megabytes — so the usual reason to accept latency in exchange for
density does not apply either.

### Supporting the SX roughly doubles the work here

The cost of SX support was first recorded as a second *bus* front end.
**The memory subsystem is the larger half**, and it was not visible at
the time:

| | access pattern |
|---|---|
| 386SX | single 16-bit transfers, **no burst at all** |
| Am5x86 | four-transfer 32-bit line fills, single cycles otherwise |

A controller tuned for one is not tuned for the other — different width,
different burst behaviour, and quite possibly a different cache design,
since the question of whether the SX path gets a cache at all is
separate.

**Superseded — see "One BIU per CPU variant" above.** The cost is now
stated precisely: the BIU doubles, the memory subsystem does not.
Concept C's argument below is the reasoning that got there.

**Concept C claims to largely dissolve this**, and the claim deserves
weighing rather than dismissing. If the cache sits inside the FPGA as
the boundary between CPU and far memory — with no external wiring on
that interface — then the far memory's width stops mattering at the bus
level, and the two CPU variants differ only in the cache's CPU-side port
and tag width. That is a parameterised design rather than two designs,
and it would make the cost nearer 1.2x than 2x. See
[BIU_MEMSS.md](BIU_MEMSS.md), "CPU-variant independence".

**The open question, and it is genuinely open:**

- **One subsystem serving both.** One design, one validation, and
  optimal for neither — compromised on width, line size and fill policy.
- **Two paths.** Each right for its CPU, twice the design and twice the
  validation. The difference between them is itself worth understanding,
  and this is the part of the project the author actually wants to build.
- **A third framing worth testing before choosing:** this is programmable
  logic, so "two paths" may be two *configurations* of one parameterised
  design rather than two designs — the same argument already made for
  the bus front end. Whether that holds depends on how much of the
  difference is parameter (width, burst length, line size) and how much
  is structure. Worth establishing early, because it decides whether the
  cost is 2x or closer to 1.2x.

- [ ] **Decide whether the SX is supported**, knowing the memory
      subsystem cost and not only the bus front-end cost.
- [ ] Establish the latency budget from the CPU side first. It is the
      fixed constraint; bandwidth is the free variable.
- [ ] Design the cache against that budget — line size, associativity,
      write policy.
- [ ] *Then* define what "modern memory" means concretely, and match its
      efficient burst length to the line size already chosen.
