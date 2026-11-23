# Koivu Seed Artifacts

**Status:** Architecture Blueprint

**Component:** Global

This document defines which forms of the Stage 1 seed exist, what each of them is derived from, where it is stored, what verification it admits and what it does not prove. It is the shared reference for [Platforms and Targets](01_platforms.md), [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md) and [Stage 1 (Seed)](04_stage1_seed.md).

---

## 1. Why the Seed Is Shipped in Several Forms

The seed is the trust anchor of the entire chain. It is the only component that cannot be built by Koivu, so users have to inspect it in a form they can trust. Different users need different forms:

* some want the source of truth, and will read it;
* some want to build it locally with tools they already have;
* some want to run it immediately, on a platform where no assembler is available;
* some want to see, quickly, what the seed looks like before deciding to use Koivu at all.

Each form is described below with the verification it supports. No single form is authoritative for all purposes.

## 2. Artifact Inventory

| Artifact | Derived from | Stored in | Primary users | Verification available | Trust level |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Seed source, Scheme** | hand-written | repository | auditors, porters, new-platform bring-up | full human review; this is the source of truth | highest |
| **Seed `.s` per target** | the Scheme seed, compiled by `koivu-pino` | **repository** (see section 3) | newcomers wanting to see what the seed looks like on a given target; porters | review of assembly; local reassembly with the platform assembler | high, but convenience only |
| **Seed binaries** (per target; Windows optionally digitally signed) | the seed source, built by a Koivu compiler or, before M2, by the C scaffold | release artifacts | everyone - this is what makes bootstrapping possible | hex review of a small binary; antivirus scan; signature check | medium |
| **Seed source, C** | hand-written | repository until M2, then deleted | the authors, during early development | ordinary code review | none - never released |

Binaries are published, not committed. Assembly is committed as a convenience, not as a trust artifact.

Every release publishes a binary for every supported platform. There is no on-request channel, so a platform is either in every release or not supported yet ([Platforms and Targets](01_platforms.md), section 2).

## 3. Why Assembly Sources Are Committed

Committed assembly is an **educational and informative artifact, not a trust artifact.** Bootstrapping is enabled by the released seed binaries. The assembly is there so that a person meeting Koivu for the first time can see what the seed looks like on a particular target without building anything: assembly is far more widely readable than a compiler's source, and "what is actually in there?" is the question newcomers ask first.

The seed is therefore published in assembly for the supported targets **as soon as `koivu-pino` produces assembly for it that is reasonably easy to audit.** Assembly is produced by `koivu-pino`, a development tool, from the same Scheme source the seed is built from ([Pino IR](pino.md), section 1). Neither the seed nor the bridge carries an assembly printer: a text form of the lowering would restate every byte template in a second representation, and that representation would have to be audited alongside the first. Before the Scheme seed exists there is nothing worth committing: the C seed is a prototype whose assembly would describe a program that is about to be deleted.

Rules that follow from committing them:

* **The Scheme seed source is the source of truth.** `.s` files are produced by `koivu-pino` and are never edited by hand.
* **A stale `.s` is a defect.** Whenever the seed source changes, the `.s` files must be regenerated in the same change.
* **Assembly is committed per target.** Adding a target adds an artifact, not a variant of an existing one.
* **A missing `.s` is acceptable before the Scheme seed exists**, and is a defect afterwards.

**CI regenerates the `.s` files and fails on a mismatch.** The check runs `koivu-pino` over the current seed source on every change, compares the result with what is committed and fails the build if the two differ. A stale `.s` therefore cannot be merged by an author who forgot to regenerate it, which is the only way it could arise: the files are never edited by hand.

## 4. What Each Artifact Proves

| Artifact | What it proves | What it does not prove |
| :--- | :--- | :--- |
| the seed source | exactly what the seed is intended to do, at a level a person can read | that any distributed binary was built from them |
| `.s` files | the intended instruction sequence, and that a local assembler can reproduce a binary | that the published binary matches, unless the user compares |
| binaries | only what the user verifies: signature, scan result, hex inspection | provenance, in the general case |

The practical auditability of a binary rests on its size only in the negative sense: a hex review is realistic for the seed and unrealistic for a full compiler, so size sets the limit below which review stays feasible. Below that limit, size is not what makes a binary auditable - a simpler, more regular instruction sequence is easier to verify even when it is several times larger. See [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2.

## 5. Provenance Non-Goal

There is no practical way to prove that a distributed seed binary was produced from the published seed source, and the project does not attempt to provide one. A user who requires such a guarantee uses the Secure Path described in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), where the seed is bootstrapped inside a controlled environment.

This is a deliberate limit, not an oversight. It is recorded here so that it is not rediscovered as a defect, and so that the two bootstrapping paths are understood as a trade-off rather than as competing claims.

This limit does not go away when the seed becomes self-compilable. A user holding the distributed seed can rebuild it from source and compare the result, but that demonstrates reproducibility, not honesty: a compromised seed reproduces itself perfectly, which is Thompson's point. The non-goal is about what can be proved, not about whether the seed can rebuild itself.

## 6. Verification Recipes

Ordered from strongest to weakest:

1. **Read the seed source.** It is the source of truth and is small enough for a complete review.
2. **Rebuild locally.** Assemble the committed `.s` file with the platform assembler and compare behaviour with the distributed binary.
3. **Compare binary to assembly.** Use a custom automated tool to check that the machine code corresponds to the committed assembly (mentioned in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md)).
4. **Hex review.** Inspect the entry point, the syscall stubs and the absence of unexpected imports and strings.
5. **Scan and check the signature.** Antivirus scan, and a digital signature check where one is published.

## 7. Seed Size Budget

The acceptance criterion behind "Auditability & Simplicity" in the [Architecture Map](../architecture.md) is practical: a reviewer must be able to complete a hex review of a seed binary in a reasonable session. The budget is a ceiling that keeps review feasible. It is not a target to minimise, and a larger binary with simpler, more regular code may be the better choice ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2).

Components that count against the budget:

* the reader and the compiler front end;
* the **Pino compiler library** - instruction encoder, backpatch resolver and container writer - which is linked into the seed;
* the arena allocator and byte buffers;
* the OS glue layer (the seven host primitives listed in [Stage 1 (Seed)](04_stage1_seed.md), section 3).

Components that do not count against it:

* target descriptions: data files, read at build time;
* the seed's source in either language: reviewed as source, not shipped inside the binary;
* committed `.s` files: derived artifacts, described in section 3.

### The Budget as It Stands

The numbers below are an **estimate, not a measurement**. They are derived before the Scheme seed exists, from the size the program is expected to have and from the density unoptimised stack-machine lowering is expected to produce. They are a ceiling that keeps the audit assumption honest, and they are to be replaced by measured values once the seed can be built, not defended.

Basis of the estimate:

* the Scheme seed is about the same program as the C scaffold - reader, interner, arena, front end, Pino compiler library - and is expected to be on the order of 6,000 lines;
* lowering is unoptimised, one fixed byte template per instruction, so a line of Scheme costs on the order of 150-200 bytes of machine code;
* `arm64` templates are fixed-width 4-byte instructions and need more of them per operation than the one-byte `push`/`pop` pair on `x86_64`, so an `arm64` seed is expected to be roughly half again as large.

| Artifact | Estimate | Ceiling - twice the estimate |
| :--- | :--- | :--- |
| `koivu-seed`, Linux `x86_64`, ELF64 | ~1 MiB | **2 MiB** (2097152 bytes) |
| `koivu-seed.exe`, Windows `x86_64`, PE32+ | ~1 MiB | **2 MiB** (2097152 bytes) |
| `koivu-seed`, macOS `arm64`, Mach-O | ~1.5 MiB | **3 MiB** (3145728 bytes) |

The C scaffold is not budgeted. It is never distributed, and it is roughly an order of magnitude smaller, so its size would say nothing about the artifact that matters.

Exceeding a ceiling is a signal that the audit assumption in section 4 needs revisiting, not an automatic build failure. The number exists to make that conversation happen while it is still cheap.
