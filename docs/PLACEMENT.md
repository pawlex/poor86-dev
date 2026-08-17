# Pseudo-schematic and general placement

**General placement only.** Orientation and exact geometry are not fixed
here; what is fixed is which block connects to which FPGA edge, because
that is what determines routing difficulty and it is derivable now from
data rather than discovered during layout.

Derived from `Data/pinmap_*.csv` — see [BOARD.md](BOARD.md) for the
gates this feeds.

---

## Pin budget (gate G3)

Counted from the datasheet-derived CSVs, not estimated.

| block | pins |
|---|---:|
| CPU bus — Am5x86, decided set (G1) | **99** |
| SDRAM, 16-bit — **CPUCLK × 2** (66.67 MHz) — see breakdown below | 40 |
| ~~HyperRAM, narrow group~~ | ~~12~~ **dropped** |
| HDMI, 4 differential pairs | 8 |
| config EEPROM (bank 8, hard SPI) | 6 |
| **QSPI video memory** — 2× PSRAM, own data buses + own selects | **10** |
| **QSPI NOR** — own data bus + select | **5** |
| **common QSPI clock**, shared by all three devices | **1** |
| SD card, 4-bit | 6 |
| ESP32 link | 8 |
| Mezzanine transceiver control | 4 |
| Clocks (50 MHz osc on GPLL0), reset, config, misc | 8 |
| **total** | **195** |
| available, CABGA381 PIO | 205 |
| **spare** | **10** |

> **Memory pivot applied.** HyperRAM is dropped (−12); the video PSRAMs
> move to their own buses, separate from the NOR (+9 against the old
> shared 7). Net **−3**. The board lands at **195 of 205 with 10 spare
> *at full address width*** — so the `A24-A31` pin-saver is **no longer
> forced**, and remains available slack rather than a requirement.
>
> **The larger prize: there is no DDR interface anywhere on the board.**
> Memory and storage cost 56 pins against the 59 they cost before the
> pivot — essentially unchanged — but **every remaining interface is
> single data rate.** SDR SDRAM by name, QSPI PSRAM at 84 MHz SDR, and
> HyperRAM, the only DDR part, is gone. What that removes:
>
> - **Read calibration and delay-tap tuning.** DDR memories need the
>   capture point found at bring-up; an entire class of problems does not
>   arise.
> - **Strobe capture** — no `RWDS` or `DQS` to align against.
> - **Tight intra-lane length matching**, which DDR requires against its
>   strobe.
> - **Half-period setup windows.** At 84 MHz SDR the window is ~12 ns
>   rather than ~6 ns.
> - **The gearing requirement — and this one changes placement.** Every
>   remaining memory interface fits inside **1× gearing at well under
>   500 Mb/s per pin**, which is available on *every* bank, including the
>   ungeared top and bottom. **Memory is no longer confined to the geared
>   left and right edges.**
>
> **That relieves the HDMI conflict recorded above.** The problem was that
> video above 800×600 needs a geared edge, while PL and PR were spoken for
> by memory and the CPU bus. Memory no longer *needs* PL — it merely
> occupies it — so the geared edges can be reallocated by geometry rather
> than by capability. **The one hard constraint left on video placement is
> bank 8, which is reserved.**

> **Why the NOR is no longer on the same wires.** Video scanout is
> continuous and real-time. Sharing data lines with the NOR means a flash
> read can stall a scanout burst, which is a visible artifact rather than
> a latency figure. **One common clock is kept** — all three devices run
> at the same rate and ignore it while their select is inactive — so the
> separation costs data lines and selects, not a second clock domain.
>
> **Corrected.** This table previously read 190 with a 97-pin CPU bus.
> **Both figures were wrong:** the CPU set is 99 (see G1 below), and the
> old line items summed to 196 rather than the 190 stated — a six-pin
> arithmetic error that had been carried since the table was written.
> **The board is tighter than recorded: 7 spare, not 15.**

**With the `A24-A31` pin-saver** (CPU bus 91): **total 190, spare 15.**

### SDRAM group — signal breakdown

| signal | count |
|---|---:|
| `DQ[15:0]` | 16 |
| `A[12:0]` | 13 |
| `BA[1:0]` | 2 |
| `RAS#` `CAS#` `WE#` | 3 |
| `CS#` | 1 |
| `CKE` | 1 |
| `CLK` | 1 |
| `DQM[1:0]` | 2 |
| **total** | **39** — 1 spare of the 40 allocated |

**16 bits wide, and the bandwidth match at CPUCLK × 2 is exact rather
than approximate:**

```
SDRAM   16 bits × 66.67 MHz = 133.3 MB/s
CPU     32 bits × 33.33 MHz = 133.3 MB/s
```

A 32-bit CPU access is two SDRAM cycles at double rate — the same
wall-clock time, no clock-domain crossing, and the fixed integer phase
relationship the clocking section argues for. **16-bit at 2× and 32-bit
at 1× are the same memory; the 16-bit version costs 17 fewer pins.**
A 32-bit interface would need **57** and does not fit the budget anyway.

**Capacity: up to 64 MB.** 13 address plus 2 bank lines reach 512 Mb with
×16 parts — 8192 rows × 1024 columns × 4 banks × 16 bits. Well above
anything the machine needs; period 486s shipped 4–32 MB.

### 66 MHz is conservative — take the lowest CL

**The interface runs far below any SDR SDRAM speed grade.** PC133 parts
are specified at 7.5 ns; the period here is **15 ns**. That slack should
be spent on **latency, not margin**, since the plan of record makes CPU
latency the fixed constraint and bandwidth the free variable.

**Target `CL2`**, and every other timing at its minimum integer clock
count:

| timing | typical | clocks @15 ns |
|---|---|:-:|
| **`CL`** | — | **2** — 30 ns |
| `tRCD` | 15–20 ns | 2 |
| `tRP` | 15–20 ns | 2 |
| `tRAS` | 42–45 ns | 3 |

Which gives, against a 30 ns CPU cycle:

| access | clocks | time | CPU cycles |
|---|:-:|---:|:-:|
| **page hit** | `CL` = 2 | **30 ns** | **1** |
| page miss | `tRP` + `tRCD` + `CL` = 6 | 90 ns | 3 |

**A page-hit read costs one CPU cycle.** That is the number the cache
design should be built against, and it is only available because the
interface is run well inside its grade. `CL3` would make every read 50%
slower for no benefit — **the setting is a mode-register write, so this
costs nothing but remembering to do it.**

**G10 — carrying both HDMI front ends** costs 8 more balls, since the two
paths need separate pairs to keep the comparison clean:

| | total | spare |
|---|---:|---:|
| full address width + both paths | **206** | **−1 — does not fit** |
| pin-saver + both paths | 198 | 7 |

**So the validation vehicle's dual-HDMI experiment requires the
pin-saver.** That answers G10's "resources permitting" test on the I/O
side with a number rather than a judgement: it fits, but only at 16 MB.

**The CPU bus is 97 pins, not the ~76 assumed earlier** — that figure was
for a 386SX-class bus. The Am5x86 essential set is 30 address + 32 data
+ 35 control.

**And the full Am5x86 signal set does not fit.** Routing all 113 signals
— adding `DP0-3` parity, JTAG, and the deferrable control group
(`IGNNE`, `FERR`, `UP`, `STPCLK`, `SRESET`, `SMI`, `SMIACT`, `CLKMUL`) —
totals 206 against 205 available. It misses by one pin.

So a choice is forced, and it is cheap — and the schematic has already
made two of them:

- **JTAG is on a CH552T**, not the FPGA (`external_perif.kicad_sch`), so
  it was never in the budget.
- **A "pin saver option" is annotated on the FPGA and Am5x86 sheets**:
  dropping `A24-A31` reduces the address space to 16 MB and the CPU bus
  to **91 pins**, taking the total to **190 of 205 — 15 spare.** 16 MB is
  already the ceiling on the SX-class path, so this makes the two CPU
  variants agree rather than diverge.

Parity remains the other easy candidate; most chipsets do not implement
it.

### Decided: the signal set to carry (G1)

Verified against `Data/am5x86_Microprocessor_Family_Datasheet.pdf` and
`Data/pinmap_am5x86_sqfp208.csv`. **Direction matters** — an input needs a
defined level, an output may simply be left open.

**Cut — not routed to the FPGA (13 signals):**

| signal | n | disposition | why |
|---|:-:|---|---|
| `TCK` `TMS` `TDI` `TDO` | 4 | **tie `TMS`/`TDI` high, `TCK` low; `TDO` open** | unusable without BSDL. **Not floated** — there is no `TRST#` here, so the TAP is held reset by `TMS` high with `TCK` static. A floating TAP can enter a scan state and **drive the bus** |
| `DP0-3` | 4 | leave open | parity unimplemented, as in most period chipsets |
| `PCHK` | 1 | **leave open — it is an output** | nothing listens; the CPU does not trap on parity |
| `SMI` `SMIACT` | 2 | **`SMI` needs no strap — internal pull-up**; `SMIACT` is an output | see the SeaBIOS evidence below |
| `STPCLK` | 1 | tie inactive | stop-clock power management, not used |

**Straps on the board — inputs, so they need a defined level:**

| signal | n | why |
|---|:-:|---|
| `UP` | 1 | upgrade-present; no upgrade socket exists |
| `CLKMUL` | 1 | selects the multiplier — a build-time property of the CPU, not a chipset signal |

> **`PCD` and `PWT` cannot be strapped — they are outputs.** The
> datasheet is explicit: *"the CPU ignores the PCD bit and drives the PCD
> **output** Low"*, and the same for `PWT`. They reflect page-table
> attributes outward, so the only choices are **route** or **leave open**
> — and they are **routed**, per the table below.

**Kept, against the earlier suggestion to cut them:**

| signal | n | why kept |
|---|:-:|---|
| `BS8` `BS16` | 2 | retained by decision — dynamic bus sizing stays available even though the FPGA could width-convert internally |
| `BREQ` `BOFF` | 2 | retained; keeps genuine multi-master arbitration open rather than assuming a single master forever |
| `PLOCK` | 1 | output, retained |
| **`SRESET`** | 1 | **retained — the earlier cut was wrong.** It was filed with the SMM signals, but SMBASE is only one of five things it spares: *"unlike RESET, does not cause it to sample `UP` or `WB/WT`, or affect the FPU, cache, CD and NW bits in CR0, and SMBASE."* **`RESET` re-samples the configuration straps; `SRESET` does not** — so it is the chipset's lighter CPU-only reset, and it is the mechanism by which a warm reboot need not disturb cache mode or FPU state. Input with an **internal pull-down**, so it is inactive if left open — cheap either way, and cheaper to have |
| **`PCD` `PWT`** | 2 | **retained for L2 correctness.** They carry the page-table cacheability attributes outward, and an L2 that ignores them will cache pages the OS marked uncacheable — memory-mapped device windows, and a shared framebuffer if video ends up in main memory. That is a **correctness** failure, not a performance one, and it is invisible until something reads stale data. Feeds the policy open in [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md) |
| **`FERR` `IGNNE`** | 2 | **required for DOS.** The legacy x87 error path is `FERR#` → IRQ13 → BIOS handler → port `0xF0` → `IGNNE#`, which is the PC-compatible mechanism whenever `CR0.NE=0` — the DOS default. Cutting these breaks x87 exception handling on a machine built to run period software |

#### Evidence that `SMI` is safe to cut

**SeaBIOS cannot use SMM on this platform.** From the source at
`rel-1.17.0`: `smm_setup()` reaches only two implementations,
`piix4_apmc_smm_setup(int isabdf, int i440_bdf)` and
`ich9_lpc_apmc_smm_setup(int isabdf, int mch_bdf)`. Both take **PCI**
bus/device/function arguments and drive the chipset through
`pci_config_readl`/`pci_config_writeb`, against PIIX4/i440FX or ICH9/Q35
specifically.

**This machine has no PCI** — established independently with `-M isapc`.
There is no path by which SeaBIOS reaches SMM here, so the condition
*"cut unless SeaBIOS does or can use it"* resolves to **cut**.

#### Routing effort tiers — and layer 2 candidates

**Speculative**, from expected system behaviour rather than the
datasheet. It exists to say *where layout effort goes*, not to reclassify
any signal's requirements.

**The criterion is when a signal is sampled, not how often it moves** —
and the databook supplies it directly, by splitting inputs between two
timing specs:

| spec | meaning | routing class |
|---|---|---|
| **`t14`/`t15`** | synchronous; sampled every clock, in the command and termination window | **command bus clock domain — full care** |
| **`t20`/`t21`** | asynchronous; setup and hold needed only for *recognition* in some specific clock | relaxed |

| tier | signals | basis |
|---|---|---|
| **1 — asynchronous** | `A20M` `FLUSH` `FERR` `IGNNE` `SRESET` `NMI` `BREQ` `BOFF` **`RESET` `EADS`** | `t20`/`t21`, an output with no handshake role, an exception path, or a once-only event |
| 2 — low rate, synchronous | `INTR` `HOLD` `HLDA` `LOCK` `PLOCK` | alive, but not per-cycle |
| 3 — command / every cycle | `CLK`, `A2-A31`, `D0-D31`, `ADS` `RDY` `BRDY` `BLAST` `BE0-3` `M/IO` `D/C` `W/R` `CACHE` `KEN` `PCD` `PWT` `AHOLD` `INV` `BS8` `BS16` `WB/WT` `HITM` | full care |

> **Correction — `BS8`, `BS16`, `WB/WT`, `BOFF` and `HITM` are *not*
> candidates.** An earlier version of this section listed them as static
> and therefore relaxed. That reasoning was wrong: it sorted by
> transition frequency when the timing class is set by the sampling
> window.
>
> - **`BS8`/`BS16` are driven by the peripheral to say whether a second,
>   third or fourth bus cycle must occur.** The databook: *"sampled every
>   clock… every clock before RDY,"* to `t14`/`t15`. **They belong to the
>   command bus clock domain**, alongside `RDY` and `BRDY`, and carry that
>   window's timing whether or not they ever change state.
> - **`WB/WT`** is sampled *"on the same clock edge in which it finds
>   either RDY or the first BRDY"* — the same termination window.
> - **`HITM`** sits in the coherency handshake.
>
> **`BREQ` and `BOFF` are candidates, despite the neighbours they were
> first grouped with**, and for two different reasons:
>
> - **`BREQ` is an output.** The CPU imposes no setup or hold on it — the
>   receiver chooses how to sample. The FPGA can simply register it, and
>   `HOLD`/`HLDA` arbitration takes multiple clocks regardless, so a
>   cycle of extra latency costs nothing.
> - **`BOFF` is an exception mechanism, not a termination signal.** That
>   is the line between it and `BS8`/`BS16`: those participate in *every*
>   cycle's termination decision, so their inactive level is meaningful
>   data sampled every clock. `BOFF` only ever aborts, and in a
>   single-master design it never asserts at all.
>
> **A signal held at one level but sampled in a tight window still needs
> that window's routing quality.** Static is not the same as slow.

**Tier 1 is the candidate set for routing on internal layer 2, the VCC
plane** — six signals, all asynchronous. They qualify because an
asynchronous input recognised over a relaxed window **neither demands a
clean return path nor injects noise into the plane.**

> **The cost is not paid by these signals — it is paid by the plane and
> by whatever crosses it.** Routing in a plane layer carves slots, and:
>
> - **Any tier 3 signal on an adjacent layer crossing a slot loses its
>   return path**, which is the classic split-plane failure. **No
>   every-cycle signal may cross one of these channels.**
> - **Slots raise plane impedance** for current delivery. The Am5x86 at
>   3.45 V is not a small load, so channels should follow the plane
>   periphery or regions already free of copper, and stay short.
>
> Guidance, not permission: **loosely routed, not carelessly routed.**
> Tier 1 still has real setup and hold *when* it moves, `RESET`'s
> deassertion edge is the most timing-critical event on the board despite
> happening once, and `FLUSH` carries the tri-state-test hazard.

- [ ] **Gate this on the stackup decision** — layer count and impedance
      targets are still open in [BOARD.md](BOARD.md), and if layer 2 ends
      up adjacent to the top-layer CPU bus, carving it is a worse trade
      than it looks.

> **Six of the ten are unconditional** — asynchronous by
> specification, so no later decision about bus width, mastering or
> coherency can promote them into the command domain.
>
> **`BREQ`, `BOFF` and `EADS` carry conditions.** If real multi-master
> arbitration is added, `BOFF`'s assertion latency starts to matter and
> `BREQ` may be wanted promptly. If active snooping is adopted under the
> coherency policy still open in
> [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md), **`EADS` becomes a live
> per-snoop signal** and its pairing with `INV` stops being optional.
> None of the three becomes a *termination* signal, so these are latency
> and skew questions rather than correctness ones.

> **`RESET` qualifies on an enormous timing budget.** It moves once, and
> although its falling edge is the reference for latching `WB/WT`,
> `A20M`, `FLUSH` and the straps, those relationships are measured in
> **clock periods** — the part cannot execute until 1 ms after power and
> clock are stable. Layer-2 routing contributes a few hundred picoseconds
> against a 30 ns clock, which is noise.
>
> - [ ] **Put a test point on `RESET`.** Burying the one signal you most
>       want to scope during bring-up is a practical cost, not an
>       electrical one, and a via and a pad fix it.
>
> **`EADS` qualifies, but is the weakest of the ten — and it must not
> travel alone.** It is a snoop-protocol signal: *"INV is sampled in the
> same clock period that EADS is asserted,"* and it may assert every
> other clock while a hold is active. **What matters is not its absolute
> delay but its skew against `INV` and the address bus.**
>
> - [ ] **If `EADS` goes on layer 2, `INV` goes with it.** Their
>       relationship is same-clock, so routing them together preserves it
>       while splitting them across layers is what would break it. `INV`
>       is otherwise a tier 3 signal and belongs there **unless it is
>       paired here.**
>
> **Condition on all ten: they must be actively driven, not
> resistor-pulled.** A line held static by a low-impedance driver is very
> hard to glitch; a weakly-pulled line in a plane channel is not. Since
> the risk of relaxed routing here is coupling rather than delay — these
> signals mostly do not move — **drive strength is what makes the
> placement safe**, and an input left to an internal pull-up is the one
> case that should stay off layer 2.

#### Where it lands

| set | signals |
|---|---:|
| full Am5x86 | 113 |
| cuts above | −12 |
| straps (`UP`, `CLKMUL`) | −2 |
| **routed to the FPGA** | **99** |
| with the `A24-A31` pin-saver | **91** |

Composition check: 30 address + 32 data + 37 control = 99, the 37 being
the 43 control signals less `PCHK`, `SMI`, `SMIACT`, `STPCLK` (cut) and
`UP`, `CLKMUL` (strapped). **`PCD`, `PWT` and `SRESET` are inside that
37.**

> **Invariant worth holding: no routed signal is reset-only.** All 99
> have runtime function. The only pins the Am5x86 samples at reset and
> then ignores are **`CLKMUL` and `UP`, and both are straps** — so no FPGA
> ball is spent on a value read once.
>
> Two things follow. Any future addition that is *only* read at reset
> belongs on a strap, not a ball. And the FPGA never drives anything
> solely for reset: the reset-time obligations (`WB/WT` level, `A20M`
> high, `FLUSH` high) all sit on pins it owns for runtime reasons, so
> gating CPU `RESET` on `DONE` is a matter of correct defaults rather than
> a separate configuration group.
>
> **`WB/WT` is not reset-only**, despite selecting the cache mode there:
> *"all subsequent cache line fills sample WB/WT"* with `RDY` or the first
> `BRDY`, setting **per-line** write policy. It is a live coherency signal,
> and its weak internal pull-down defaults to write-through if undriven.

> **Why `RESET` alone is not sufficient.** A full `RESET` re-samples
> `UP` and `WB/WT`, which means it re-latches the cache mode. That
> interacts directly with the coherency policy open in
> [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md): if `WB/WT` is ever driven by
> the chipset rather than statically strapped, **`RESET` becomes the
> instrument that changes cache mode and `SRESET` the one that does
> not.** Losing that distinction would have cost a capability for one
> pin.

---

## FPGA edge allocation

The CABGA381 has 205 PIO balls, distributed very unevenly:

| die edge | balls | A/B differential pairs |
|---|---:|---:|
| PT (top) | 60 | 29 |
| PL (left) | 65 | 16 |
| PR (right) | 67 | 17 |
| PB (bottom) | **13** | 6 |

**A 97-pin CPU bus fits on no single edge.** Only two adjacent pairs are
large enough — PT+PR (127) or PT+LEFT (125) — so **the CPU sits at a
corner of the package**, not centred on a face. That is the single most
consequential placement fact available today.

| FPGA edge | allocated | pins | why |
|---|---|---:|---|
| **PT + PR** | CPU bus | 97 of 127 | only adjacent pair large enough |
| **PL** | SDRAM | 40 of 65 | main memory on one face, opposite the CPU |
| **PB** | **configuration EEPROM only** | 6 of 13 | bank 8 *is* the configuration bank — see below |
| leftovers | HDMI, ESP32, SD, transceiver control, clocks | ~34 of ~49 | distributed into PT/PR/PL slack |

### PB is the configuration bank — and is now formally reserved

**Bank 8 is reserved for configuration and DFx only**, recorded in
[PLAN_OF_RECORD.md](PLAN_OF_RECORD.md). Anything else there requires a
waiver.

All 13 balls of bank 8 carry configuration functions:

```
D0-D7 / IO0-IO7      SPI flash data
MOSI, MISO, MOSI2, MISO2
CSSPIN, CSON, CS1N, SN/CSN
HOLDN/DI/BUSY/CEN, DOUT, WRITEN
```

This is the interface the ECP5 boots through, so the **SPI NOR flash
belongs here and nothing else can have it.** It also happens to be
exactly where the QSPI PSRAM goes, since that part shares the flash bus
by design — so bank 8 hosts both, and the "one extra chip select" costs
one of its spare balls.

**HDMI therefore does not go on PB.** It takes 8 balls from the slack on
whichever of PT/PR/PL faces the rear panel.

### HDMI needs differential pairs, not true LVDS

**Fake TMDS does not require true LVDS. The restriction is on
differential pairs.**

So the constraint is not which banks support LVDS output — it is whether
adjacent **A/B PIO pair sites** are available, since the two halves of
each pair must be matched or skew destroys the signal at these rates.

HDMI needs **4 pairs** (3 data, 1 clock). Pair sites by edge:

| edge | A/B pair sites | enough for HDMI |
|---|---:|---|
| PT | 29 | yes |
| PR | 17 | yes |
| PL | 16 | yes |
| PB | 6 | **reserved — bank 8** |

Every usable edge has ample pairs. Bank 8 is excluded because it is
reserved for configuration and DFx, not because of its pair count.

> **Correction — pair count is not the binding constraint.** This
> previously read *"HDMI placement is free among PT/PL/PR"*. That is
> wrong. Emulated differential output is available on every bank, but the
> **output gearing is on the left and right sides only** — the top side
> supports 1x gearing only, which caps it at **500 Mb/s**, or 800×600.
> 1024×768 needs a geared edge and a -7 part; 720p needs a geared edge and
> a -8 part. See [FAKE_TMDS.md](FAKE_TMDS.md) for the datasheet quotes and
> the mode table. **HDMI on PT is a permanent 800×600 ceiling**, which is
> a board-spin decision rather than a bitstream one.

**No VCCIO constraint either: every VCCIO rail is 3.3 V.** With a single
I/O voltage across the device there is no bank-sharing conflict to
resolve, so HDMI, the CPU bus and the memory groups can be assigned by
geometry alone.

---

## Board floorplan

![placement](placement.svg)

*(ASCII version below, for diffing.)*

Relative placement only. Rear I/O at the top. The FPGA is oriented with
**PT toward the rear** (so HDMI has a short run to its connector), **PB
downward** toward the SPI flash it must serve, **PL** facing the memory
and **PR** facing the CPU.

```
        +==================== 170 mm =====================+
        |  [DC in]      [USB]        [HDMI]   REAR I/O    |
        |      |          |             |                 |
        |   power      ESP32            | HDMI: 8 from    |
        |   section                     | PT slack        |
        |                          +----+----+            |
        |    SDRAM  ---------------|   (PT)  |            |
        |                          |         |    Am5x86  |
        |                          | (PL)ECP5|  +-------+ |
   170  |                          |    (PR) |--| SQFP  | |
   mm   |         memory: 52 pins  |         |  |  208  | |
        |         on PL            |   (PB)  |  +-------+ |
        |                          +----+----+   CPU bus  |
        |                               |        97 pins  |
        |                    SPI NOR + QSPI PSRAM         |
        |                    (bank 8 = config bank)       |
        |                                                 |
        |    SD                                           |
        |                                                 |
        |   ========== MEZZANINE CONNECTOR ==========     |
        |     386SX bus, 3.3 V + 4 xcvr-control lines   |
        +=================================================+
            daughterboard: transceivers + level translation
                           CL-GD5428 + own DRAM + VGA
```

### Rationale

- **CPU at the FPGA's PT/PR corner.** Forced — no single edge holds 97
  pins. The CPU package sits diagonally off that corner so both edges
  face it.
- **SDRAM on PL**, the opposite face, keeping the two widest buses on
  opposite sides of the FPGA so they do not cross. **The narrow memory
  group is gone** — video memory is the QSPI pair, near bank 8.
- **SPI NOR and QSPI PSRAM on PB**, because bank 8 is the configuration
  bank and the FPGA boots through it. Not a placement choice — a
  constraint.
- **HDMI from the slack on whichever big edge faces the rear panel**,
  preferring adjacent A/B pair sites for skew.
- **Mezzanine at the board edge.** The transceivers are on the
  daughterboard, so the baseboard passes the raw bus to the connector and
  keeps a single 3.3 V domain.
- **ESP32 near the rear** for antenna keep-out, away from the CPU bus.
- **SD wherever slack allows** — few pins, latency-insensitive.
- **The CPU on the side away from the rear panel**, which keeps the
  hottest part clear of the connector stack and puts it next to the
  mezzanine it shares a bus with.

---

## Open

- [ ] **Which of PT+PR or PT+PL carries the CPU.** Both fit. The choice
      is decided by where the CPU can physically sit given the rear I/O
      and the mezzanine, not by ball count.
- [x] **HDMI goes on a geared edge — PL or PR. Decided.**

      **The asymmetry decides it.** PT offers only 1× gearing, a hard
      **500 Mb/s** ceiling — 800×600 and no further, **permanently, as a
      board property.** PL and PR offer GDDRX2 at **700 Mb/s guaranteed**
      at `-7`, which carries 1024×768.

      **It costs nothing now.** Dropping DDR memory freed the geared
      edges; SDRAM occupies PL but no longer *needs* it, so 8 balls for
      video are available there.

      **And it preserves an option worth having.** Lattice's grades are
      demonstrably conservative — the ULX3S runs 720p at ~19% over its
      `-6` GDDRX2 spec. **Nothing in this design depends on exceeding
      700 Mb/s**, and it should not; but on a geared edge the ceiling can
      be *explored on real hardware*, where on PT it cannot be explored at
      all. **Wrong choice here is a respin; right choice is free.**

- [ ] **Preserve 4 adjacent A/B pair sites on the chosen edge.** PL has 16
      pair sites and SDRAM takes 40 of its 65 balls, so the memory
      allocation must be made **without fragmenting four contiguous
      pairs.** This is the one way the decision above can be lost by
      accident during pin assignment.
- [ ] **Speed grade of the LFE5U-85F**, which is recorded nowhere and now
      has a video consequence: -6 tops out at 800×600, -7 at 1024×768, -8
      at 720p.
- [ ] **Bank VCCIO grouping** against the 3.3 V CPU bus and the video
      pairs — banks sharing a VCCIO rail must share a voltage.
      `Data/pinmap_ecp5_cabga381_power.csv` has the rails.
- [ ] **Which 8 signals are dropped** to bring the full Am5x86 set inside
      205, if more than the essential 97 are wanted.
- [ ] Whether video gets its own memory channel — would add a narrow
      group and eat most of the 15 spare pins.
- [ ] SX-class variant: its bus is ~57 pins rather than 97, so the same
      allocation holds with slack. No separate floorplan needed.
