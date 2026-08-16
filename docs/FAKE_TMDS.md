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

**And it does test the emulated-differential technique** — read the
schematic and the source rather than assuming.

Sipeed's own `svo_hdmi.v` instantiates **`ELVDS_OBUF`** — Gowin's
***E*mulated* LVDS, not `TLVDS_OBUF` (true LVDS) — driven by a hard 10:1
serialiser, `OSER10`. The HDMI pins sit in **Bank 1 at 3.3 V**, shared
with the RGB LCD pins.

So this is the same class of technique planned here: complementary CMOS
outputs emulating a differential standard into a TMDS sink. It is a
closer analogue than a board with real LVDS drivers would have been.

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

**Only this board's own layout and termination.** That is a narrower gap
than it first appeared: the Tang Nano does exercise emulated differential
through an AC-coupled front end, so the *technique* is demonstrable on
hardware already here. What remains is trace impedance, coupling-cap
placement and connector transition on **this** PCB — which no borrowed
board could ever have answered.

That is acceptable, because the technique is not the risk. It is
documented in the ECP5 datasheet with a termination scheme (Figure 3.1),
it ships working on the ULX3S, and there are multiple public
implementations. **The residual risk is this board's own layout and
termination**, which no borrowed hardware could have de-risked anyway.

### Two reference front ends, compared

Both boards emulate differential output, and **both AC-couple.** The Tang
Nano front end is fully verified here from its schematic (sheet
`FPGA_HDMI`, rev 3672); the ULX3S values are from published sources
rather than a schematic read.

| | **Tang Nano 9K** | **ULX3S** |
|---|---|---|
| driver | `ELVDS_OBUF` (emulated) | `LVCMOS33D` (emulated) |
| serialiser | `OSER10`, hard 10:1 | fabric / `ODDRX1F` |
| **coupling** | **100 nF series, all 8 lines** | **220 nF series** (100 nF on a later fork) |
| bias / termination | **49.9 Ω pull-up to +3V3 per line** | not verified here |
| ESD | **`RCLAMP0524P` ×2** (4 channels each) | not verified here |
| DDC | SCL/SDA pulled up 1.5 kΩ to +5 V; CEC 27 kΩ | 3.3 V↔5 V I²C level shifter |

**The Tang Nano signal chain, in order:** FPGA pin → 49.9 Ω to +3V3 →
100 nF series cap → ESD clamp → HDMI connector.

That pull-up is worth understanding rather than copying blindly. It puts
**a ~50 Ω source-side termination referenced to 3.3 V** on the driver
side of the coupling cap — roughly mirroring what the sink does with its
own 50 Ω to AVCC — while the capacitor keeps the two DC domains apart.

**Where the two designs converge is the useful part:** two independent
teams, two FPGA families, both emulating differential into a TMDS sink,
and both chose **series capacitors in the 100–220 nF band.** That is the
75–200 nF industry guidance, arrived at twice.

**For the BOM here** that means, per line: one series capacitor
(100 nF is the value both converge on), a 49.9 Ω pull-up to 3.3 V, and a
shared ESD clamp array — eight lines, so two four-channel parts.

### EDID stays; DDC does not — the data comes from a ROM

**Separate the wire from the data.** They are usually one thing and do
not have to be.

- **DDC is out entirely — no I²C master, and the pins are not brought
  out to the connector.** `SCL`, `SDA` and `CEC` are left unconnected at
  the HDMI connector. That removes the I²C master in RTL, a **5 V-to-3.3 V
  crossing into the FPGA** (see
  [BOARD.md](BOARD.md) — the board has a 5 V rail; what it will not have
  is 5 V reaching an FPGA pin), and the runtime negotiation path.
- **EDID — the data structure — stays in the design**, supplied from **a
  small ROM** rather than read off the display.

So the mode logic still consults a real EDID blob and is not hardcoded
against a mode list baked into RTL. It simply gets those bytes locally.

**And the ROM can be supplied upstream by the ESP32.** This is the same
mechanism already carrying the CMOS time base, `etc/e820` and the NE2000
MAC address: the chipset reset-exit vector reads configuration from the
controller. **EDID becomes one more item in that payload**, which means
it is updatable without a bitstream rebuild — a user with an awkward
display can be given a different blob rather than a different board.

**Why keep the EDID format at all**, rather than a private table? Because
it costs nothing and buys two things: existing tooling writes, parses and
validates it, and a **real** display's EDID can still be obtained
out-of-band — read on any other machine, handed to the ESP32, and served
as the blob. The machine never reads a monitor; it can still be *told*
what a monitor said.

**Recoverable by bodge, not by respin.** The DDC pins get **0 Ω
footprints at the connector, DNP**, with the far side landing on an
isolated pad rather than a routed net. Nothing reaches the FPGA, so the
pins, the 5 V domain and the RTL are all still saved — but the signals
are *present at a pad* instead of stopping dead at the connector.

If DDC is ever wanted: stuff the 0 Ω parts and run wire from those pads
to spare PMOD I/O, of which there is a deliberate surplus. The I²C master
becomes bit-banged on general PIO, which is cheap, and the whole
capability comes back as **an afternoon of rework rather than a board
spin.**

Applies to `SCL`, `SDA`, `CEC` and `HPD`.

**And a level-shifter footprint on that path, also DNP.** Cheap in board
area, nothing in BOM, and it turns a compromise into the conventional
circuit. The chain becomes:

```
HDMI connector  →  0 Ω (DNP)  →  level shifter (DNP)  →  bodge pad  →  PMOD I/O
                   5 V side  ────────────────────────  3.3 V side
```

With it stuffed, **the connector side can be pulled up to 5 V the way
DDC normally is** — the Tang Nano uses 1.5 kΩ to +5 V — while the FPGA
side stays 3.3 V. This is what the ULX3S does too: its GPDI carries a
3.3 V↔5 V bidirectional I²C level shifter.

A single small bidirectional part (a `PCA9306`-class device, or a
`TXS0102`) is preferable here to the discrete dual-MOSFET arrangement,
despite being slightly dearer: **during a rework, fewer parts to stuff is
worth more than a cheaper BOM line** that will most likely never be
bought.

> **The 3.3 V rule still holds on the bodge path.** Any pull-ups added
> **the FPGA side is 3.3 V, always.** A 5 V rail *is* available on the
> board, which is exactly what makes this worth writing down — the
> temptation during rework is to reach for the nearest supply, and the far
> end of that bodge is a pin that is not 5 V tolerant.
>
> **With the level shifter stuffed**, 5 V pull-ups on the *connector* side
> are correct and conventional. **Without it**, everything on the path
> stays 3.3 V — DDC is open-drain, so that works with most sinks, and the
> sink's own EEPROM does not care what voltage the bus idles at. Both are
> valid; what is never valid is 5 V continuing past the shifter position
> toward the FPGA.

> **Not the same pins:** `+5V` (pin 18) and `HPD` (pin 19) are separate
> from DDC and serve a different purpose — a sink draws that rail and
> asserts hot-plug on it. **Dropping DDC is not a reason to drop those**,
> and some sinks expect the +5 V rail present before they treat a source
> as active. Left as an explicit open below rather than decided here.

**Two things this does not fix:**

- **A canned EDID is a claim, not knowledge.** It says what the machine
  is willing to emit, not what the attached display accepts. Wrong blob,
  wrong answer — the honesty is in the sourcing, not the format.
- **There is still no detection of refusal**, so a refused mode is a blank
  screen with no runtime fallback. The output mode must be one that always
  works, which argues for **a fixed, safely-accepted output mode with the
  guest's mode scaled into it** rather than switching output to follow the
  guest. It strengthens the scaler case rather than weakening it.

> **Prototype build note — use a large footprint for the 49.9 Ω
> pull-ups.** On prototype boards these eight resistors should be an
> oversized package — 0805 or 1206 rather than 0402 — specifically so
> they are **easy to lift with an iron.**
>
> The pull-up is the one part of this front end taken on the authority of
> someone else's board rather than measured on ours. If it turns out to
> be wrong here — wrong value, or unwanted against a particular sink —
> the fix is removing or changing eight parts on assembled hardware.
> Making that a five-minute rework instead of a careful one costs nothing
> at prototype stage and can be dropped to the small package once the
> value is confirmed.
>
> Same reasoning as the DNP footprints and cuttable bridges elsewhere in
> [BOARD.md](BOARD.md): file it under survivability.

### Build sheet — the HDMI front end, consolidated

Everything decided above, in one place, so the front end can be laid out
without reading the narrative around it. **8 TMDS lines** = D0±, D1±,
D2±, CK±.

**Signal path, per TMDS line:**
`FPGA pin → 49.9 Ω to +3V3 → 100 nF series → ESD clamp → connector`

| qty | part | value | populate | why |
|---:|---|---|:-:|---|
| 8 | resistor, **0805 or 1206** | 49.9 Ω 1% | **yes** | pull-up to +3V3; source-side bias and ~50 Ω termination. **Oversized package deliberately** — the one value taken on another board's authority, so make it liftable |
| 8 | capacitor | 100 nF | **yes** | series AC coupling; blocks DC so the swing rides the sink's own bias. **Still external** — the companion chip below does not provide these |
| **1** | **`TPD12S521`** | — | **yes** | **replaces the entire discrete front end** — see below |
| 2 | capacitor | 0.1 µF | **yes** | `ESD_BYP` (pin 37) is mandatory; `HOTPLUG_DET_OUT` (pin 20) raises the ESD rating |

#### Superseded — the `PTN3365` regenerates TMDS rather than protecting it

**Decision: `PTN3365BS`, populated, not DNP.** The `TPD12S521` analysis
below is kept because the reasoning still holds for what it does; it is
simply the lesser answer.

**The difference is what happens to the signal.** The `TPD12S521` clamps
and passes TMDS through untouched — whatever the FPGA emitted arrives at
the connector, emulated warts and all. The `PTN3365` **converts four
lanes of low-swing AC-coupled differential input into DVI v1.0 and HDMI
v1.4b compliant open-drain current-steering output**, terminated into
50 Ω to 3.3 V at the sink.

Read that input description again: *low-swing, AC-coupled,
differential.* **That is exactly what an FPGA emulated-differential
output through series capacitors produces.** The part is specified for
the signal this board already makes, and emits the signal a monitor
actually wants.

| | |
|---|---|
| package | **HVQFN32** — not a BGA, and **in JLCPCB's assembly library at <$2 @ qty 1**, so factory placement is routine |
| supply | single **3.3 V**, 230 mW typical |
| rate | **3.0 Gbit/s per lane** |
| DDC | active buffer, 3.3 V source ↔ 5 V sink |
| HPD | active buffer, 5 V sink → 3.3 V source |

**What this changes, and what it does not:**

- **It removes the signal-integrity risk class.** The output is compliant
  TMDS, not an emulation hoping to be accepted. The one gap this document
  said only our own board could close — *"whether emulated differential
  survives to the connector"* — largely stops existing. What remains is
  ordinary high-speed layout.
- **It does not raise the FPGA's ceiling, and the mode table is
  unchanged.** 3.0 Gbit/s is the *part's* capability. The FPGA still
  cannot serialise faster than **500 Mb/s on PT** or 624/700/800 Mb/s on
  PL/PR by speed grade. **A 3 Gbit/s part on the far side of a 500 Mb/s
  serialiser is still a 500 Mb/s link** — the gearing analysis above
  stands untouched, and the PT-versus-geared-edge decision is unaffected.
- **It makes DDC nearly free** — an active DDC buffer is present whether
  or not it is used. That does not reverse the EDID-from-ROM decision, but
  it does mean the 0 Ω bodge pads now sit on a part already doing the
  translation.
- **"Required, not DNP" is forced, not preferred.** The DNP pattern
  elsewhere assumes a person can place the part later with an iron. **An
  HVQFN32 cannot be added as a rework by most people building one board**
  — it needs fab placement, hot air and a stencil. Leaving it unpopulated
  would not defer the decision, it would *foreclose* it. So it is decided
  now and placed at the factory, which at JLC assembly prices costs
  nothing to commit to.

##### Component-level ESD is not system-level ESD

**`6 kV HBM / 1 kV CDM` does not qualify the connector.** Those are
JEDEC component ratings, and per TI's own guidance they are

> *"useful in verifying the component's ability to survive manufacturing,
> assembly, and shipping but does not represent what a component
> experiences in an end-user scenario"* — SLLA305A §4.2

HBM specifically *"simulates a human body discharging onto a grounded
device **in a controlled factory environment**."* **An HDMI port is the
opposite of a controlled factory environment** — it is the one connector
on this board a person handles, repeatedly, often while touching the
chassis.

The applicable standard is **IEC 61000-4-2**:

| level | contact (±kV) | air (±kV) |
|:-:|:-:|:-:|
| 1 | 2 | 2 |
| 2 | 4 | 4 |
| 3 | 6 | 8 |
| **4** | **8** | **15** |

> **The trap is that the numbers look comparable and are not.** "6 kV HBM"
> sits next to "level 3 = 6 kV contact" and invites the conclusion that
> the part is already there. It is not: HBM discharges 100 pF through
> 1.5 kΩ, while IEC 61000-4-2 discharges 150 pF through **330 Ω**, giving
> a far faster rise and a much higher peak current. **The same voltage
> number is a substantially harsher event.** Never read one as the other.

**So the front end keeps a dedicated ESD array, placed between the
`PTN3365` and the connector** — protection belongs on the connector side
of what it protects, as close to the connector as layout allows.

- **Target IEC 61000-4-2 level 4** — ±8 kV contact, ±15 kV air.
- **Still under ~1 pF per channel**, per the selection rule above.
- **A pure ESD array, not another companion chip.** A `TPD12S521` would
  also satisfy the ESD requirement, but it duplicates the DDC and HPD
  buffering the `PTN3365` already does, and putting two active buffers in
  series on those lines is worse than either alone.

Net BOM for the front end: **`PTN3365` + one low-capacitance ESD array +
8 coupling capacitors**, and the pull-ups pending the check below.

##### Resolved from the datasheet — and one complication

Datasheet in hand (`PTN3365`, NXP, 2015). Every open item closes, and two
things appear that were not accounted for.

- [x] **Connector-side ESD — a second part stays in the BOM.** The
      datasheet labels both figures **"Component level"** in its own
      footnotes, confirming from the primary source what was inferred
      above.
- [x] **The 49.9 Ω pull-ups come out.** The part has *"integrated 50 Ω
      termination resistors for AC-coupled differential input signals"*
      and the `IN_Dx` pins are **self-biasing**, average input voltage
      specified at 0 V. External pull-ups to 3.3 V would fight that bias.
      **Keep the 100 nF** — *"the input to this pin must be AC coupled
      externally."*
- [x] **`OE_N` (pin 17) costs no FPGA pin — strap it LOW.** `HIGH` puts
      `IN_Dx` termination and `OUT_Dx` into high impedance; `LOW` gives
      50 Ω termination and active outputs. Optionally *worth* driving
      later, as a clean blanking and power-save control. `DDC_EN`
      (pin 23) straps likewise.

**⚠ The complication: this part expects a DisplayPort/PCIe source, not a
CMOS output.**

> *"PTN3365 features low-swing self-biasing differential inputs which are
> compliant to the electrical specifications of **DisplayPort Standard
> v1.2 and/or PCI Express Standard v1.1**"*

Those standards put the input around **0.4–1.2 V peak-to-peak
differential.** An ECP5 `LVCMOS33D` pair swings rail to rail — on the
order of **3.3 V single-ended**, several times the intended input, into
an internal 50 Ω termination that a CMOS driver cannot properly drive
anyway.

**So series attenuation is required between the FPGA and this part** — a
resistor per line forming a divider against that internal 50 Ω, sized to
land the swing inside the DisplayPort range.

There is a pleasing irony in where that lands. Dividing 3.3 V CMOS down
to a few hundred millivolts across 50 Ω puts the series element in the
**low hundreds of ohms** — the same neighbourhood as the classic
fake-TMDS series resistors. **The resistor network returns in a different
role:** not shaping TMDS for a monitor, but conditioning a CMOS output
into a DisplayPort-class receiver.

- [ ] **Compute and simulate that network** — series R against the
      internal 50 Ω with the 100 nF in path, at rate. Edge rate degrades
      as series R rises, so it is a trade rather than a lookup.
- [ ] **Confirm the `IN_Dx` absolute maximum.** The limiting-values table
      specifies the CMOS pins but not the differential inputs.
      **Over-driving must be ruled out, not assumed** — the one item here
      that could damage parts rather than merely perform badly.

**Also new to the BOM:** `REXT`, **10 kΩ 1% from pin 6 to GND** — the
reference for output current steering. *"Operation without external
reference resistor is possible but will result in reduced output voltage
swing"*, so treat it as required.

**Two points in the part's favour**, both worth having:

- **Outputs are back-power safe** — a powered monitor cannot drive current
  back into an unpowered board. A real hazard on a machine people leave
  connected.
- **Fully transparent: no re-timing, no state machines, nothing latched or
  clocked, no I²C.** Whatever the FPGA emits is what leaves, level
  shifted — so every timing question stays upstream, where the gearing
  analysis above already put it.

##### Takeaway: the `PTN3365` is additive, not substitutive

**It buys compliance at the monitor and costs elegance at the FPGA.**
Stated plainly, because the earlier framing here read as if one part
replaced a pile of others, and the datasheet does not support that.

| | **direct — the "poor" path** | **via `PTN3365`** |
|---|---|---|
| coupling caps | 8 | 8 |
| 8-resistor group | pull-ups / bias | **attenuators** |
| `REXT` | — | 1 |
| level shifter IC | — | **1, QFN32, factory-only** |
| **ESD array** | **1 — required** | **1 — still required** |

**The passive count does not change.** The eight resistors merely change
job — from biasing the line, to attenuating a CMOS output down into a
DisplayPort-class receiver. **The ESD array is required either way**,
because a user-accessible connector needs system-level protection
regardless of what drives it. So the `PTN3365` removes nothing from the
board; it adds an IC and a reference resistor.

**And it does dull the idea.** The appeal of the direct approach is that
an FPGA talks to a monitor through eight capacitors and nothing else.
Adding a stage whose *input* needs conditioning trades that away — and
the irony is that both paths face the same electrical problem, driving
CMOS into a 50 Ω termination. The `PTN3365` does not remove that problem;
it **relocates** it, and pays an IC for a compliant result on the far
side.

**What it genuinely buys**, and this is not small:

- **Compliant DVI/HDMI output** rather than an emulation hoping to be
  accepted — which matters more here than usual, because with EDID gone
  there is no runtime fallback and a refused mode is a blank screen.
- **Back-power safety** against a powered monitor on an unpowered board.
- **Removal of a risk class** before a board spin, on a board whose author
  estimates spins in months.

**So it is a risk-versus-elegance trade, and it should be settled by
measurement rather than taste** — see the display-acceptance gate below.
The Tang Nano 9K runs the direct path, in emulated differential through
AC coupling, on hardware already here. **If it drives the target displays
at the target modes, the cheap path is earned with evidence** and the
`PTN3365` can be dropped in a later spin with the reasoning on record.
If it is marginal, the trade has paid for itself.

**Corrected: the conservative choice is the direct path, not this one.**
An earlier reading here treated fitting the part as the safe option. It is
not. The direct path's risk is **already retired by two shipping
designs** and is measurable on a Tang Nano before layout; the `PTN3365`
path's risk is **novel and unretired** — an attenuator into a
DisplayPort-class receiver, with an `IN_Dx` maximum that is not confirmed
and a QFN that cannot be depopulated if it disappoints. **Gating a
prototype on that is a gamble dressed as caution.** See G10 in
[BOARD.md](BOARD.md).

#### The `TPD12S521` collapses this to one part

A single-chip HDMI **transmitter-side** port protection and interface IC,
and it fits this design almost suspiciously well.

| what it replaces | |
|---|---|
| 2× 4-channel ESD arrays | **0.8 pF** per TMDS channel, 0.05 pF matched across each pair, IEC 61000-4-2 level 4 at ±8 kV |
| the DDC/CEC level shifter | bidirectional, `LV_SUPPLY` system side ↔ 5 V for `SDA`/`SCL`/`HPD`, 3.3 V for `CEC` |
| a 5 V load switch for pin 18 | `5V_OUT` with on-chip current limiting |

**Four things make it the right choice rather than merely a convenient
one:**

- **38-pin TSSOP (DBT), 0.5 mm pitch — not a BGA.** It satisfies the hard
  packaging constraint outright and can be placed by hand.
- **It costs zero FPGA pins.** The pin list is fully accounted for with
  **no enable, OE or control pins** — 2 supplies, 10 grounds, 16 TMDS, 4
  system-side logic, 4 connector-side logic, `ESD_BYP`, `5V_OUT`. The part
  is transparent and always on, so nothing has to drive it.
- **`LV_SUPPLY` accepts 1–5.5 V and is specified at 3.3 V typical**, which
  is the system-side rail this board already has.
- **The pin order follows the HDMI connector**, at connector pitch, so the
  differential pairs pass straight through without crossing. TMDS in/out
  pin pairs are tied inline on the PCB — the part sits *in* the line
  rather than beside it.

Lifecycle is **ACTIVE**.

> **Why the capacitance number mattered.** The earlier note here said an
> ESD clamp must be well under ~1 pF per channel or it loads the line.
> This part is **0.8 pF**, which is the reason it qualifies — a general
> purpose TVS array in the same footprint would not.

**DDC / EDID path — nothing reaches the FPGA:**
`connector → TPD12S521 → 0 Ω (DNP) → isolated pad → bodge wire → PMOD`

The companion chip already performs the level shift, so **the separate
shifter footprint is no longer needed.** The 0 Ω pads move to the chip's
**system-side** pins.

| qty | part | value | populate | why |
|---:|---|---|:-:|---|
| 4 | resistor | 0 Ω | **DNP** | series pads on `DDC_CLK_IN`, `DDC_DAT_IN`, `CE_REMOTE_IN`, `HOTPLUG_DET_IN` (pins 16–19); far side to an isolated pad |
| 2 | resistor | pull-ups, **3.3 V** system side | **DNP** | I²C still needs them; system side is `LV_SUPPLY`-referenced, so 3.3 V — the 5 V side is the chip's problem, not ours |
| 4 | pad / test point | — | — | bodge target for spare PMOD I/O |

**Connector, other pins:**

| pin | signal | populate | note |
|---:|---|:-:|---|
| 18 | `+5V` | **yes** | driven from the chip's `5V_OUT`, current-limited. Never reaches the FPGA |
| 19 | `HPD` | via chip | level-shifted by the chip; system side lands on a 0 Ω pad |
| 13/15/16 | `CEC`, `SCL`, `SDA` | **not routed to FPGA** | pass through the chip; system side to 0 Ω pads only |

**EDID itself is data, not a wire** — served from a small ROM,
supplyable upstream by the ESP32 over the same reset-exit vector that
carries the CMOS time base, `etc/e820` and the NE2000 MAC.

> **On keeping a path nobody expects to use.** In all likelihood none of
> the DNP parts above will ever be stuffed. They stay anyway. The cost is
> board area on a board that has it, and the alternative is deciding on
> someone else's behalf what they are allowed to do with hardware they
> own.
>
> Every other choice here can be revisited at a bench with an iron.
> **Leaving the pads off is the only one that cannot** — and a footprint
> costs a great deal less than being wrong about what somebody would
> eventually want.

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

### Open

- [x] **`+5V` (pin 18) — populate it.** The board has a 5 V rail, the pin
      is connector-only and never reaches the FPGA, and some sinks want it
      present before treating a source as connected. No reason to withhold
      it.
- [ ] **Confirm `HPD` (pin 19) is worth a 0 Ω pad**, given it is now the
      only way to know a display is attached at all. Cheap to leave in;
      the question is only whether anything would ever consume it.

---

## The video envelope — fixed

> **Requirement: FPGA speed grade ≥ -7.** Stated as a minimum rather than
> as whatever is in stock, because **`-6` does not meet it** — its
> GDDRX2 ceiling is 624 Mb/s against the 650 Mb/s that 1024×768 needs, so
> a grade down silently caps the machine at 800×600.
>
> | grade | GDDRX2 | ceiling |
> |---|---:|---|
> | `-6` | 624 Mb/s | **800×600 — does not meet spec** |
> | **`-7`** | **700** | **1024×768 — meets spec** |
> | `-8` | 800 | 1024×768 **plus 720p** |
>
> `LFE5U-85F-**7**BG381I` is what JLCPCB stocks, and it satisfies the
> requirement. A `-8` would raise the ceiling to include 720p and is
> acceptable wherever it can be had, but **nothing in the design depends
> on it.**

**The design ceiling is 1024×768 @60, 8 bpp**, and two independent limits
land on it:

| limit | ceiling |
|---|---|
| **serialiser**, `-7` GDDRX2 at 700 Mb/s | 1024×768 needs 650 Mb/s — **7% margin**; 720p needs 743 — **out of reach** |
| **video memory**, ganged PSRAM pair at ~60 MB/s | 1024×768×8 streams at 47.2 MB/s — **79% used** |

**That the two agree is worth noting.** Neither subsystem is grossly over-
or under-provisioned against the other, which suggests the sizing is
balanced rather than accidentally lopsided.

**The practical envelope:**

| mode | bpp | streamed | verdict |
|---|:-:|---:|---|
| 640×480 @60 | 8 | 18.4 MB/s | comfortable — 41 MB/s left for writes |
| 800×600 @60 | 8 | 28.8 | comfortable — any FPGA edge |
| 640×480 @60 | 16 | 36.9 | comfortable |
| **1024×768 @60** | **8** | **47.2** | **the ceiling — geared edge, 13 MB/s for writes** |
| 800×600 @60 | 16 | 57.6 | memory-limited, no write headroom |
| 1024×768 @60 | 16 | 94.4 | **exceeds memory** |

> **At the top mode, writes are the binding constraint, not scanout.**
> 13 MB/s against a 486's ~66 MB/s of back-to-back `STOSD` means a
> full-screen clear at 1024×768 takes ~62 ms, roughly four frames. Tolerable
> for a mode period software barely uses, and it is why **640×480 remains
> the mode the machine should feel fastest in.**

**Framebuffer fits comfortably:** 1024×768×8 is **768 KiB**, so the 2 MiB
allocation holds it **double-buffered** with room to spare.

**720p is not reachable and no part choice fixes it.** The `PTN3365`'s
3 Gbit/s does not help — the FPGA must still serialise 743 Mb/s and
cannot at `-7`. If a display demands 720p specifically, **scale into
1024×768 instead**; monitors generally accept it more readily than TVs
do.

### Deferred to silicon — resolution beyond the envelope

**Max resolution is not a prototype goal.** The spec is 1024×768 @60 at
8 bpp, guaranteed, and the prototype's job is to reach it — not to chase
the ceiling.

**The measurement order matters, and it runs the opposite way to the
design order.**

1. **Measure what the TMDS path actually tops out at** on real hardware.
   Lattice's grades are conservative, so the true ceiling likely sits
   above the 700 Mb/s guaranteed at `-7` — but by how much is a property
   of *this* board, not of a datasheet.
2. **Then size any compression to the gap that remains**, if one remains.

**Doing it the other way round would size a codec against a guess.** The
bandwidth shortfall is only knowable once the resolution ceiling is
measured, so building compression first risks solving a problem that
turns out not to exist — or solving the wrong size of it.

**The enabling decision has already been taken:** HDMI sits on a geared
edge, so the ceiling is explorable on the prototype rather than fixed at
500 Mb/s by placement. Nothing further is needed before the boards
arrive.

**Levers available when the time comes**, cheapest first:

| lever | effect | cost |
|---|---|---|
| **4 bpp** | halves traffic — 1024×768 to 23.6 MB/s | free, and period-correct (EGA/VGA planar) |
| **compression** on the write-combine flush | raises the *average*, not the guaranteed floor | fixed allocation + 1 bit/line; see [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md) |
| **third QSPI PSRAM** | raises the *guaranteed* floor to ~90 MB/s | 5 pins of the 10 spare |

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

- [ ] **Read the EDID of every display that matters — from a PC, as a
      bench measurement.** This is how the supported mode list gets
      chosen; it is not a product feature, and the board will not do this
      at runtime (see above). Established Timings I names 720×400@70 and
      640×480@60 explicitly. Costs nothing and may answer most of it.
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
