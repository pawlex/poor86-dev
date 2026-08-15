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
| CPU bus — Am5x86, essential set | **97** |
| SDRAM, wide group | 40 |
| HyperRAM, narrow group | 12 |
| HDMI, 4 differential pairs | 8 |
| SPI NOR + QSPI PSRAM chip select | 7 |
| SD card, 4-bit | 6 |
| ESP32 link | 8 |
| Mezzanine transceiver control | 4 |
| Clocks, reset, config, misc | 8 |
| **total** | **190** |
| available, CABGA381 PIO | 205 |
| **spare** | **15** |

**The CPU bus is 97 pins, not the ~76 assumed earlier** — that figure was
for a 386SX-class bus. The Am5x86 essential set is 30 address + 32 data
+ 35 control.

**And the full Am5x86 signal set does not fit.** Routing all 113 signals
— adding `DP0-3` parity, JTAG, and the deferrable control group
(`IGNNE`, `FERR`, `UP`, `STPCLK`, `SRESET`, `SMI`, `SMIACT`, `CLKMUL`) —
totals 206 against 205 available. It misses by one pin.

So a choice is forced, and it is cheap: parity is unused by most
chipsets, JTAG belongs on a header rather than the FPGA, and several of
the deferrable signals can be strapped rather than driven. Any one of
those recovers the margin.

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
| **PL** | SDRAM + HyperRAM | 52 of 65 | both memories on one edge, one face of the FPGA |
| **PB** | **SPI NOR + QSPI PSRAM** | 7 of 13 | bank 8 *is* the configuration bank — see below |
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

### HDMI does not need true LVDS

Worth stating, because it widens where HDMI can live. The fake-TMDS
approach drives the pairs as **antiphase LVCMOS33**, not true LVDS, so
designated LVDS-output sites are not required and HDMI is not restricted
to particular banks.

Adjacent **A/B PIO pair sites** are still preferable — they are laid out
as pairs inside the package, which helps skew — but they are a
preference, not a constraint. Pair-site counts by edge: PT 29, PR 17,
PL 16, PB 6.

---

## Board floorplan

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
        |    HyperRAM -------------| (PL)ECP5|  +-------+ |
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
        |   [bus transceivers]                            |
        |   ========== MEZZANINE CONNECTOR ==========     |
        |              486 bus, level translated          |
        +=================================================+
                   daughterboard: CL-GD5428 + own DRAM + VGA
```

### Rationale

- **CPU at the FPGA's PT/PR corner.** Forced — no single edge holds 97
  pins. The CPU package sits diagonally off that corner so both edges
  face it.
- **Memory on PL**, the opposite face, keeping the two widest buses on
  opposite sides of the FPGA so they do not cross.
- **SPI NOR and QSPI PSRAM on PB**, because bank 8 is the configuration
  bank and the FPGA boots through it. Not a placement choice — a
  constraint.
- **HDMI from the slack on whichever big edge faces the rear panel**,
  preferring adjacent A/B pair sites for skew.
- **Mezzanine at the board edge**, behind transceivers, so a daughterboard
  can overhang without fouling anything and the stubs stay short.
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
- [ ] **Which edge carries HDMI**, decided by where the rear panel is
      once the FPGA rotation is chosen. 8 balls from slack, preferring
      adjacent A/B pair sites.
- [ ] **Bank VCCIO grouping** against the 3.3 V CPU bus and the video
      pairs — banks sharing a VCCIO rail must share a voltage.
      `Data/pinmap_ecp5_cabga381_power.csv` has the rails.
- [ ] **Which 8 signals are dropped** to bring the full Am5x86 set inside
      205, if more than the essential 97 are wanted.
- [ ] Whether video gets its own memory channel — would add a narrow
      group and eat most of the 15 spare pins.
- [ ] SX-class variant: its bus is ~57 pins rather than 97, so the same
      allocation holds with slack. No separate floorplan needed.
