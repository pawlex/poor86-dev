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
| **Cuttable bridge + series footprint** | **board area only, zero BOM** | mezzanine isolation, anywhere a part might later need inserting in series |

> **DNP has a package-class limit, and it is easy to miss.** Leaving a
> footprint unpopulated only defers a decision if **a person can actually
> place the part later.** That holds for passives, SOT-23 and SOIC. It
> does **not** hold for fine-pitch QFN or BGA, which need fab placement,
> hot air and a stencil — for most people building a single board, an
> unpopulated QFN is not an option kept open, it is **an option
> foreclosed** while still paying for the area.
>
> So the rule splits by package: **hand-placeable parts may be DNP;
> fine-pitch parts are decided at layout and populated at the factory, or
> they are not on the board at all.** Where such a part is cheap and
> factory-assembled anyway, populating it is the *conservative* choice —
> the opposite of the instinct that applies to everything else here.
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

- **HARD SPEC: the mezzanine is a 386SX-class bus — 16-bit data, 24-bit
  address — not a 32-bit 486 bus.** It promises the **intersection of
  both CPU variants**, so a daughterboard designed against it works
  whichever CPU is fitted; a mezzanine written against a 32-bit bus would
  break the moment an SX-class part was populated.

  **Call it 386SX, never 486SX.** The Intel **486SX is a 32-bit part** —
  a 486 with the FPU disabled — so "486SX bus" reads as a full 32-bit
  486 bus, which is precisely the misreading this label exists to
  prevent. The 16-bit lineage is the **386SX** and the SLC/SXLC parts
  that share its pinout, `TI486SXLC` among them: the "SX" in those names
  refers to the 386SX pinout, not to the Intel 486SX.

  It also lines up with decisions already made: the pin-saver option puts
  both variants at a 16 MB address space anyway, and the CL-GD5428 has a
  16-bit host interface, so the first intended daughterboard wants
  exactly this. Fewer connector pins is a free consequence.

  **The label on the diagram is the warning.** Someone designing a
  daughterboard reads the drawing before the documents, so it states
  the class and the voltage where it
  will actually be seen: `386SX BUS — 3.3 V ONLY`.
- **HARD SPEC: the mezzanine interface is 3.3 V and is NOT 5 V
  tolerant.** This is a protection requirement, not a preference — a
  daughterboard driving 5 V into the connector damages the baseboard.
  It must appear on the connector pinout, in any mezzanine template, and
  silkscreened at the connector.
- **Any translation a daughterboard needs, it does itself.** There is no
  requirement for 5 V at the mezzanine, and no 5 V is provided for
  signalling. A 5 V period part is perfectly usable on a mezzanine — it
  just translates on the mezzanine, where the part is.
- **Baseboard transceivers are optional and non-translating.** Buffers
  may sit between the bus and the connector, but they are 3.3 V on both
  sides. What they buy is isolation rather than translation: the
  connector stub and a daughterboard's loading are kept off the
  CPU-side nets, and a faulty mezzanine cannot drag the CPU bus with it.
- **Survivability: `xx245` octal bus transceiver — footprint present,
  DNP by default, bypassed by a cuttable bridge.** Filed under
  survivability rather than performance: whether the mezzanine path needs
  isolation is **open**, and the cost of being wrong is a respin —
  hundreds of dollars and weeks of overseas transit — against a cost of
  being right of zero. The mezzanine path therefore carries the footprint
  in series with a bridge that shorts across it:
  **Invariant: exactly one of the two is present. Bridge OR transceiver,
  never both.**

  | | bridge | `xx245` |
  |---|---|---|
  | **default** | intact | DNP |
  | **isolated** | **cut** | stuffed |

  Default costs nothing to assemble and requires no decision before the
  boards are made. **If you stuff the 245, you cut the bridge** — the two
  are alternatives, not layers.

  **Getting that wrong is worse than getting no isolation.** A stuffed
  `xx245` with the bridge left intact is a transceiver driving into a
  short across its own output. The signal still passes — through the
  bridge — so the board appears to work while the isolation silently does
  not exist, and the transceiver is fighting a copper short every time it
  drives. Note it on the silkscreen next to the bridges, not only here.

  Roughly **seven packages** cover the bus at 8 bits each: 2 for the 16
  data lines, 3 for `A2-A23`, 2 for control — the SX-class width above,
  not a 32-bit bus.

  **One part number across all three groups is deliberate.** Address and
  control are unidirectional and would strictly want an `xx244` buffer,
  but using `xx245` throughout with direction strapped costs nothing
  electrically and keeps the BOM and the assembly to a single line item.

  Two practical notes. **Cutting is per signal**, so a fully buffered bus
  means on the order of fifty cuts — tedious, and worth laying the
  bridges out in accessible rows rather than scattering them under
  parts. And a cut is **reversible only by soldering**, so treat it as a
  one-way decision per board.
- Without them the stub is just the connector and its short trace,
  unloaded when nothing is fitted. Either way, keep the run to the
  connector short and fold it into the conservative-routing rule.
- A ~33 MHz bus through a board-to-board connector is well within reach:
  ISA ran at 8 MHz through card edges and VL-Bus at 33-50 MHz.
- **Height and case clearance** on mini-ITX. A low-profile board-to-board
  arrangement is needed, not a socket-and-riser.
- The connector itself is BOM and area whether or not a mezzanine is
  ever fitted.

**The interface is 3.3 V throughout, and the daughterboard owns its own
voltage problem.**

The mezzanine connector is a **3.3 V, non-5 V-tolerant** interface. That
is a hard specification: a daughterboard that drives 5 V into it damages
the baseboard.

This does not exclude 5 V period parts — period Cirrus devices among
them — it relocates the responsibility. A daughterboard carrying a 5 V
part translates on the daughterboard, next to the part, where the
designer of that board can see the requirement. The baseboard never
takes a position on anyone else's voltage.

**So: a 3.3 V machine with a 3.3 V expansion bus**, and any legacy
voltage handled where the legacy part lives. Any period peripheral expecting a 386SX- or ISA-style bus can live
there — video, sound, whatever comes later. That quietly restores
expandability to a board with no legacy expansion slots, at the cost of one
connector and a handful of transceivers. It is also the same bus the
soft core drives when no hard CPU is fitted, so mezzanine peripherals
work on both paths without special handling.

#### And that makes the mezzanine the upgrade path, deliberately cheaply

Keeping translation off the baseboard has a consequence beyond the BOM:
it makes the connector **a plain 3.3 V edge interface with no opinions**,
which is the cheapest possible thing to build against.

A daughterboard is therefore a **two-layer board from any low-cost PCB
house** — not a project in its own right. The baseboard imposes only the
bus and the 3.3 V limit, so the designer picks their own voltage domain,
their own parts and their own rules, and pays for translation only if
they actually need it. Translating centrally would have chosen for
everyone, and charged every daughterboard for a 5 V capability most of
them will never use.

**What that makes tractable is not only period video.** Another FPGA with
its own memory, an accelerator, a peripheral nobody has proposed yet —
each is an edge-connector board and a bitstream, with no change to the
machine underneath and no permission required from this repository.

And it can be developed **before any board exists.** The co-simulation in
[vexrv-cpu-oss](https://github.com/pawlex/vexrv-cpu-oss) runs the chipset
against real RTL, so a mezzanine can be written, driven and debugged in
simulation first. The testbench is published rather than left as an
exercise — which is the same reasoning as the rest of the project: the
next person should inherit the working starting point, not reconstruct
it.

- [ ] Decide whether the mezzanine is specified as a **general
      peripheral bus** rather than a video-specific connector. Costs
      nothing extra now and forecloses less later.

#### The mezzanine is not yet formally specified — and needs to be

Everything above describes the mezzanine's *intent*. None of it is a
specification, and **nobody can design a daughterboard against intent.**
This is the gap that most limits other people rather than this board:
"386SX-class bus, 3.3 V" does not tell a designer what to draw.

Writing it is not blocked on anything — the CPU pinmaps are in `Data/`
and the electrical position is already decided. What a spec has to pin
down, roughly in order of what stops someone starting:

- **Connector part, pinout and keying.** Which physical part, and the
  signal-to-pin assignment. Mechanical keying so it cannot seat wrong.
- **The signal list**, with directions and which are optional. Which of
  the 386SX bus appears, and what a card may leave unconnected.
- **The transceiver-control lines** — what the four lines mean and who
  drives them, including the state when nothing is fitted.
- **Electrical limits**: 3.3 V, not 5 V tolerant, plus drive strength and
  the maximum load a card may present per pin.
- **Timing budget at ~33 MHz through a connector** — setup and hold *at
  the connector*, not at the FPGA, with the propagation allowance stated
  so a card designer can spend it.
- **How a slow card extends a cycle**, and what the ceiling on that is.
- **Interrupts back to the FPGA**, and whether they are shared.
- **Address and I/O ranges a card may claim**, and the FPGA's matching
  obligation not to claim them.
- **Power**: which rails, and the current budget per rail.
- **Mechanical**: board outline, mounting, and height under mini-ITX
  clearance.

**The first pass is the physical and electrical specification plus the
pinout**, and the rest follows separately. That split is deliberate:
connector, pinout and electrical limits are a **one-way door** — changing
them later means a board spin for everyone who has built a card against
them — while cycle extension, interrupt handling and decode ranges are
protocol, and protocol lives in a bitstream that can be revised without
anyone reworking hardware. Settle the irreversible layer first, and it
stops holding up the revisable one.

It is also the layer that unblocks other people soonest: with the
connector, pinout, voltage limits and timing budget published, someone
can lay out a card and know it will seat, power up and not damage the
baseboard, even while the protocol above it is still moving.

Two things worth settling before writing it, since they change the
document rather than fill it in: whether the bus is general or
video-specific (the checkbox above), and whether a **reference
daughterboard** ships alongside — a KiCad template plus the
co-simulation harness is a far better specification than prose, and most
of both already exist.

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
- **Every remaining PIO routed to PMOD headers.** Not merely "spare I/O
  brought out" — *all* of it, on the principle that an unrouted ball is
  worth nothing and a routed one costs a track. On the current budget
  that is ~17 balls, so two 8-signal PMODs with one to spare.

  It serves three purposes at once, which is why it is worth the area:
  **bring-up observability** (internal signals brought out to a scope
  without a respin), **expansion** (a standard connector others already
  build for), and **survivability** (if something needs an extra signal
  late, it exists).

  **Choosing PMOD rather than a period connector is the point.** New
  ideas are welcome; they are expected to arrive in a modern idiom. That
  gives the board two expansion paths, each in its own era's terms:

  | path | for | speaks |
  |---|---|---|
  | **mezzanine** | period parts | 386SX bus, 3.3 V, buffered |
  | **PMOD** | anything new | a standard modern header |

  Which is the organising principle applied to expansion rather than to
  peripherals: **period where it has to be, modern where it can be.** A
  period part needs a period bus and gets one. Anything designed today
  has no reason to pretend, and shouldn't be made to.

  **The absence is of *legacy* slots specifically, and that is a
  conclusion rather than a constraint.** Building an expansion ecosystem
  around period cards is a dead end: the supply only shrinks, every card
  needs the bus reproduced faithfully enough to satisfy hardware nobody
  can fix, and the effort scales with a catalogue that is closed. The
  mezzanine supports the specific legacy silicon that actually earns its
  place — and nothing more — while anything new arrives on a header that
  is still manufactured.

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

**G10 — HDMI front end: direct, or via a `PTN3365`?**
([FAKE_TMDS.md](FAKE_TMDS.md) — full analysis and part numbers there.)

> **RESOLVED — video moves to a mezzanine. Both front ends become
> cards.** The baseboard carries **one** set of 4 differential pairs to a
> connector; the front end lives on a card, and the two candidates are
> two cards rather than two baseboard paths.
>
> **Connector: vertical PCI Express ×1, mechanical only.** Decided for
> the prototype.

##### Why the mezzanine resolves this rather than deferring it

| | balls | budget total | fits at full address width? |
|---|---:|---:|---|
| both front ends on the baseboard | 16 | 206 | **no — over by one** |
| **video on a card, two cards** | **8** | **198** | **yes, 7 spare** |

- **It removes the pin-saver dependency.** The dual-path experiment no
  longer forces 16 MB.
- **The comparison gets better, not worse** — same FPGA pins, same
  bitstream, same escape routing. Only the card changes.
- **It unwinds the QFN commitment.** A fine-pitch part cannot be DNP, so
  putting the `PTN3365` on the baseboard meant committing at fab. **On a
  card that is moot — you simply do not build that card.** The risk of
  the "correct" path stops being a board spin and becomes a spare PCB.
- **ESD moves to the card**, beside its connector, which is where
  protection belongs.

##### Why vertical PCIe ×1 rather than M.2

| | **vertical PCIe ×1** | M.2 / NGFF |
|---|---|---|
| card thickness | **standard 1.6 mm** | 0.8 mm — **carries a real price premium at JLC** |
| rear panel | **native** — the standard arrangement already presents a card-mounted connector at the back | flat; reaching the panel is awkward |
| pins | 36 — ample for 8 signals, 2 ID straps and ~26 power/ground | 67 |
| height | upright; accepted for a prototype | ~3 mm |

**Card cost decides it.** 36 pins is comfortable for four pairs at
roughly one return per signal, and the upright card presenting HDMI at
the rear panel is the arrangement mini-ITX already expects.

Height is the concession, and it is **a prototype-only one.** A
production board may fold the winning front end back onto the baseboard
and delete the connector entirely.

> **This is not an expansion slot, and does not contradict the
> no-legacy-slots position.** It is a PCIe connector used as a private
> mezzanine interface with a private pinout — **nothing about it is PCIe
> electrically.** A reader seeing the slot in a photograph will assume
> otherwise, so it should be labelled on the silkscreen.

**No card-ID straps.** They were proposed so the bitstream could detect
which front end is fitted and set drive accordingly. **Not worth it at
this quantity:** the run is **five prototype boards**, operated by the
person who plugged the card in, during a phase when bitstreams are being
rebuilt constantly anyway. A build-time choice costs nothing; automatic
detection would be solving a problem nobody has.

**The connector does not reach production.** It exists on the five
prototypes to settle the comparison, and **the winning front end goes
onto the production baseboard directly** — connector deleted.

That also disposes of the common-mode caveat rather than merely noting
it. The connector sits in both paths, so the A/B comparison is fair; and
because production removes it, **any absolute degradation it contributes
is temporary and does not propagate** into the shipping design. The
number that matters — how the winning front end performs without a
connector in the path — is measured on the production board, where the
question is finally the right one.
>
> The analysis is finished: both paths are fully specified down to part
> numbers, values and populate status, and **no further research is
> required.** What remains is a question about *what is left over*, which
> is not knowable until the CPU bus and memory groups have taken their
> share. A deliberate park with the inputs gathered, not a stall.

##### Superseded: if both were carried on the baseboard

**Do not share one set of pairs between the two paths with 0 Ω
selection.** It is the obvious way to save pins and it **corrupts the
comparison the board exists to make**: whichever path is unpopulated
leaves a stub hanging off the shared net, and a disappointing result then
cannot be attributed — path, or stub? The board would answer a question
nobody asked.

| approach | FPGA balls | verdict |
|---|---:|---|
| shared pairs, 0 Ω select | **8** | **rejected** — stubs compromise the measurement |
| **separate pairs per path** | **16** | clean comparison, both live |

**The cost is 8 additional balls**, against a budget with **15 spare (23
with the pin-saver option)**. It fits — but it consumes half the slack,
and slack is what the rest of this document keeps deliberately in
reserve. Plus a second HDMI connector in the 159 × 44.5 mm rear window,
and the area for both front ends.

**That is the real "resources permitting" test**, and it is a stronger
constraint than fitting either path alone.

*If both do not fit:* fall back to the ordering below — the direct path is
proven and is the default; the `PTN3365` is the upgrade to reach for once
direct has been measured and found wanting.

**Blocks PCB**, and is blocked *by* the allocations above it. The two
paths differ in placement, routing and BOM, so it cannot slip past
layout — but it should not be forced ahead of layout either.

*The summary:* a `PTN3365` converts the FPGA's emulated differential into
**compliant DVI/HDMI output**, which matters more here than usual —
**with EDID dropped there is no runtime fallback, so a refused mode is a
blank screen.** It is also **back-power safe** against a powered monitor
on an unpowered board.

*But it is additive, not substitutive.* The passive count is unchanged —
the eight resistors merely shift from biasing to attenuating — a
system-level **ESD array is required either way**, and it adds a QFN32
plus a `REXT`. It also needs **series attenuation designed and
simulated**, because its inputs are DisplayPort/PCIe-class low-swing and
an `LVCMOS33D` pair is several times that. That conditioning is what
**unrolls the elegance** of the direct approach, whose whole appeal is an
FPGA driving a monitor through eight capacitors and nothing else.

*Decides:* the HDMI front end, its board area, and whether a fine-pitch
part joins the fab-placement list.

*The risk runs the other way from how it first appears.* An earlier draft
here recommended fitting the part "to be safe". **That was backwards.**

| | **direct** | **via `PTN3365`** |
|---|---|---|
| precedent | **two shipping designs** — ULX3S, Tang Nano 9K | **none known** at this interface |
| retired before layout? | **yes** — measurable on a Tang Nano now | **no** — only building it answers it |
| novel engineering | none | attenuator network into a DP-class receiver |
| worst case | marginal signal, degraded | **`IN_Dx` overdrive — unconfirmed maximum, could damage parts** |
| escape hatch | — | **none: QFN, fab-placed, cannot be depopulated** |

**The "correct" path is the one carrying unretired risk.** The direct path
is proven; the `PTN3365` path asks a receiver specified for
DisplayPort/PCIe to accept a conditioned CMOS output, which no reference
design here has demonstrated. **Gating a prototype on that is a gamble,
not a safety measure.**

**And two independent teams already chose direct.** The ULX3S and Tang
Nano 9K both had level shifters and redrivers available and neither used
one. This document already treats their agreement on coupling-capacitor
values as worth more than either alone — **the same reasoning applies to
the architecture choice.** *Caveat, since it is inference rather than
knowledge:* both are low-cost hobby boards where a $2 part weighs more
than it does on a board carrying an Am5x86 and an ECP5-85F. Their
constraint was tighter than ours, so read it as corroboration, not proof.

*If only one is built, decided by — in order, at layout time:*

1. **Measurement.** The Tang Nano 9K runs the direct path on hardware
   already here. If it drives the target displays at the target modes,
   **build direct** — the risk is retired and the elegance is kept.
2. **Remaining board area and FPGA I/O**, which is why this waits for G3
   and G5. Worth separating the two, because they bear on different
   questions:
   - **FPGA I/O pressure barely affects the *front-end choice*.** Both
     paths cost the same 8 balls — four pairs — and the `PTN3365`'s
     `OE_N` and `DDC_EN` strap rather than needing pins. What I/O
     pressure actually decides is whether HDMI survives at all, and on
     **which edge**, which is the gearing question already recorded in
     [PLACEMENT.md](../docs/PLACEMENT.md).
   - **Board area is what decides this gate.** A QFN32, eight
     attenuators, a `REXT` and controlled-impedance routing in and out,
     all near the rear I/O — against a 170 mm square that already carries
     a CPU at an FPGA corner, two memory groups and a mezzanine along one
     edge.
3. **Schedule**, as the final tiebreaker. **It is a legitimate one
   precisely because the fallback is proven** — declining the part under
   time pressure is choosing the demonstrated option, not cutting a
   corner.

*Standing recommendation if unresolved:* **build direct.** It is the
proven path, it is what both reference designs do, and its failure mode
is a degraded signal rather than a damaged part. The `PTN3365` is the
upgrade to reach for **once the direct path has been measured and found
wanting** — not the default to spend prototype schedule on first.

*Depends on:* G2 (whether FPGA video exists at all), then **G3 and G5** —
this gate consumes their leftovers rather than competing with them.

*Note the deferral this buys:* if both paths ship on the validation
vehicle, **the production choice moves from layout time to after
bring-up**, and is then decided by measurement on this board rather than
by inference from other people's. That is the outcome worth spending
slack on.

### Proposal — put the CPU on a mezzanine too

**Not decided.** Recorded because it resolves several open problems at
once and should be settled *before* G3, since it changes the pin budget's
shape.

**The idea:** the CPU does not sit on the baseboard. It lives on a card,
and the baseboard carries a connector.

#### It converts an anticipation problem into a capacity problem

This is the strongest argument, and it is not really about swapping CPUs.

Two items currently stand in this document and in
[PLAN_OF_RECORD.md](PLAN_OF_RECORD.md): *"route every CPU signal to the
FPGA, including ones the first design does not use"* and *"route the
superset across supported CPU variants."* Both exist because **a soldered
CPU forces every variant's needs to be anticipated before fabrication**,
and a signal not routed is a board spin.

With a CPU card, the baseboard routes **N generic connector pins** to the
FPGA and stops. **Each card maps its own CPU onto that assignment.**

- *"Which signals must I anticipate?"* — an anticipation problem, and
  unverifiable, since the answer depends on parts not yet chosen.
- *"How many pins are enough?"* — **a capacity problem, and checkable
  today.**

And it covers what a soldered superset structurally cannot: **CPUs not
yet enumerated.** A soldered board can share pins between the variants it
was designed around; it cannot serve one nobody had thought of. A card
can, because the remapping happens on the card.

#### What it resolves

| open item | effect |
|---|---|
| **G9** — one CPU footprint or two | **dissolved** — the baseboard has none |
| "route the superset" | **dissolved** — becomes a pin count |
| **G1** — CPU pinout superset | **reduced** to "what is the largest signal count worth carrying" |
| board area | SQFP-208 and its escape routing leave a crowded 170 mm square |
| thermal / mechanical | hottest part and any heatsink move off-board |
| supply risk | a future CPU is a **new card**, not a new machine — the ao486 survivability argument becomes physical |
| bring-up | baseboard first on the soft core, CPU cards added incrementally |

#### The residual constraint — clock-capable pins

**One thing a card respin cannot fix: which connector pins land on
clock-capable FPGA balls.** A card is free to map anything anywhere,
*except* that a CPU clock must arrive somewhere the FPGA can treat as a
clock.

- [ ] **Reserve clock-capable balls at the connector**, on any pin a
      future card might plausibly drive a clock into. This is the one
      place where anticipation is still required, and it is cheap.

#### What it does not solve

- **FPGA I/O is unchanged.** Those signals still reach the FPGA; they
  arrive via a connector instead of a package. The 205-ball budget binds
  exactly as before, and how many CPU signals to carry is still a
  decision — the full Am5x86 set is 113, the essential set 97, the
  pin-saver set 89.
- **It adds a second board-to-board connector** to a board that already
  has one at its edge, with the case-height question that implies.

#### Precedent and connector

**VL-Bus is the existence proof** — the 486 local bus on a card edge at
33–50 MHz, as a shipping standard. `Data/VL_Bus_2.0_199311.pdf` is the
reference to design against rather than deriving the timing budget from
scratch.

**A PCIe ×16 mechanical connector is the candidate** — the connector and
card edge only, nothing PCIe about it electrically:

- **164 contacts**, so 113 signals still leaves ~51 for power and ground
- **accepts standard 1.6 mm PCB**, unlike DDR3 sockets which want 1.27 mm
- cheap and universally available
- **the card side is bare PCB** — no connector to buy or solder, which is
  the property that makes spinning a CPU card cheap and fast

- [ ] **Check the 486 bus timing budget at 33 MHz** against the added path
      and connector, using VLB's rules as the reference. Desk work, with
      the spec already in `Data/`.
- [ ] **Decide the signal count** the connector carries, which is G1
      restated as a capacity question.
- [ ] **Case height with two cards** on mini-ITX.

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
| **Build quantity** | **five prototype boards** — calibrates rework, assembly and part-cost decisions throughout |
| Form factor | **mini-ITX, 170 × 170 mm** |
| Rear I/O | standard shield window, 159 × 44.5 mm |
| Sockets | **none** — every part soldered, including the CPU |
| CPU supply | **3.3 V required**, so the CPU bus connects to the FPGA with no level shifters |
| BOM | reduced-BOM is a stated design goal, not a preference |
| Legacy expansion slots | **none** — see below; specific legacy parts are supported on a mezzanine instead |

## Power: as drawn in the schematic

From `PCB/AsicPowerGnd.kicad_sch` — this is what exists, not a proposal.

| | |
|---|---|
| entry | **ATX-20** (J1) |
| regulators | **3x TLV62569DBV** synchronous buck (U2, U4, U6) |
| rails | **+3V3, +2V5, +1V1** from +5 V |
| adjust | **JP6 solder jumper — "Closed = 3.3 V, Open = 3.5 V"** |

### +5 V exists on the board — it just never touches the FPGA

**Distinguish the rail from the domain.** The board takes +5 V in and
derives +3V3, +2V5 and +1V1 from it, so **a 5 V rail is available** for
connectors, USB VBUS, an HDMI sink's +5 V pin, fans, and anything else
that wants it.

**What is prohibited is a 5 V *signal* reaching an FPGA pin.** The ECP5
is 3.3 V and not 5 V tolerant. Every crossing needs translation or
isolation, and the burden sits with whatever needs 5 V — the same
principle already applied at the mezzanine.

This matters because *"no 5 V on the board"* is wrong and would rule out
things that are perfectly fine — powering USB, feeding a display's +5 V
pin. **"Nothing in the 5 V domain connects directly to the FPGA"** is the
actual constraint, and it is the one to state in reviews.

The schematic annotations give the feedback maths for a 0.6 V reference:

```
(15k/18k  + 1) * 0.6 V = 1.10 V     core
(15k/4.7k + 1) * 0.6 V = 2.51 V     VCCAUX
(15k/3.3k + 1) * 0.6 V = 3.33 V     JP6 closed
(16k/3.3k + 1) * 0.6 V = 3.51 V     JP6 open
```

So JP6 swaps the upper divider leg between 15k and 16k. The mechanism is
a solder jumper on the feedback network, not a trim pot — set at build,
changeable with an iron.

**JP6 is aimed squarely at the Am5x86 margin.** That part is nominally ~3.45 V, so a 3.5 V setting matches the
CPU rather than asking it to run 150 mV low. This is a better answer than
the level-shifter footprints recorded elsewhere: it removes the mismatch
instead of translating across it.

- [ ] **Confirm what the 3.5 V setting feeds.** ECP5 VCCIO for LVCMOS33
      has a *recommended* range around 3.135-3.465 V, so **3.5 V is above
      the recommended VCCIO** — fine for the CPU, out of spec if the same
      rail also feeds FPGA banks. Either the CPU gets its own rail, or
      the jumper is understood as CPU-only. This needs checking against
      the ECP5 datasheet before it is relied on, because it interacts
      with the "all VCCIO is 3.3 V" decision.
- [ ] With that resolved, decide whether the level-shifter footprints are
      still wanted, or whether JP6 supersedes them.

### The schematic already carries a pin-saver option

Annotated on both the FPGA and Am5x86 sheets:

> *"pin saver option. Reduces address space to 16 MB"*

Dropping `A24-A31` takes the CPU bus from **97 pins to 89**, and the
total budget from 190 to **182 of 205 — 23 spare** rather than 15.

Two things make this cheaper than it sounds:

- **16 MB is already the machine's ceiling on the SX-class path**, since
  a 24-bit address bus is all those parts have. Taking the option makes
  the two CPU variants agree on address space instead of diverging.
- 16 MB is generous for DOS. The plan of record puts guest RAM at
  single-digit megabytes.

- [ ] Decide whether to take it. It is the cheapest 8 pins available and
      the only cost is address space the software will not use.

### JTAG comes from a CH552, not the FPGA

`external_perif.kicad_sch` maps JTAG onto a **CH552T**: `TCK` on P1.7,
`TDI` on P1.5, `TDO` on P1.6 (all multiplexed onto its hardware SPI) and
`TMS` bit-banged on P1.4.

So JTAG never touched the FPGA pin budget — it arrives over USB from a
small microcontroller. That answers one of the "what gets dropped to fit"
questions before it was asked.

### Status of the existing schematic and layout: a study, not a decision

**`PCB/` predates the methodical phase.** The schematic and the initial
board revision were drawn first, and the decision to stop and work
through the architecture came afterwards. They record exploration, not
commitments.

So where they differ from the plan of record, **the plan is current and
the schematic is history** — these are not conflicts to reconcile:

- The schematic instantiates **`LFE5U-25F-6BG256C`** — a 25F in BG256 —
  where the plan assumes **LFE5U-85F in CABGA381**. Every ball count and
  the whole pin budget are written against the 85F.
- An **ATX-20** connector is fitted, where `BOARD.md` records DC barrel
  as preferred on BOM and size grounds and lists power entry as still
  open.

**What the study produced is still valuable, and is treated as input:**

- the **pin saver option** and its 16 MB consequence
- the **VREG topology and feedback maths**, including JP6
- **JTAG on a CH552T**, off the FPGA budget entirely
- the **CL-GD54xx DRAM pin redefinitions** captured in
  `video.kicad_sch` — `CAS` redefined as `WE`, `OE` as `RAS1`, `WE[3:0]`
  as `CAS[3:0]`, with the databook pages cited — which is real work
  someone would otherwise repeat
- the FPGA **configuration mode straps**

Those findings stand on their own. The part choices around them do not.

- [ ] When layout resumes, decide explicitly what carries over from the
      study and what is redrawn. The value is in the annotations and the
      worked details, not in the placement.

## Storage buses: configuration and bulk are separate

**Two buses, deliberately not shared.**

| bus | on | carries |
|---|---|---|
| **hard SPI config** | bank 8 config pins | the **configuration EEPROM** — the FPGA's bitstream |
| **dedicated QSPI** | general I/O, ~7 pins | **QSPI SPI NOR** (BIOS images, reset-exit config, read-only system) + **QSPI PSRAM** sharing it on a second chip select |

Splitting them buys three things:

- **Bank 8 becomes genuinely single-purpose.** The reservation is easier
  to hold when the bank does exactly one job, and configuration is never
  competing with anything for it.
- **The bulk NOR runs at full QSPI speed under user control**, rather
  than being constrained by the configuration interface it would
  otherwise share.
- **Configuration cannot be disturbed by runtime storage traffic**, which
  matters because a corrupted configuration path is the failure that
  cannot be recovered in the field.

The QSPI PSRAM still shares a bus by design — now the dedicated one, not
the configuration one — so it still costs a single extra chip select. The
contention note stands: NOR used as a read-only system store and PSRAM
used as main memory are both continuous, and the two are compatible only
if one is idle.

## Clocking: a single 50 MHz oscillator on GPLL0

**One 50 MHz oscillator, into a GPLL0 input.** Everything else is
synthesised on-chip — CPU bus clock, memory clock, pixel clock — so the
board carries one clock source rather than several. That is the right
trade on a pin-constrained design: a dedicated PLL input costs one pin
and removes the need for separate oscillators and their pins elsewhere.

**It must land on a dedicated GPLL input**, not general I/O. There are
four GPLL0 inputs, one per die corner:

| corner | true (T) | comp (C) | bank | edge |
|---|---|---|---|---|
| upper-left | **A4** | A5 | 7 | PL |
| lower-left | **P3** | P4 | 6 | PL |
| upper-right | **C18** | D17 | 2 | PR |
| lower-right | **U16** | T17 | 3 | PR |

(GPLL1 also exists at the two upper corners on PT — A6/B6 in bank 0 and
A19/B20 in bank 1.)

**Cost is one pin** for a single-ended oscillator: drive the **T** input
and leave the C pin free. Two only if a differential source is ever used.

- [ ] **Pick the corner.** A left-hand GPLL0 — **A4** or **P3** — puts
      the PLL nearest the memory on PL, which is where the timing-critical
      logic will be. PL also has the slack: 52 of 65 balls allocated. The
      right-hand corners sit under the CPU bus, which is the busier edge.
**SDRAM runs at CPUCLK × 2.** With a 33 MHz CPU bus that is ~66 MHz, and
both fall out of the 50 MHz reference on clean ratios:

```
CPU bus    50 MHz x 2/3 = 33.33 MHz
SDRAM      50 MHz x 4/3 = 66.67 MHz   = CPUCLK x 2 exactly
```

The point is not the bandwidth — the memory is already over-specified for
this machine — it is the **fixed integer phase relationship**. At exactly
2x, the memory controller gets two SDRAM cycles per CPU cycle with no
clock-domain crossing and deterministic timing between the two, which
removes synchroniser latency from precisely the path the whole
latency argument is about.

- [ ] **Check the pixel clock is synthesisable from 50 MHz.** 33 MHz for
      the CPU bus is a straightforward ratio, but exact VGA pixel clocks
      are not — 25.175 MHz from 50 MHz needs a fractional ratio the PLL
      may only approximate. Displays generally tolerate a small error,
      but this belongs in gate G2 rather than being assumed.

## Reserved resources

- **ECP5 bank 8 — configuration and DFx only.** 13 balls, all
  configuration functions, and the interface the FPGA boots through.
  **The configuration EEPROM lives here, on the hard SPI config pins, and
  nothing else does** except DFx. Anything further needs a waiver
  recorded in [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md). Do not count these
  balls as general I/O in any pin budget.

  The bulk **QSPI SPI NOR is *not* here** — it has its own bus, below.

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
| Deliberately absent | RJ45, drive connectors, coin cell, legacy expansion slots, optical drive — each removed by a decision recorded in the plan |

## CPU bus routing tiers — and what may share the VCC plane

Full derivation in [PLACEMENT.md](PLACEMENT.md); the summary is here
because it constrains the stackup.

**The classifier is the databook's own timing split**, not an estimate of
how busy a signal looks:

| spec | meaning | class |
|---|---|---|
| **`t14`/`t15`** | synchronous — sampled every clock, in the command and termination window | **full care** |
| **`t20`/`t21`** | asynchronous — setup and hold needed only for *recognition* in some clock | relaxed |

**Ten of the 99 CPU signals are candidates for routing on internal layer
2, the VCC plane.**

| | signals | note |
|---|---|---|
| **Unconditional** | `A20M` `FLUSH` `IGNNE` `SRESET` `NMI` `FERR` | asynchronous by specification; **no later decision can promote them** |
| **Conditional** | `BREQ` `BOFF` | promote if real multi-master arbitration is adopted |
| | `EADS` | promotes if active snooping is adopted — and **`INV` must share its layer**, being a same-clock relationship |
| | `RESET` | qualifies on a millisecond-scale budget; **needs a test point**, since burying the signal most wanted during bring-up is a practical cost |

**Explicitly not candidates:** `BS8` `BS16` `WB/WT` `HITM` `KEN` `RDY`
`BRDY` `AHOLD` `INV`. `BS8`/`BS16` are driven by the peripheral to
indicate whether a second, third or fourth bus cycle must occur — they
are **command bus clock domain**, sampled every clock before `RDY`, and
their inactive level is meaningful data. **Static is not the same as
slow.**

**Three conditions on the technique itself:**

- **All ten must be actively driven, not resistor-pulled.** The risk of
  relaxed routing here is coupling rather than delay, and a low-impedance
  driver makes a static line hard to glitch. `IGNNE` (internal pull-up)
  and `SRESET` (internal pull-down) fail this if left to their internal
  resistors.
- **No tier 3 signal may cross a plane channel.** Slots in a reference
  plane break the return path of whatever crosses them on adjacent
  layers — the cost lands on the *fast* bus, not on the slow signals that
  caused it.
- **Channels stay short and follow the plane periphery.** Slots raise
  plane impedance, and the Am5x86 at 3.45 V is not a small load.

**If the CPU moves to a mezzanine, the same tiering applies to connector
pin assignment** — tier 1 takes the positions with the poorest ground
return, tier 3 takes the good ones.

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
- [ ] **Layer count, stackup, and impedance targets for the CPU bus.**
      **Now carries a dependency** — see the routing tiers below, which
      assume some of the CPU bus can be relieved onto the VCC plane. If
      layer 2 ends up adjacent to a top-layer CPU bus, that assumption
      fails and the pin escape gets harder.
- [ ] ESP32 ↔ FPGA interface width and whether the ESP32 is FPGA
      configuration master (which would change the SPI flash wiring).

## Deliberately not decided here

Anything that a bitstream can change. If it can be fixed by
re-synthesising, it does not belong in this file.
