# Board — constraints, decisions, opens

Tracking file for the physical design. Rationale lives in
[PLAN_OF_RECORD.md](PLAN_OF_RECORD.md); this records what it means for
the PCB.

## The principle this file exists for

**The board is where soft decisions become hard.**

Nearly everything else in this project is a bitstream change — the bus
front end, the cache, the peripheral set, the memory controller, even
which CPU variant is supported. The PCB is the one layer where a
decision cannot be revised later, and where an omission cannot be
recovered by rebuilding.

So the governing rule: **when uncertain, commit the pins and defer the
logic.** Routing a signal that is never used costs a track. Not routing
one that turns out to be needed costs a respin.

## Prototype strategy: design in the options

**Prototypes are expensive and the intent is to build them once.** So
options get designed in even where they may go unused or unexercised.

The economics are not close. A three-dollar part that goes unpopulated
is trivially cheaper than discovering a three-dollar part is needed and
respinning every prototype to add it — where the real cost is not the
board but the assembly, the stencil, the lead time, and the weeks.

There is a cost hierarchy worth being explicit about, because the
cheapest options are nearly free and are the ones most often skipped:

| | cost | examples |
|---|---|---|
| **Route it** | a track | unused CPU control signals, spare FPGA I/O |
| **Footprint, unpopulated (DNP)** | board area only | second memory channel, GD5428, alternate power entry |
| **Populate it anyway** | a few dollars, plus area | a part whose need is likely but unproven |
| **Respin** | everything | — |

### HARD CONSTRAINT: BGAs are factory-fit, so a BGA footprint is not an option

**Any BGA on any plan — A, B or C — must be assembled at the PCB house.**
Hand-placement is possible but not reliable enough to depend on.

This breaks the option strategy for exactly the parts it was meant to
cover. **A DNP footprint only works as a hedge if it can be populated
later.** For a BGA it cannot, so a BGA footprint is not an option — it
is a **commitment deferred to order time**, which is a different and much
more expensive thing.

The line runs through the memory candidates, and it has nothing to do
with performance:

| part | package | who can fit it |
|---|---|---|
| ECP5 | CABGA381 | factory — mandatory regardless |
| HyperRAM `IS66WVH8M8ALL` | **BGA25** | **factory only** |
| Parallel PSRAM `IS66WVE4M16` | **TFBGA48** | **factory only** |
| SDR SDRAM | commonly TSOP-54 | **bench** |
| QSPI PSRAM (e.g. APS6404) | SOP-8 | **bench** |
| CPU, CL-GD5428 | PGA / PQFP | bench |
| ESP32 module, SPI NOR | castellated / SOIC | bench |

(Packages for the two BGA memories are taken from the footprints already
in `PCB/Lib/`.)

Consequences:

- **Prefer bench-solderable parts wherever a hedge is actually wanted.**
  A hedge you cannot populate is not a hedge.
- **HyperRAM must be populated on the prototype run to be testable at
  all.** Either pay its BOM on every board, or split the run into
  variants and pay assembly setup twice. If neither is worth it, drop it
  now rather than carry a footprint that can never be exercised.
- This strengthens **SDR SDRAM** considerably: known-good controller
  already written, lower latency than HyperRAM, and **the only wide
  option that can be changed after the boards arrive.**
- Any part whose need is uncertain *and* which only exists in BGA has to
  be resolved **before the order**, not during bring-up.

- [ ] Decide, per BGA candidate, whether it is populated on the run,
      split across variants, or dropped. **This decision has an
      order-time deadline**, unlike everything else in this file.

### When to design it in, and when to spin another board

The question that decides how much hedging is rational. Three
observations resolve most of it.

**1. The scarce resource is layout time, not money.** Boards and
assembly at prototype quantity are cheap next to months of placement and
routing. So an option that costs pins and area but little layout effort
is nearly free, and an option that complicates the placement is
expensive even if the part costs nothing.

**2. A respin is not a re-layout.** This is the one most often got
wrong. Adding a part in revision two does not cost another three months
— it reuses the existing placement and routing almost entirely, and the
change is local. The real cost of a respin is **fab, assembly, and
several weeks of calendar**, plus days of layout. Not months.

**3. Therefore: plan for at least two spins.** Revision one exists to
*answer questions*. Revision two is the product. Treating revision one
as if it must be the final board is what makes the hedging question feel
impossible, because it forces every future decision into the present.

Once revision two is assumed rather than feared, the criterion becomes
much narrower:

> **Include it in revision one if its absence prevents the board from
> teaching you something. Not if its absence merely limits what the
> board can do.**

A missing feature is a limitation, and limitations are what revision two
is for. A missing *instrument* is a blind spot, and blind spots are what
force an unplanned respin.

#### Always include, because the marginal cost is near zero

- Anything sharing a pin group whose pins are already committed.
- Routed-but-unused signals, test points, spare I/O.
- **BGA parts that might be needed** — not because they are likely, but
  because they cannot be added at the bench later, so their option value
  expires at order time.

#### Accept the respin instead when

- The change would be **local** — one part, one region — so revision two
  absorbs it cheaply.
- The option costs **pins or area that something known-needed wants**.
  Speculative parts do not outrank confirmed ones.
- What you learn would **change the architecture**, not add to it. No
  amount of hedging survives a structural change, so hedging against one
  is wasted.
- The board has already answered its questions. At that point revision
  two is a product board, not a fix.

#### Applied to the current candidates

| candidate | verdict | why |
|---|---|---|
| Parallel SRAM + SDRAM sharing the wide group | **include** | tests the latency hypothesis; pins already committed |
| QSPI PSRAM, gangable | **include** | tests Concept C's premise; ~18 pins |
| HyperRAM | **probably drop** | BGA, so it occupies a shared group's only slot; and SDRAM plus QSPI already span the latency-versus-pins argument, so it teaches little the others do not |
| Level shifter footprints | **include** | a wrong 3.3 V margin is otherwise unrecoverable |
| CL-GD5428 | **mezzanine connector** | see below — removes it from the gate entirely |
| Both CPU footprints | **respin instead** | costs scarce area, and a second variant is a local change |

#### The CL-GD5428 goes on a mezzanine

Rather than gating a GD5428 footprint on G2, the main board carries a
**mezzanine connector on the CPU local bus** and the video chip lives on
a daughterboard.

**Why this is better than a footprint:**

- **It costs no additional FPGA pins.** The GD5428 connects to the
  **486 bus the FPGA already exposes** — the BIU's outward-facing side —
  not to new I/O. Those pins exist by necessity. Against a budget with
  roughly 33 spare after everything known-needed, a 60-80 pin mezzanine
  fed from fresh FPGA I/O would not fit at all; fed from the bus that is
  already there, it costs nothing from the budget.
- **The GD5428 decodes its own addresses.** It is a real VGA device and
  knows `0x3c0-0x3df` and the `0xa0000-0xbffff` aperture, so it needs
  no chip select — only the bus. The corresponding requirement is on the
  FPGA side: **it must not claim those ranges when a mezzanine is
  present**, which is a bitstream matter rather than a board one.
- **The connector is a replication of the exposed 486 bus, plus a few
  lines to drive bus transceivers.** So the pin cost is the transceiver
  control — direction and output-enable — not the bus itself.
- **It removes the GD5428 from the prototype's critical path.** The
  daughterboard is designed, built and revised on its own schedule,
  independently of a main board that takes months to lay out.
- **It reclaims main-board area**, which is the other scarce resource on
  a 170 mm square.
- **The mezzanine carries its own video connector and its own DRAM**, so
  neither competes for rear I/O or main-board memory.
- Different video approaches become different daughterboards rather than
  different main boards.
- It is genuinely field-upgradeable — a customer option rather than a
  build-time one.

**Costs and cautions:**

- **Buffered, not stubbed.** Because the mezzanine sits behind bus
  transceivers rather than tapping the bus directly, it does not load
  the CPU-side nets — and with output-enable deasserted an unpopulated
  mezzanine is electrically absent. That removes the signal-integrity
  concern a direct tap would have created. Cost is roughly seven
  transceiver packages (data, address, control) plus their board area.
- A ~33 MHz bus through a board-to-board connector is well within reach:
  ISA ran at 8 MHz through card edges and VL-Bus at 33-50 MHz.
- **Height and case clearance** on mini-ITX. A low-profile board-to-board
  arrangement is needed, not a socket-and-riser.
- The connector itself is BOM and area whether or not a mezzanine is
  ever fitted.

**The transceivers can also translate voltage — which is the larger
consequence.**

The 3.3 V requirement exists so the CPU connects to the FPGA without
level shifters. It does **not** have to constrain the mezzanine: with
translating transceivers at the connector, **5 V period parts can live
on the mezzanine** while the core of the machine stays 3.3 V throughout.

That matters immediately — period Cirrus parts are 5 V devices, and the
CL-GD5428's supply should be confirmed rather than assumed — and it
matters more generally, because it makes the mezzanine a home for the
entire 5 V period parts bin rather than only for parts that happen to
exist in 3.3 V.

**So: a modern-voltage core with a level-translated legacy expansion
bus.** Any period peripheral expecting a 486 or ISA-style bus can live
there — video, sound, whatever comes later. That quietly restores
expandability to a board with no expansion slots, at the cost of one
connector and a handful of transceivers. It is also the same bus the
soft core drives when no hard CPU is fitted, so mezzanine peripherals
work on both paths without special handling.

- [ ] Decide whether the mezzanine is specified as a **general
      peripheral bus** rather than a video-specific connector. Costs
      nothing extra now and forecloses less later.

**What it does not solve:** whether *FPGA* video needs a dedicated memory
channel still depends on G2. The mezzanine removes the GD5428 from the
gate; it does not remove the gate.

### What earns an option, and what does not

Left unchecked this philosophy sprawls, because everything looks like it
might be needed. The test:

**Does its absence force a respin, or merely a limitation?** A missing
part that caps performance is a limitation and can wait for revision
two. A missing part that makes the board unusable, or makes a
question unanswerable, is a respin — and that is what earns a footprint.

Two supporting questions: is the uncertainty *real and currently
unresolved*, and does the option cost area that is genuinely scarce on a
170 mm square?

### Candidates

- **Level shifters on the CPU bus.** The no-level-shifter property
  depends on a voltage margin that is **tight, not comfortable** — the
  Am5x86 is nominally ~3.45 V against an LVCMOS33 ceiling near 3.465 V.
  If that margin fails on real hardware there is no recovery without a
  respin. Footprints for translation on the bus, normally bypassed by
  zero-ohm links, is the textbook case for this rule.
- **Series termination footprints** on the CPU bus and clocks, fitted
  with zero-ohm links initially — signal integrity at 33 MHz cannot be
  validated until the front end exists.
- **Second memory channel**, footprint and pins, populated later.
- **Both CPU footprints**, if the area allows.
- **CL-GD5428**, footprint pending the HDMI gate.
- **Alternate power entry** — DC barrel and an ATX header footprint,
  populate one.
- **Strapping options** as resistor footprints rather than fixed logic.
- **Test points on everything that matters**, and spare FPGA I/O
  reserved for bringing internal signals out. A prototype that cannot be
  probed is a prototype that has to be respun to answer a question.

## Status

Nothing is fabricated. Schematics and library work are in `PCB/`;
reference material in `Data/`. Nothing here is frozen.

---

## Prototype definition

**Built once, deliberately.** Layout is expected to take months of
iteration, so the prototype is scoped by what it must *answer*, not by
what the finished product contains.

### The two jobs of revision one

**Answer the questions below — and survive the answers being
unfavourable.**

The second job is easy to forget and expensive to skip. The cost of a
wrong answer is not the part that turns out to be needed; it is
**hundreds of dollars and weeks of overseas transit** before the next
attempt. So the board carries fallbacks that would never ship, on the
grounds that a compromised option already fitted beats an elegant one
that costs a month to obtain.

### The questions it exists to answer

These cannot be settled in simulation, and each one that goes unanswered
is a reason for a second spin:

1. **Does the CPU bus work at 33 MHz against an FPGA chipset** —
   signal integrity, and the 3.3 V margin.
2. **Which far memory works** — and whether the cache can be made
   effective against it.
3. **Does fake-TMDS video work** at a useful resolution.
4. **Does the machine boot** end to end.

Everything below follows from those four.

### MUST — absence forces a respin

- **CPU, soldered, with every signal routed to the FPGA.** Including the
  ones the first bitstream ignores.
- **ECP5-85F**, configuration flash, power, JTAG, and enough test points
  to diagnose a board that does not work.
- **Every candidate far-memory technology must be testable.** This is
  the important one. The serial approach is unproven and the whole of
  Concept C rests on hiding its latency. **If the prototype can only
  test one class of memory and that class disappoints, the board is
  respun to answer a question it should have been able to answer.**

  The candidates: **serial PSRAM**, **parallel PSRAM**, **SDRAM**, and
  **HyperRAM**. Populate one, route and footprint the rest.

  **They do not each need their own pins.** Only one is ever populated,
  so footprints can share a pin group:

  | group | width | serves |
  |---|---|---|
  | **narrow** | ~12 pins | serial PSRAM, HyperRAM |
  | **wide** | ~40-45 pins | parallel PSRAM, SDRAM |

  Two groups, roughly 55 pins, covers all four technologies — against
  ~90 if each were given its own. The control signals differ between
  parallel PSRAM and SDRAM (`RAS`/`CAS`/`CKE`/`DQM` versus
  `CE`/`OE`/`ADV`), so the wide group is specified as the **superset**
  and unused signals are simply not driven.

  One caveat worth taking seriously: **"DDR of any kind" spans two very
  different layout problems.** SDR SDRAM and HyperRAM are tractable at
  this level. DDR2/DDR3 bring matched-length routing, termination and
  fly-by topology — a different class of difficulty that may not belong
  on a first prototype, and would likely dominate the layout schedule if
  admitted.
- **HDMI pins and connector.** Pins are free; not routing them means a
  respin to test video.
- **ESP32**, since it is the controller for configuration, storage and
  time — nothing boots without it.
- **A console path that works before video does** — serial or debug
  port. A board that cannot report why it failed to boot is a board that
  gets respun blind.
- **Level-shifter footprints on the CPU bus**, bypassed by zero-ohm
  links. The 3.3 V margin is tight enough that being wrong here is
  otherwise fatal.
- **Series termination footprints** on the bus and clocks.

### SHOULD — cheap, and likely needed

- **SD card.**
- **Second memory channel** — pins committed, footprint present,
  unpopulated.
- **CL-GD5428 footprint**, unless the HDMI gate has already passed by
  freeze time.
- **Strapping and configuration options as resistors** rather than fixed
  logic.
- **Spare FPGA I/O brought to headers**, for observing internal signals
  on hardware.

### COULD — only if area and time allow

- Both CPU footprints on one board.
- Audio output.
- USB host for HID.
- Alternate power entry.

### Decided: two memories, both populated — and they are an experiment

**Two memories are needed regardless**, so the question was never whether
but which two. The answer: **SDR SDRAM on the wide group and HyperRAM on
the narrow group, both populated, on separate pins.**

They are not primary and backup in the ordinary sense. **They are the two
sides of the contested question in
[PLAN_OF_RECORD.md](PLAN_OF_RECORD.md):**

| | tests |
|---|---|
| **SDR SDRAM** — wide, low latency, controller already written | *"the LLC may be unnecessary"* — a machine whose memory is quick enough that hiding is not required |
| **HyperRAM** — narrow, high latency, few pins | *"the LLC works"* — Concept C's premise, that latency can be hidden behind L2 and a stream buffer |

Because they sit on **separate pin groups, both can be populated at
once**. Comparing them is a bitstream switch, not a rework — same board,
same CPU, same workload, same day. That is what turns the
latency-versus-bandwidth disagreement from an argument into a
measurement.

Supporting points:

- **Video is indifferent.** Both exceed the ~150 MB/s ceiling
  comfortably (SDRAM ~286, HyperRAM ~400), so neither constrains the
  display decision.
- **HyperRAM's BGA is now a deliberate commitment rather than a hedge**,
  which is the right way to spend an order-time decision. It is being
  populated because it is one of the two hypotheses, not held in reserve
  in case something else fails.
#### And a third: QSPI PSRAM on the flash bus

**Serial QSPI PSRAM is included as well, sharing the EEPROM/FLASH QSPI
bus.** The bus already exists for the configuration and storage flash,
so the PSRAM costs **one additional chip select** and nothing else.

That gives **three memory technologies testable on one board** — wide
SDRAM, narrow HyperRAM, and serial QSPI PSRAM — for a pin budget that
only ever paid for two.

**This is survivability, and that is the whole point.** Flash and PSRAM
on one bus serialise against each other, so it is explicitly not a
production arrangement — and that does not matter. **The cost of being
wrong is not the part. It is hundreds of dollars and weeks of overseas
transit**, on a project worked in evenings where a lost month is a real
loss.

A compromised fallback that is already on the board beats an elegant one
that requires a respin to obtain. **Do not remove this for being
inelegant** — it is here precisely because it is cheap insurance against
the expensive failure mode.

Two things to watch, neither of which undermines the above:

- **Contention depends on what the flash is doing.** If the flash is
  read mainly at boot, sharing costs almost nothing in steady state. But
  the plan of record proposes NOR as a **read-only system store** — a
  bootable DOS image — and that is accessed continuously, which would
  contend directly with PSRAM used as main memory. The two ideas are
  compatible only if one of them is idle.
- **It interacts with G7.** If the ESP32 becomes FPGA configuration
  master and owns the flash bus, then three masters want that bus and
  arbitration stops being trivial. If the FPGA owns it after
  configuration, separate chip selects are enough.

- **Async parallel SRAM stays available** on the wide group as the
- **Async parallel SRAM stays available** on the wide group as the
  lowest-latency instrument, if the latency hypothesis needs testing at
  its extreme.

**This also gives the prototype a clear purpose beyond "does it work".**
It is an instrument built to answer a specific architectural question,
and it will answer it whichever way the result falls.

### Gates to the prototype decision

**Nothing is ordered until these are answered.** Each changes what the
prototype must contain, and every one of them is cheap relative to the
layout effort it protects — days of work gating months of iteration.

Listed in dependency order, because several feed the ones below them.

**G1 — CPU pinout superset.**
Compare the datasheets across supported cached SX-class parts (TI
486SXLC2, Cyrix 486SLC, IBM 486SLC2) and the Am5x86. Identify every pin
incompatibility and every pin *renaming*.
*Decides:* the size and shape of the CPU pin group.
*Blocks:* G3.

**G2 — HDMI feasibility, on a ULX3S** ([FAKE_TMDS.md](FAKE_TMDS.md)).
Find the ceiling, judged on headroom rather than on whether it works.
*Decides:* whether FPGA video exists; whether the CL-GD5428 needs a
footprint; whether video needs its own memory channel.
*Blocks:* G3, G4. **This single result moves items between MUST and
COULD.**

**G3 — Pin budget**, against 205 usable I/O on CABGA381.
CPU (~76 from G1) + memory groups + HDMI + SPI NOR + SD + ESP32 +
clocks + spares.
*Decides:* whether the memory hedge fits at all, and how wide the shared
groups can be.
*Blocks:* G4, G5, G6.
*Known already:* **the CPU bus does not fit on any single FPGA edge** —
top is 60 balls, right 67, left 65 — so the CPU sits at a corner and
spans two banks.

**G4 — Memory group widths and membership.**
Which parts share the wide group, which share the narrow, and how many
QSPI devices the narrow group is sized for.
*Decides:* the memory hedge.
*Depends on:* G3, and on whether video shares memory (G2).

**G5 — Bank allocation and placement.**
Which signal group lives in which bank, respecting VCCIO grouping,
differential-pair sites and escape routing.
*Decides:* the placement — and therefore most of the routing difficulty.
*Depends on:* G3, G4.

**G6 — BGA population. Has an order-time deadline.**
Per BGA candidate: populated on the run, split across variants, or
dropped. Unlike everything else here, **being wrong means a new order,
not a rework.**
*Depends on:* G3, G4.

**G7 — ESP32 as FPGA configuration master?**
*Decides:* the SPI flash wiring and whether the two share a bus.

**G8 — Power entry**, DC barrel versus ATX header.

**G9 — CPU footprints**: one variant per board, or both present on a
170 mm square.

### Why these come first

Every one is hours-to-days of work. Between them they determine the
placement, and **placement determines whether routing takes weeks or
months.** The failure mode being avoided is discovering a gate answer
part-way through layout, when the sunk cost makes restarting feel more
expensive than pushing on — which is how a bad placement survives to
fabrication.

## Constraints (given, not derived)

| | |
|---|---|
| Form factor | **mini-ITX, 170 × 170 mm** |
| Rear I/O | standard shield window, 159 × 44.5 mm |
| Sockets | **none** — every part soldered, including the CPU |
| CPU supply | **3.3 V required**, so the CPU bus connects to the FPGA with no level shifters |
| BOM | reduced-BOM is a stated design goal, not a preference |
| Expansion slots | **none**, and the form factor could not hold them |

## Reserved resources

- **ECP5 bank 8 — configuration and DFx only.** 13 balls, all
  configuration functions, and the interface the FPGA boots through.
  SPI NOR, the QSPI PSRAM sharing its bus, and DFx are permitted;
  anything else needs a waiver recorded in
  [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md). Do not count these balls as
  general I/O in any pin budget.

## Irreversible at layout — decide these first

The recurring theme of the whole project. Everything in this list is
cheap now and impossible later.

- [ ] **Route every CPU signal to the FPGA**, including ones the first
      bitstream ignores: `KEN#`, `FLUSH#`, `AHOLD`, `EADS#`, `BRDY#`,
      `BLAST#`, `INV`, byte enables, all of it. A programmable chipset
      can start using a signal later; it cannot use one that was never
      connected. **This is the single most likely cause of a respin.**
- [ ] **Route the superset across supported CPU variants.** Cache and
      power-management control on SLC/SXLC-class parts lands on pins the
      base 386SX pinout used differently or left unconnected. A pin that
      is NC on one part and `FLUSH#` on another is invisible in a
      pin-count comparison and fatal in layout. Needs the datasheet
      comparison recorded in the plan.
- [ ] **Commit memory channel pins even where the part is unpopulated.**
      Serial memory makes an extra channel nearly free in pins, and an
      unpopulated footprint costs nothing in BOM — but the pins must
      exist. Applies to both a capacity upgrade path and a possible
      dedicated video channel.
- [ ] **Leave spare FPGA I/O and keep bank voltages flexible.** Same
      argument.
- [ ] **Be conservative on the CPU bus at 33 MHz** — trace length,
      termination, clock distribution. This path *cannot be validated on
      hardware until the chipset front end exists*, so it has to be
      right by construction rather than by measurement.
- [ ] **Do a full pin budget before layout.** Rough shape: CPU bus ~76,
      serial memory ~12 per channel, HDMI 4 pairs, SPI NOR, SD, ESP32
      link, plus clocks and housekeeping. Against ~197 usable I/O on
      CABGA381 that should fit with margin — but "should" is not a
      budget.

## Parts and their board implications

| part | notes |
|---|---|
| CPU | one, soldered, 3.3 V. Am5x86-133, or a cached SX-class part (TI 486SXLC2 class). Footprint differs between them — one board variant per footprint, or both footprints with one populated |
| FPGA | Lattice **ECP5 LFE5U-85F**, CABGA381 |
| Board controller | **ESP32** module — needs antenna keep-out and placement care |
| Far memory | serial PSRAM, channel count TBD |
| Config / storage | SPI NOR (bitstream + BIOS images + config + read-only system); candidate size 64 MiB, of which 8 MiB reserved for dual-boot bitstreams |
| Bulk storage | SD card |
| Video | HDMI direct from the FPGA (see [FAKE_TMDS.md](FAKE_TMDS.md)), and/or a **CL-GD5428** on the local bus |
| Deliberately absent | RJ45, drive connectors, coin cell, expansion slots, optical drive — each removed by a decision recorded in the plan |

## Open

- [ ] **Power entry.** DC barrel with on-board regulation is cheaper and
      smaller than ATX and consistent with the BOM goal. Not decided.
- [ ] **CPU footprints: one variant per board, or both present?** Both
      costs area on a 170 mm square; one means two board variants.
- [ ] **Is the CL-GD5428 populated, footprint-only, or absent?** Gated
      on the HDMI feasibility gate.
- [ ] **Rear I/O set** within the shield window — HDMI and USB are
      likely; what else earns the space.
- [ ] **Whether video gets a dedicated memory channel** — pins are the
      commitment, the part can come later.
- [ ] Layer count, stackup, and impedance targets for the CPU bus.
- [ ] ESP32 ↔ FPGA interface width and whether the ESP32 is FPGA
      configuration master (which would change the SPI flash wiring).

## Deliberately not decided here

Anything that a bitstream can change. If it can be fixed by
re-synthesising, it does not belong in this file.
