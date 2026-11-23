# Koivu Roadmap to Self-hosting

**Status:** Architecture Blueprint  

**Component:** Global  

> Capt. Barbossa: So you expect to leave me standing on some beach with nothing but a name and your word it's the one I need and watch you sail away on my ship?<br>
> Capt. Jack Sparrow: No. I expect to leave you standing on some beach with absolutely no name at all, watching me sail away on *my* ship, and then I'll shout the name back to you. Savvy?<br>
> Capt. Barbossa: But that still leaves us with the problem of me standing on some beach with naught but a name and your word it's the one I need.

This document maps out the bootstrapping pipeline of the **Koivu** compiler infrastructure. It uses classic **T-diagrams** to show how the project transitions from a single external host dependency - a C compiler used to build the seed and Vesi - to a chain that needs nothing outside itself.

## 0. How to Read This Document

Three conventions are used throughout, and all three are inherited from other blueprints rather than defined here:

* **Step numbers** follow the four-step build chain in [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 6. That chain starts at the sapling build, so building the seed itself is **Step 0**: a prerequisite, not one of the four steps.
* **Milestone names** (M0 to M4) follow [Backend](backend.md), section 1. A milestone is not a release number; it marks the point at which a particular lowering capability appears.
* **The reference host is Linux `x86_64`.** The diagrams show one platform because the chain is the same on every host. Section 6 adds a second axis - in what form each compiler exists - and section 7 covers macOS, the one host that adds a step after the chain has run. Other per-platform differences are out of scope here.

One distinction is worth stating before the first diagram, because the rest of the document depends on it: **no `.ll` file appears anywhere in this chain.** Stages 1 and 2 build Pino IR, write it out as a canonical `.pino` image and stop; `koivu-vesi` lowers that image to machine code. Neither stage contains an encoder, a container writer or a target description, and nothing between their source and the bytes is external. Stage 3 keeps the ability to emit textual LLVM IR permanently, as its primary debugging instrument and as the input to `koivu-llc`, but nothing in the chain consumes that output ([Pino IR](pino.md), section 1; [Backend](backend.md), section 7).

A second convention follows from that split: **Steps 1 and 2 are drawn as two T's.** A front end writes an image and Vesi lowers it, so each of those steps has a `Scheme -> Pino` half and a `Pino -> x86_64` half. Steps 3 and 4 stay single, because Stage 3 lowers natively and needs no second program.

### T-Diagram Notation Recap
A compiler T-diagram represents:
* **Left:** The source language being compiled.
* **Right:** The target language produced.
* **Bottom:** The language the compiler itself is written in.

---

## 1. Step 0: Building the Seed and Vesi (M0)

Before the chain can start, two programs have to exist: the seed, which writes images, and Vesi, which lowers them. Before M2 there is no Koivu executable anywhere, so an external C compiler must build both from their C sources. This is the only external tool the project ever uses.

```text
       +-----------------------+     +-----------------------+

       |      Seed Source      |     |      Vesi Source      |
       |      (C)              |     |      (C)              |
       +-------+       +-------+     +-------+       +-------+

               |       |                   |       |
       +-------+-------+-------+     +-------+-------+-------+

       |    C    -->  x86_64   |     |    C    -->  x86_64   |
       |                       |     |                       |
       +-------+       +-------+     +-------+       +-------+

               |       |                   |       |
               | clang |                   | clang |  <--- (External LLVM C compiler, until M2)
               +-------+                   +-------+
```

* **Input:** the seed's C sources and Vesi's C sources.
* **Tool running:** an external LLVM C compiler, twice; it also drives the platform assembler and linker.
* **Output:** the `koivu-seed` and `koivu-vesi` binaries.
* **Milestone:** M0. This is pure **bootstrapping via a host compiler**.
* **When it stops:** at M2. From M2 both are written in Scheme and rebuilt by a Koivu compiler produced by the chain, with no external tool involved ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2).

Step 0 is the only step that needs a tool from outside the chain, and only until M2. It does not disappear from the project's practice even then: the Koivu compiler that rebuilds the seed and Vesi is **not distributed**, so a user starts from the published binaries and reaches the M2 shape by completing the chain once. That is why those binaries have to be published at all, and why they are the only ones Koivu ships.

---

## 2. Step 1: Generating the Sapling Binary (M0)

With a working `koivu-seed` binary and a working `koivu-vesi`, the seed compiles the Stage 2 sapling source and Vesi lowers the image. Stage 2 introduces hygienic macros; closures are already available in Stage 1, because the sapling is itself written in them.

```text
       +-----------------------+     +-----------------------+

       |       Stage 2         |     |       image           |
       |       Source          |     |       (.pino)         |
       +-------+       +-------+     +-------+       +-------+

               |       |                   |       |
       +-------+-------+-------+     +-------+-------+-------+

       | Scheme  -->  Pino     |     | Pino    -->  x86_64   |
       |                       |     |                       |
       +-------+       +-------+     +-------+       +-------+

               |       |                   |       |
               | x86_64|                   | x86_64|
               +-------+                   +-------+
        (Stage 1 Seed, Step 0)        (koivu-vesi, Step 0)
```

* **Input:** Stage 2 sapling source code.
* **Compiler running:** the Stage 1 seed, then Vesi.
* **Intermediate:** a `.pino` image, written by the seed.
* **Lowering:** `koivu-vesi`.
* **Output:** the `koivu-sapling` binary.
* **Milestone:** M0.

**Two T's, not one.** The seed is `Scheme -> Pino`; Vesi is `Pino -> x86_64`. Splitting them is what keeps the seed portable: it carries no encoder, no container writer and no target description, and the image it writes is target-independent, so the same seed binary serves every host ([Koivu Vesi](koivu-vesi.md), section 1). No external tool appears in either half, which is bootstrap goal 1 ([Backend](backend.md), section 1), met at M0 - the earliest milestone, not the last.

---

## 3. Step 2: Generating the Stage 3 Binary (Version A)

Using the sapling binary, the initial implementation of Stage 3 (the statically typed Scheme dialect featuring the Nanopass architecture) is compiled.

```text
       +-----------------------+     +-----------------------+

       |       Stage 3         |     |       image           |
       |       Source          |     |       (.pino)         |
       +-------+       +-------+     +-------+       +-------+

               |       |                   |       |
       +-------+-------+-------+     +-------+-------+-------+

       | Scheme  -->  Pino     |     | Pino    -->  x86_64   |
       |                       |     |                       |
       +-------+       +-------+     +-------+       +-------+

               |       |                   |       |
               | x86_64|                   | x86_64|
               +-------+                   +-------+
        (Stage 2 Sapling, Step 1)     (koivu-vesi, Step 0)
```

* **Input:** Stage 3 source code.
* **Compiler running:** the sapling binary, then Vesi.
* **Intermediate:** a `.pino` image, written by the sapling.
* **Lowering:** `koivu-vesi`, the same binary as in Step 1.
* **Output:** Stage 3 **Version A**.
* **Milestone:** M1.

Two properties of this step are worth stating explicitly. The lowering is not a second implementation: it is the same Vesi that lowered the sapling, so a compiler's image and the sapling's image are encoded by identical code. And there is no subset restriction: Vesi lowers **every** instruction of the declared Pino ISA, and conformance is a membership test rather than a closure over a special subset ([Backend](backend.md), section 4). No `.ll` file is produced, so no external lowering appears in this step either.

---

## 4. Step 3: Native Rebuild (Version B)

Once the production lowering stack exists inside the Stage 3 source, the project can produce a compiler that is lowered by Koivu itself.

```text
       +-----------------------+

       |       Stage 3         |
       |       Source          |
       +-------+       +-------+

               |       |
       +-------+-------+-------+

       | Scheme  -->  x86_64   |
       |                       |
       +-------+       +-------+

               |       |
               | x86_64|  <--- (Stage 3 Version A)
               +-------+
```

* **Input:** Stage 3 source code.
* **Compiler running:** Stage 3 **Version A**, which contains the native lowering stack.
* **Intermediate:** LLVM IR held in memory inside Version A - the same shape as Pino IR one stage earlier. No file is written and no external tool lowers it; Stage 3 contains its own lowering stack ([Backend](backend.md), section 7.2).
* **Output:** Stage 3 **Version B**.
* **Milestone:** M3.

The difference between Version A and Version B is code quality, not capability: both emit machine code. Version A's *own* machine code was produced by Vesi from the sapling's image, and Vesi makes no attempt to optimise anything; Version B's was produced by the production backend. That is the one-generation lag inherent to bootstrapping - a compiler can only use a lowerer it already contains - and it is why the fixpoint check compares B with C rather than A with B.

---

## 5. Step 4: The Fixpoint Check (Version C)

To demonstrate that the chain has stabilized, Version B compiles the Stage 3 source one final time.

```text
       +-----------------------+

       |       Stage 3         |
       |       Source          |
       +-------+       +-------+

               |       |
       +-------+-------+-------+

       | Scheme  -->  x86_64   |
       |                       |
       +-------+       +-------+

               |       |
               | x86_64|  <--- (Stage 3 Version B)
               +-------+
```

* **Input:** Stage 3 source code.
* **Compiler running:** Stage 3 **Version B**.
* **Output:** Stage 3 **Version C**.
* **Milestone:** M4.

When Version B and Version C are **byte-for-byte identical**, the compiler has reached a fixpoint and stable self-hosting is demonstrated. Three conditions make the check meaningful, and they are stated in [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 6: compare B with C rather than A with B, use the same backend configuration on both sides, and require deterministic emission.

**What this does and does not mean.** The fixpoint is where the *compilers* stop needing anything external: from Version B onward, each compiler is lowered by the previous one. Steps 1 to 4 contain no external tool at all - Step 1 has needed none since M0, Step 2 since M1, and the only step that ever needed one is Step 0, which stopped needing it at M2.

Nor does a fixpoint prove trustworthiness. It proves reproducibility and self-consistency; a deliberately planted backdoor would be reproduced perfectly along with everything else. That distinction, and the separate Secure Path that addresses it, belong to [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 8.

---

## 6. The Artifact Axis

The steps above answer *which compiler runs*. A second, independent axis answers *in what form that compiler exists*. The step chain is identical on every host; the form is not, and it is the form that decides what a user has to do before Step 1 can start.

| Step | Compiler that runs | Where that compiler comes from | Form |
| :--- | :--- | :--- | :--- |
| Step 0, before M2 | an external C compiler | the host toolchain | not a Koivu artifact |
| Step 0, from M2 | a Koivu compiler | built earlier in the chain by the same user | native binary, built on the user's machine |
| Step 1 | the seed, then Vesi | **distributed** with the project | published binaries on every host, with committed `.s` for reading ([Seed Artifacts](08_seed_artifacts.md), section 2) |
| Step 2 | the sapling, then Vesi | the sapling is produced by the seed in Step 1; Vesi is the same published binary | native binaries, built on the user's machine |
| Steps 3 and 4 | Stage 3 Versions A and B | produced by the previous step | native binary, built on the user's machine |

One row of this table is a distribution question. The seed and Vesi are the only binaries the project ships; everything after them is produced locally, so their form is decided by the platform rather than by the project's release process. The inventory of published forms, and what each of them proves and does not prove, is in [Seed Artifacts](08_seed_artifacts.md), sections 2 and 4.

The axis matters here rather than in a footnote because the form of the seed is where the Simple and Secure Paths diverge. A user who assembles the committed `.s` file has performed a local build and can compare the result against the binary they downloaded; a user who only runs the published binary has not, and relies on inspection instead. Both are supported, and the difference between them is described in [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), sections 4 and 5.

---

## 7. macOS: One Command Added, Not a Different Chain

macOS is not a host where the chain takes a different shape. Vesi writes the executable container on all three hosts; the one thing macOS adds is a step the **user** performs, not Vesi: an executable on Apple Silicon must be signed before it will run, so Vesi writes an unsigned Mach-O and the user ad-hoc signs it with `codesign --force --sign -` ([Platforms and Targets](01_platforms.md), section 6.2).

What that means for the roadmap:

* **The chain completes identically.** Vesi lowers the image and writes the container exactly as on Linux and Windows. The only platform tool is the signing command, and it runs after Step 1 has already produced its output.
* **macOS reaches bootstrap goal 1 with the other two hosts.** No step waits for a Mach-O writer, because Vesi has one, and no step needs an assembler or a linker.
* **Signing is not part of the trust story.** An ad-hoc signature makes a binary runnable; it says nothing about who built it. Provenance remains the recorded non-goal of [Seed Artifacts](08_seed_artifacts.md), section 5, and the Secure Path is unaffected.

The committed `.s` seed artifacts are a separate matter and are not affected by any of this: they are rendered by `koivu-vesi` from the same image the seed binary is lowered from, not by the seed itself ([Seed Artifacts](08_seed_artifacts.md), section 3).

macOS is therefore a **Simple Path** platform in the sense of [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 4 - and now for the same reason as the other two hosts, rather than in a weaker sense than them.
