# Concept C — a behavioural sketch of the BIU and memory subsystem

## What this is, and what it is not

**Concept C**, matching option **C** in the cacheability and coherency
list in [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md): *selective cacheability plus
snooping* — the fastest and hardest of the three. The sketch implements
that shape, with a snoop interface, region-based cacheability decode,
and a write-back cache with dirty bits.

**These are concepts, not design requirements.** A late-night idea
captured as behaviour so it could be understood later. Nothing more.
Nothing here is proposed, selected, or committed to, and the machine may
well end up on option A or B instead — both of which make the coherency
problem largely disappear.

They have not been simulated, synthesised or elaborated. Everything
below comes from **reading the source**, so it is analysis rather than
measurement — where a finding would change the design, the way to
confirm it is stated alongside.

Recorded as-is, defects included. The value of a captured concept is
that it can be reasoned about later; editing it into something tidier
would lose what it actually said.

## Premise

The reasoning the concept was built on, recorded because the code only
makes sense against it:

1. **Cheap serial PSRAM now exists in very small packages.** Low pin
   count — which is what makes the package small and the FPGA I/O budget
   survivable — low cost, useful density.
2. **Used correctly, it performs well — and "correctly" means
   bursting.** These parts are not designed for random single-word
   access.
3. **Bursting means latency.** There is a fixed cost to opening a
   transfer before any data appears.
4. **Latency kills a 386 or 486.** They are latency-bound machines, and
   the four-word burst ceiling gives almost no window to amortise a long
   setup (see [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md)).
5. **So: always run the far memory in burst mode.** Accept that changing
   context costs a lot of latency, because once data starts arriving it
   arrives quickly.
6. **And use that stream to fill L2**, the chipset cache, which is what
   the CPU actually sees. The far memory's latency is paid on a miss;
   the CPU's accesses are served from the cache at cache speed.

### The solution the concept proposes

Two structures, each answering a different half of the latency problem:

- **A fast L2 in the chipset** — N-way set-associative, BRAM-backed —
  **to absorb the initial latency hit.** Once a line is resident the CPU
  never sees the far memory's setup cost at all.
- **A stream pool in the LLC**, to **alleviate
  the warm-up penalty when the CPU switches context.** A cache that is
  merely fast does nothing for a cold working set; every miss after a
  context switch pays full latency again. Keeping several streams alive
  means a newly-scheduled working set can already have data in flight
  rather than starting from nothing.

The concept is therefore not "make the memory fast". It is **make the
memory's one strength — sustained streaming — the only thing the CPU
ever depends on**, and hide everything else: the steady state behind the
cache, and the transitions behind the stream pool.

**That maps onto the sketch directly.** Its two structures are those two
ideas:

| sketch structure | premise role |
|---|---|
| 4-way set-associative BRAM cache | the fast cache absorbing initial latency |
| 3-entry stream buffer | the LLC stream pool covering context-switch warm-up |

Three streams is a defensible number for that job — roughly code, data
and stack, or two working sets plus an interrupt handler.

### A third thing it solves: CPU-variant independence

Not obvious from the code, and arguably its strongest property.

**The BIU and the cache controller are both inside the FPGA, with no
external wiring between them.** That interface is not a board-level
concern at all — it has no pin cost, no signal-integrity budget, no
routing, and changing it is a bitstream change rather than a PCB
respin.

The consequence: **the far memory is abstracted far enough away that its
width stops mattering at the CPU bus level.** The cache is the boundary.
Its CPU-side port faces whichever processor is fitted; its fill path
faces whichever memory is fitted; neither side needs to know about the
other.

So **one board can carry both CPU variants** — the 486DX4 with its
32-bit bursting cached bus, and the simpler SX-class part — against the
same BOM, differing only in a bitstream.

Contrast M8SBC-486, where SRAM sits directly on the CPU bus: there the
memory's width *is* the CPU's width, and supporting two CPU widths would
mean different memory wiring on the board. **Paying the pins to route
the data bus through the FPGA buys two things, not one** — the
associativity recorded in [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md), and this
decoupling.

Stated precisely: it is **the DRAM's width that is invisible at the bus
level.** Whatever the far memory turns out to be — 8-bit serial, 16-bit,
one device or several — the CPU never sees it, because the cache's fill
path absorbs it entirely. The far memory can be re-chosen without
touching the CPU-side design.

The CPU side does still differ between variants: a 16- versus 32-bit
data path, and the SX's 24-bit address shrinking the tag. Those are
**parameters of a shared design** rather than a second design, which is
the distinction that matters for cost.

### And channels are nearly free, which leaves an upgrade path

The same abstraction makes **memory channels cheap to add**, because a
serial part costs only a handful of pins per channel. Two consequences,
and the second is a product feature rather than an engineering one:

- **A second channel can be planned on the PCB at effectively zero
  cost.** Unpopulated footprints add nothing to the BOM, and the
  packages are small enough not to trouble a 170 mm board. The pins are
  the only real commitment, and there are few of them.
- **That is an upgrade path for the customer** — the same board shipping
  in more than one configuration, and a populated-later option, rather
  than a new board.

It is also worth noting what a second channel buys beyond capacity:
**bandwidth that can be dedicated.** The framebuffer and the CPU want
opposite things from memory — sustained sequential streaming against
small latency-sensitive accesses — and on a shared channel they contend.
Two channels allow scanout and CPU traffic to be separated outright,
which is a cleaner answer to that contention than arbitration is.

- [ ] Decide the channel count the PCB plans for, even if only one is
      populated initially. This is a pin-assignment decision, so it has
      to be made before layout freezes — the one item here that cannot
      be deferred to a bitstream.

### Nomenclature: corrected to canon

The premise as dictated called the chipset's BRAM cache **"L1"**. Under
the canonical definitions in [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md) that is
**L2**, and this document uses the canonical terms throughout:

| structure | canonical level |
|---|---|
| CPU's on-die cache (16 KiB write-back on an Am5x86; absent on a plain SX) | **L1** |
| the chipset's N-way set-associative BRAM cache — Concept C's "fast cache" | **L2** |
| the structure fronting far memory — the **stream buffer** | **last level cache (LLC)**, *not* L3 |

Worth noting the **source was already right**: the sketch's signals are
`l2_data_mem`, `l2_tag_mem`, `l2_valid`, `l2_dirty`. It was the spoken
premise that drifted, not the code.

**Resolved: Concept C has no L3.** Canon reserves L3 for an *external*
cache, and this structure is inside the FPGA — so calling it L3 was
wrong.

**The canonical term is the last level cache (LLC); "stream buffer" is
Concept C's implementation of that role.** The two are not synonyms and
the distinction is deliberate: **LLC describes a position in the
hierarchy, stream buffer describes a mechanism.** With several designs
alive, a positional name survives a change of design where a mechanism
name does not — drop Concept C for an external direct-mapped cache and
"LLC" still applies, while "stream buffer" becomes false. Use LLC in
architecture text, stream buffer only when describing how Concept C
fills it.

That is the same failure that produced the L1 collision above: a term
describing one specific thing got used as a general one.

The hierarchy in Concept C is therefore:

```
  L1   CPU on-die            (may not exist)
  L2   chipset, N-way, BRAM
  LLC  stream buffer, BRAM   <- last level before far memory
  ---- far memory: serial PSRAM
```

It is still a genuine level rather than a fill mechanism — it is
tag-checked and can satisfy a CPU request directly (`stream_hit`) — so
it needs its own hit/miss accounting and replacement policy. It simply
is not L3.

### Concept C deliberately contradicts the parallel-SRAM conclusion

Worth stating plainly, because both positions are now recorded and they
disagree.

[PLAN_OF_RECORD.md](PLAN_OF_RECORD.md) argues from the **four-word burst ceiling**
that a 486 can never amortise a long setup cost, so **low latency beats
high bandwidth** — which points at parallel SRAM and away from
serial parts. M8SBC-486 independently used parallel SRAM.

**Concept C takes the opposite route.** It accepts a high-latency serial
part and argues the CPU should simply never see that latency: the cache
absorbs it in steady state, the stream pool covers the transitions.
Cheap, few pins, small package — *provided the hiding works*.

These are not reconcilable by argument, and the difference between them
is a number:

- **If the chipset cache's hit rate is high enough**, the far memory's
  latency is paid rarely and Concept C's economics win — fewer pins,
  cheaper part, smaller footprint.
- **If it is not**, the four-word ceiling dominates, every miss is
  exposed, and the parallel part is the right answer despite costing
  pins.

So the disagreement is **empirically settleable**, and by the method
already sketched elsewhere: run a real workload, measure miss rate and
miss cost. That is exactly what ao486 was noted as useful for — a real
486 core generating realistic traffic at transaction level, which is the
right layer for this question.

- [ ] Measure it before choosing. The two positions in this repository
      cannot both be right, and a hit-rate figure decides which.

---

| file | module | role |
|---|---|---|
| [`../rtl/i486_biu.sv`](../rtl/i486_biu.sv) | `i486_biu` | CPU-side bus interface, region decode, posted write buffer, cache/system routing |
| [`../rtl/ecp5_cache_subsystem.sv`](../rtl/ecp5_cache_subsystem.sv) | `ecp5_cache_subsystem` | 4-way set-associative cache, 3-stream prefetch buffer, serial PSRAM interface |

Original filenames were `Poor86-dev.i486DX4_BIU_Interface.sv` and
`Poor86-dev.L2Controller_sPSRAM_StreamBuffere.sv`; renamed to match the
module names inside them.

---

## The structural finding: the arrays are unlikely to infer as BRAM

**Assumed, not yet measured — and worth confirming early, because it
changes the module rather than the code.**

The source comments state that yosys will infer `DP16KD` blocks for the
cache arrays. The expectation here is that it will not, and that the
storage lands in LUT-based distributed RAM instead.

The reason is the hit path:

```systemverilog
for (int w = 0; w < WAYS; w++)
    if (l2_valid[w][index] && (l2_tag_mem[w][index] == tag)) begin
        hit_data = l2_data_mem[w][index];      // async read, all four ways
```

That is an **asynchronous** read of all four ways inside `always_comb`.
**ECP5 EBR is synchronous-read.** An async read cannot map to it and
falls back to distributed RAM — which is exactly the `altdpram` problem
already documented in
[ao486-cpu-oss](https://github.com/pawlex/ao486-cpu-oss), where
async-read arrays could not use EBR and were charged against the LUT
budget instead.

If that holds, the data array does not land in block RAM at all, and the
reason for keeping it on-chip (see the cache decision in
[PLAN_OF_RECORD.md](PLAN_OF_RECORD.md)) is defeated.

**Confirming it costs one command:** synthesise the module alone with
`synth_ecp5` and read the cell counts. `DP16KD` near zero with a large
`TRELLIS_DPR16X4` and LUT4 count confirms it; a `DP16KD` count in the
tens refutes it.

**The fix, if confirmed, is structural:** split the ways into separate
memories, register the index, and pipeline the lookup — cycle 1 reads
tag and data synchronously, cycle 2 compares tags and selects the way.
That costs one cycle of hit latency and buys EBR inference plus a much
shorter critical path. It changes the module's timing contract with the
BIU, which is why it is better settled now than after the surrounding
logic is written.

---

## Correctness defects — cache

Ordered by consequence.

- **Dirty lines are silently discarded.** The `EVICT` state is declared
  but never entered, and `l2_dirty` is set but never acted upon. On a
  miss the victim way is overwritten unconditionally. With a write-back
  policy that is data loss, not a performance issue.
- **Write misses lose the write.** On a write miss the line is fetched,
  allocated, and marked dirty — but `cpu_wdata` is never merged into the
  fetched line. The write disappears and the line is marked dirty
  anyway, so the wrong data is later written back.
- **The replacement policy evicts the most recently used way.**
  `l2_plru[index] <= hit_way` records the way just used, and
  `victim_way` then selects that same value. It is also not a tree
  pseudo-LRU — it is "remember the last way", which for four ways gives
  poor replacement even once the inversion is fixed.
- **A miss can return the wrong line.**
  `psram_addr <= {cpu_addr[31:6], 6'h0}` requests a 64-byte-aligned
  block, but a single 16-byte line is returned and used to satisfy the
  request. Unless `cpu_addr[5:4] == 0` that is not the line the CPU
  asked for.
- **No byte enables.** The BIU produces `cache_be`; the cache has no
  corresponding port and writes full 32-bit words. x86 byte and word
  writes are common, and would corrupt neighbouring bytes.

### The stream buffer is internally inconsistent

- `stream_tag` is `cpu_addr[31:6]` — 64-byte granularity — while the
  buffer is 16 lines of 16 bytes (256 bytes), and the comment describes
  it as 256 bytes per stream. The tag covers a quarter of the buffer.
- The index `cpu_addr[5:4] + stream_head[s]` adds a 2-bit value to a
  4-bit one with no masking.
- Only one line is ever written (`stream_mem[stream_lro][0]`), so any
  hit at a non-zero offset reads uninitialised entries.
- Nothing fills a stream: there is no counter or loop, and the PSRAM
  interface delivers one line per handshake. As written the prefetcher
  never prefetches.

---

## Correctness defects — BIU

- **`core_ready` is driven from two always blocks** — cleared in
  `always_comb` (line 102) and set in `always_ff` (line 178). This will
  not elaborate.
- **Posted-write hazard.** A read is issued to cache or system while a
  write to the same address may still be sitting in the write buffer,
  so the CPU can read stale data. Store-to-load forwarding, or a
  drain-before-read interlock, is the main thing a posted write buffer
  has to provide — otherwise it is not safe to post at all.
- **Write-buffer drain is not atomic.** The drain is issued only while
  `!core_req` and is abandoned as soon as a new request arrives, without
  tracking whether the transaction completed.
- **`snoop_hit_out` never consults tags.** It is `snoop_req` delayed one
  cycle. As an unconditional invalidate pulse that is conservative and
  workable; as something named "hit" it is misleading.
- **Wait states do not latch the transaction.** In `BIU_CACHE_WAIT` and
  `BIU_SYS_WAIT` the address and write data are still taken combinatorially
  from `core_*` rather than from a latched copy.
- **Naming:** `core_ready` is described as a `BRDY#` equivalent, but
  there is no burst anywhere — no `BLAST#`, no four-transfer sequencing.
  It is `RDY#`. That is consistent with the decision to defer burst
  support, and the comment should say so rather than implying burst.

---

## The two modules do not connect as written

| BIU port | cache port | issue |
|---|---|---|
| `cache_be[3:0]` | — | no counterpart; byte enables are dropped |
| `cache_ready` | `cpu_done` | name differs, and `cpu_done` is a **pulse** while the BIU consumes it as a **level** |
| `cache_req/write/addr/wdata/rdata` | `cpu_req/write/addr/wdata/rdata` | naming only |

The pulse-versus-level mismatch is the substantive one: the BIU samples
`cache_ready` combinationally in `BIU_IDLE`, and a one-cycle pulse can
be missed or double-counted depending on when the state machine looks.

---

## Sizing: 16 KiB is the one size that cannot pay

`SETS=256 × WAYS=4 × 16 B` = **16 KiB total**.

The Am5x86 has a **16 KiB write-back L1**. A second-level cache the same
size as the first captures very little the L1 did not already hold — it
is close to the only capacity that reliably fails to earn its area.

The budget recorded in [PLAN_OF_RECORD.md](PLAN_OF_RECORD.md) puts 128 KiB at ~57
EBR and 256 KiB at ~114 of 208 available, both comfortable on the
hard-CPU path where no soft x86 core is instantiated. If 256 sets was a
placeholder it is worth moving early, since sets, ways and line size all
feed the address parsing and the tag width.

---

## What Concept C would require, if it were ever pursued

Not a work plan. This is what would have to be true for this shape to
become a design, which is also a fair measure of what option **C** costs
against **A** and **B**.

- [ ] Synthesise `ecp5_cache_subsystem` alone and read the `DP16KD`
      count. This decides whether the pipelined restructure is needed,
      and it is the cheapest question to answer.
- [ ] Fix the capacity, since it changes the address parsing.
- [ ] Decide the hit latency contract — single-cycle combinational, or
      pipelined with registered tag compare. The BIU's handshake depends
      on it.
- [ ] Add eviction and write-allocate merge, or state explicitly that
      the cache is write-through and drop `l2_dirty`.
- [ ] Settle byte enables end to end, from `core_be` through to the data
      array.
- [ ] Build the stream pool to match its stated purpose. It is the least
      developed part of the sketch — as written it holds one line and
      never fills — but its **intent is now clear**: covering
      context-switch warm-up rather than steady-state throughput. That
      is a testable claim, and the co-simulation could measure it
      directly by comparing miss behaviour across a context switch with
      and without the pool.

Note that several of these are the same decisions listed as open in
[PLAN_OF_RECORD.md](PLAN_OF_RECORD.md) — cacheability policy, write policy,
snooping — now reached from the implementation side rather than the
architectural one. That convergence is the useful part of the sketch,
more than the code itself.
