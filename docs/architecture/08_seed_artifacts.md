# Koivu Seed Artifacts

**Status:** Architecture Blueprint

**Component:** Global

This document defines what a Koivu release publishes, what each artifact is derived from, where it is stored, what verification it admits and what it does not prove. It is the shared reference for [Platforms and Targets](01_platforms.md), [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), [Stage 1 (Seed)](04_stage1_seed.md) and [Koivu Vesi](koivu-vesi.md).

The document keeps the name it has always had, although its scope is now the published set as a whole rather than the seed alone: the links that point at it are numerous, and a name is cheaper to explain than to change.

---

## 1. One Binary, One Image, and Source

The chain needs exactly one machine binary from outside, and it is not the seed. It is **Vesi**, the Pino lowerer.

That is a consequence of the split described in [Koivu Vesi](koivu-vesi.md), section 1. A front end writes a target-independent `.pino` image; Vesi turns an image into an executable for a target. So:

* **The seed is published as an image**, `koivu-seed.pino`, and never as a binary. The user lowers it themselves with the Vesi they have just checked, which means no seed binary is distributed and nothing about the seed's machine code has to be taken on faith.
* **Vesi is published as a binary**, one per host, with its assembly committed beside it, because it is the one program the user cannot derive from anything else.
* **The sapling is not published at all.** It is scaffolding: its `.scm` source is in the repository, and the user builds it with the seed. There is no third artifact and no gap where one would go.

The trusted artifact is therefore the *smaller* of the two programs. The seed keeps the front end - roughly 78% of the old single compiler - while Vesi is roughly 60% of it ([Koivu Vesi](koivu-vesi.md), section 5). Under the previous arrangement the user had to trust the larger half; now they trust the smaller half and lower the larger one themselves.

Two further properties follow, and both are gains rather than side effects:

* **The seed's image is published once, not per host.** An image carries no target information ([Koivu Vesi](koivu-vesi.md), section 2), so one file serves every platform, and only Vesi is published per host.
* **The seed's assembly is not published**, because the user renders it with the same Vesi they are checking: `koivu-vesi --emit-asm koivu-seed.pino`. Committing it would be publishing a derived artifact that its reader regenerates anyway.

## 2. Artifact Inventory

| Artifact | Form | Derived from | Stored in | Primary users | Verification available |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Seed source, Scheme** | text | hand-written | repository | auditors, porters, new-platform bring-up | full human review; this is the source of truth |
| **Seed image** `koivu-seed.pino` | text | printed from the seed source by a Koivu compiler | **release artifacts**, one file for all hosts | everyone - this is what the user lowers into a seed | reading it against the seed source; lowering it with Vesi |
| **Vesi source, Scheme** | text | hand-written | repository | auditors, porters | full human review; this is the source of truth |
| **Vesi `.s` per host** | text | rendered by Vesi from Vesi's own image, for that host's target | **repository** (see section 3) | auditors; porters; users checking the distributed binary | review of assembly; local reassembly with the platform assembler |
| **Vesi binary** per host (Windows optionally digitally signed) | machine code | the Vesi source, built by a Koivu compiler or, before M2, by the C scaffold | **release artifacts** | everyone - this is the only machine binary the project ships | reassembly of the committed `.s`; hex review; antivirus scan; signature check |
| **Seed source, C** | text | hand-written | repository until M2, then deleted | the authors, during early development | ordinary code review; never released |
| **Sapling source** | text | hand-written | repository | everyone - the user builds the sapling with the seed | ordinary code review; never released as an artifact |

Binaries are published, not committed. Assembly is committed as a convenience, not as a trust artifact, and only for Vesi.

Every release publishes a Vesi binary for every supported platform, plus the one seed image. There is no on-request channel, so a platform is either in every release or not supported yet ([Platforms and Targets](01_platforms.md), section 2).

## 3. Why Vesi's Assembly Is Committed

Committed assembly is an **educational and informative artifact, not a trust artifact.** Vesi's binary is what makes bootstrapping possible, and the assembly is there so that a person meeting Koivu for the first time can see what that binary is on a particular target without building anything: assembly is far more widely readable than a compiler's source, and "what is actually in there?" is the question newcomers ask first.

Vesi's assembly is committed for the supported hosts **as soon as `koivu-vesi` can render its own image as assembly that is reasonably easy to audit.** It is rendered by Vesi from the same image its binary is lowered from, so the two are outputs of one encoding pass rather than of two implementations that are supposed to agree ([Koivu Vesi](koivu-vesi.md), section 4). Neither Vesi nor any front end carries a separate assembly printer: a text form of the lowering would restate every byte template in a second representation, and that representation would have to be audited alongside the first.

The seed's assembly is deliberately not committed, for the reason given in section 1: the user renders it themselves, with the Vesi they are checking, from the image they were given. Before the Scheme seed exists there is nothing worth committing in either case: the C scaffold is a prototype whose assembly would describe a program that is about to be deleted.

Rules that follow from committing Vesi's assembly:

* **The Vesi source is the source of truth.** `.s` files are rendered by `koivu-vesi` and are never edited by hand.
* **A stale `.s` is a defect.** Whenever Vesi's source changes, the `.s` files must be regenerated in the same change.
* **Assembly is committed per host, beside the binary it describes.** A host is added by adding two artifacts - a Vesi binary and its `.s` - not by adding a variant of an existing one. A target that is not a host adds neither: Vesi's `.s` is Vesi's own machine code, and no Vesi binary exists for a platform the chain does not run on.
* **A missing `.s` is acceptable before the Scheme Vesi exists**, and is a defect afterwards.

**CI regenerates both the `.s` files and the seed's image, and fails on a mismatch.** For the assembly it builds Vesi's image from the current source, renders it with Vesi on every change, compares the result with what is committed and fails if the two differ. For the seed's image it recompiles the seed's source, compares the printed image with the published one and fails on any difference. Neither file is ever edited by hand, so a stale one cannot be merged by an author who forgot to regenerate it.

## 4. What Each Artifact Proves

| Artifact | What it proves | What it does not prove |
| :--- | :--- | :--- |
| the seed source and the Vesi source | exactly what each program is intended to do, at a level a person can read | that any published artifact was built from them |
| the seed's image | the exact program the user is about to run, in a form they can read | that it was printed from the published source, unless the user compares |
| Vesi's `.s` | the intended instruction sequence, and that a local assembler can reproduce a binary | that the published binary matches, unless the user compares |
| Vesi's binary | only what the user verifies: signature, scan result, reassembly, hex inspection | provenance, in the general case |

One thing this arrangement changes, and it should be stated rather than discovered: **the seed's byte-level guarantee is no longer carried by a published artifact.** The seed's machine code is produced on the user's own machine, by Vesi, from a readable image - so it is *stronger* than a published binary in the sense that the user performed the last step themselves, and *weaker* in the sense that no published seed binary exists to compare anything against. What used to be "trust this binary, or reassemble and compare" is now "read this image, then lower it here".

The practical auditability of a binary still rests on its size only in the negative sense: a hex review is realistic for Vesi and unrealistic for a full compiler, so size sets the limit below which review stays feasible. Below that limit, size is not what makes a binary auditable - a simpler, more regular instruction sequence is easier to verify even when it is several times larger. See [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2.

## 5. Provenance Non-Goal

There is no practical way to prove that a published artifact was produced from the published source, and the project does not attempt to provide one. A user who requires such a guarantee uses the Secure Path described in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), where the chain is bootstrapped inside a controlled environment.

The split does make the gap smaller and easier to look at. The unprovable step is now between two readable texts - the seed's source and the seed's image - rather than between a text and a binary. A reader can compare them; nothing can prove they match. For Vesi the step is unchanged: its binary is the trust anchor, and its committed assembly is what makes checking it practical.

This is a deliberate limit, not an oversight. It is recorded here so that it is not rediscovered as a defect, and so that the two bootstrapping paths are understood as a trade-off rather than as competing claims.

This limit does not go away when the chain becomes self-compilable. A user holding Vesi can rebuild it from source and compare the result, but that demonstrates reproducibility, not honesty: a compromised compiler reproduces itself perfectly, which is Thompson's point. The non-goal is about what can be proved, not about whether the chain can rebuild itself.

## 6. Verification Recipes

Ordered from strongest to weakest:

1. **Read the Vesi source and the seed source.** They are the source of truth and are small enough for a complete review.
2. **Reassemble Vesi's committed `.s`** with the platform assembler and compare the result byte-for-byte with the distributed Vesi binary. This is the strongest mechanical check available to a user, and it is why Vesi's assembly is committed at all.
3. **Compare Vesi's binary to its assembly** with an automated tool, for a user who does not want to assemble by hand.
4. **Lower the seed's image yourself.** `koivu-vesi koivu-seed.pino -o koivu-seed` produces the seed from the image with the Vesi just checked; there is no published seed binary to trust.
5. **Read the seed's image against the seed's source.** The image is text, and a reviewer can follow what the compiler produced without running anything.
6. **Hex review Vesi's binary.** Inspect the entry point, the syscall stubs and the absence of unexpected imports and strings.
7. **Scan and check the signature.** Antivirus scan, and a digital signature check where one is published.

Windows deserves a note: a bare Windows system has no assembler, so recipes 2 and 3 are unavailable there and a Windows user is left with 1, 4, 5, 6 and 7. That limitation used to sit on one of two artifacts; it now sits on the only distributed binary, which is why Vesi's budget in section 7 is the tighter of the two.

## 7. Size Budgets

There are two budgets, one per published program, because they are two programs with different jobs and a single number would hide which one grew. Each is a ceiling that keeps review feasible, not a target to minimise: a larger binary with simpler, more regular code may be the better choice ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2).

Components that count against the **seed's** budget:

* the reader and the compiler front end;
* the arena allocator and byte buffers;
* the canonical image printer;
* the OS glue layer (the seven host primitives listed in [Stage 1 (Seed)](04_stage1_seed.md), section 3).

Components that do not count against it: the instruction encoder, the fixup resolver, the container writers and the target descriptions, all of which live in Vesi now ([Koivu Vesi](koivu-vesi.md), section 4).

Components that count against **Vesi's** budget:

* the `.pino` reader and the static stack-balance verifier;
* the instruction encoder - one byte template per instruction per target;
* the label table and the backpatch resolver;
* the container writers, one per format;
* the OS glue layer.

Components that do not count against it: target descriptions, which are data files read at run time; and the seed's or the sapling's sources, which are reviewed as source rather than shipped inside the binary.

### The Budgets as They Stand

The numbers below are an **estimate, not a measurement**. They are derived before the Scheme seed and the Scheme Vesi exist, from the size the programs are expected to have and from the density unoptimised stack-machine lowering is expected to produce. They are ceilings that keep the audit assumption honest, and they are to be replaced by measured values once the programs can be built, not defended.

Basis of the estimate:

* the old single compiler was estimated at roughly 1 MiB on `x86_64` and 1.5 MiB on `arm64`;
* the seed keeps the front end, about 78% of it, and Vesi is about 60% of it, so the pair is roughly 1.4 times the old single compiler - the cost of the split, recorded in [Koivu Vesi](koivu-vesi.md), section 5 rather than hidden here;
* lowering is unoptimised, one fixed byte template per instruction, so a line of Scheme costs on the order of 150-200 bytes of machine code;
* `arm64` templates are fixed-width 4-byte instructions and need more of them per operation than the one-byte `push`/`pop` pair on `x86_64`, so an `arm64` artifact is expected to be roughly half again as large;
* each ceiling is twice its estimate, as before.

| Artifact | Estimate | Ceiling - twice the estimate |
| :--- | :--- | :--- |
| `koivu-seed.pino` | text, and not budgeted in bytes | - |
| seed binary, Linux `x86_64`, ELF64 | ~800 KiB | **1600 KiB** (1638400 bytes) |
| seed binary, Windows `x86_64`, PE32+ | ~800 KiB | **1600 KiB** (1638400 bytes) |
| seed binary, macOS `arm64`, Mach-O | ~1200 KiB | **2400 KiB** (2457600 bytes) |
| `koivu-vesi`, Linux `x86_64`, ELF64 | ~600 KiB | **1200 KiB** (1228800 bytes) |
| `koivu-vesi.exe`, Windows `x86_64`, PE32+ | ~600 KiB | **1200 KiB** (1228800 bytes) |
| `koivu-vesi`, macOS `arm64`, Mach-O | ~900 KiB | **1800 KiB** (1843200 bytes) |

The seed's row is listed even though the seed is published as an image: the budget applies to the binary the user produces from it, which is what gets audited. The image itself is text and is bounded by the front end's `EMIT_BUFFER_BYTES` ([Stage 1 (Seed)](04_stage1_seed.md), section 2) rather than by an audit budget.

The C scaffolds are not budgeted. Neither is distributed, and both are roughly an order of magnitude smaller, so their size would say nothing about the artifacts that matter.

Exceeding a ceiling is a signal that the audit assumption in section 4 needs revisiting, not an automatic build failure. The number exists to make that conversation happen while it is still cheap.
