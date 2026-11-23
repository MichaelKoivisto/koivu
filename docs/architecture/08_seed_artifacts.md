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
| **Stage 1 `.ll` sources** | hand-written | repository | auditors, porters, new-platform bring-up | full human review; this is the source of truth | highest |
| **Stage 1 `.s` per target** | `.ll` via `llc` | **repository** (see section 3) | Linux and macOS users on the standard path; people evaluating Koivu | review of assembly; local reassembly with the platform assembler | high |
| **`koivu-seed.exe`** (Windows, optionally digitally signed) | `.ll` / `.s` via `llc` and a linker | release artifacts | Windows users on the standard path | hex review of a small binary; antivirus scan; signature check | medium |
| **Seed binaries for other targets** | same as above | release artifacts | users on those platforms, rarely needed | same as Windows | medium |
| **Koivu-built seed** | not planned, see section 5 | - | - | - | - |

The `.ll` sources and the `.s` files are both kept in the repository. Binaries are published, not committed.

## 3. Why Assembly Sources Are Committed

Assembly sources are committed so that a person considering Koivu can see, without building anything, what the seed looks like in every form it takes. The seed is the part of the project that must be trusted first, and a readable assembly file is a much faster answer to "what is actually in there?" than a build instruction.

Rules that follow from committing them:

* **The `.ll` sources are the source of truth.** `.s` files are derived and are never edited by hand.
* **A stale `.s` is a defect.** Whenever `.ll` sources change, the `.s` files must be regenerated in the same change.
* **Reviewers of a `.ll` change review the corresponding `.s` diff as well.** The point of committing assembly is that the two stay in step.
* **Assembly is committed per target.** Adding a target adds an artifact, not a variant of an existing one.

Open item: whether regeneration of `.s` is enforced by CI (see section 8).

## 4. What Each Artifact Proves

| Artifact | What it proves | What it does not prove |
| :--- | :--- | :--- |
| `.ll` sources | exactly what the seed is intended to do, at a level a person can read | that any distributed binary was built from them |
| `.s` files | the intended instruction sequence, and that a local assembler can reproduce a binary | that the published binary matches, unless the user compares |
| binaries | only what the user verifies: signature, scan result, hex inspection | provenance, in the general case |

The practical auditability of a binary rests on its size only in the negative sense: a hex review is realistic for the seed and unrealistic for a full compiler, so size sets the limit below which review stays feasible. Below that limit, size is not what makes a binary auditable - a simpler, more regular instruction sequence is easier to verify even when it is several times larger. See [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2.

## 5. Provenance Non-Goal

There is no practical way to prove that a distributed seed binary was produced from the published `.ll` sources, and the project does not attempt to provide one. A user who requires such a guarantee uses the Secure Path described in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), where the seed is bootstrapped inside a controlled environment.

This is a deliberate limit, not an oversight. It is recorded here so that it is not rediscovered as a defect, and so that the two bootstrapping paths are understood as a trade-off rather than as competing claims.

This limit does not go away when the seed becomes self-compilable. A user holding the distributed seed can rebuild it from source and compare the result, but that demonstrates reproducibility, not honesty: a compromised seed reproduces itself perfectly, which is Thompson's point. The non-goal is about what can be proved, not about whether the seed can rebuild itself.

## 6. Verification Recipes

Ordered from strongest to weakest:

1. **Read the `.ll` sources.** They are the source of truth and are small enough for a complete review.
2. **Rebuild locally.** Assemble the committed `.s` file with the platform assembler and compare behaviour with the distributed binary.
3. **Compare binary to assembly.** Use a custom automated tool to check that the machine code corresponds to the committed assembly (mentioned in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md)).
4. **Hex review.** Inspect the entry point, the syscall stubs and the absence of unexpected imports and strings.
5. **Scan and check the signature.** Antivirus scan, and a digital signature check where one is published.

## 7. Seed Size Budget

The acceptance criterion behind "Auditability & Simplicity" in the [Architecture Map](../architecture.md) is practical: a reviewer must be able to complete a hex review of a seed binary in a reasonable session. The budget is a ceiling that keeps review feasible. It is not a target to minimise, and a larger binary with simpler, more regular code may be the better choice ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2).

Components that count against the budget:

* the reader and the compiler front end;
* the **evaluator** - environments, `apply`, special forms and primitive dispatch - required by resolved decision 7 in [Backend](backend.md), section 3.3;
* the arena allocator and byte buffers;
* the S-LLVM IR emitter;
* the OS glue layer (the six host primitives listed in [Stage 1 (Seed)](04_stage1_seed.md), section 3).

Components that do not count against it:

* `simple-codegen` and the container writer: Stage 1 Lisp, executed at build time. They are reviewed as source, but they are not part of the binary.
* target descriptions: data files.

Open item: the numeric ceiling per artifact is not set yet (see section 8).

## 8. Open Items

| Item | Why it matters |
| :--- | :--- |
| Numeric size budget per artifact | turns "small enough to audit" into a checkable requirement |
| Whether CI regenerates `.s` and fails on a mismatch | prevents stale assembly from being committed |
| Whether binaries for other targets are published per release or on request | affects the release checklist in [Platforms and Targets](01_platforms.md) |
