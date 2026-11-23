# Koivu Roadmap to Self-hosting

**Status:** Architecture Blueprint  

**Component:** Global  

> Capt. Barbossa: So you expect to leave me standing on some beach with nothing but a name and your word it's the one I need and watch you sail away on my ship?<br>
> Capt. Jack Sparrow: No. I expect to leave you standing on some beach with absolutely no name at all, watching me sail away on *my* ship, and then I'll shout the name back to you. Savvy?<br>
> Capt. Barbossa: But that still leaves us with the problem of me standing on some beach with naught but a name and your word it's the one I need.

This document maps out the bootstrapping pipeline of the **Koivu** compiler infrastructure. It uses classic **T-diagrams** to show how the project transitions from a single external host dependency - a C compiler used to build the seed - to a chain that needs nothing outside itself.

## 0. How to Read This Document

Three conventions are used throughout, and all three are inherited from other blueprints rather than defined here:

* **Step numbers** follow the four-step build chain in [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 6. That chain starts at the bridge build, so building the seed itself is **Step 0**: a prerequisite, not one of the four steps.
* **Milestone names** (M0 to M4) follow [Backend](backend.md), section 1. A milestone is not a release number; it marks the point at which a particular lowering capability appears.
* **The reference host is Linux `x86_64`.** The diagrams show one platform because the chain is the same on every host. Section 6 adds a second axis - in what form each compiler exists - and section 7 covers the one host, macOS, where the chain takes a different shape. Other per-platform differences are out of scope here.

One distinction is worth stating before the first diagram, because the rest of the document depends on it: **no `.ll` file appears anywhere in this chain.** Stages 1 and 2 build Pino IR in memory and lower it themselves, so there is nothing between their source and their machine code. Stage 3 keeps the ability to emit textual LLVM IR permanently, as its primary debugging instrument and as the input to `koivu-llc`, but nothing in the chain consumes that output ([Pino IR](pino.md), section 1; [Backend](backend.md), section 7).

### T-Diagram Notation Recap
A compiler T-diagram represents:
* **Left:** The source language being compiled.
* **Right:** The target language produced.
* **Bottom:** The language the compiler itself is written in.

---

## 1. Step 0: Building the Seed (M0)

Before the chain can start, the seed has to exist as a running program. Before M2 there is no Koivu executable anywhere, so an external C compiler must build the seed from its C sources. This is the only external tool the project ever uses.

```text
       +-----------------------+

       |       Stage 1         |
       |       Source (C)      |
       +-------+       +-------+

               |       |
       +-------+-------+-------+

       |    C    -->  x86_64   |
       |                       |
       +-------+       +-------+

               |       |
               | clang |  <--- (External LLVM C compiler, until M2)
               +-------+
```

* **Input:** the Stage 1 C sources.
* **Tool running:** an external LLVM C compiler, which also drives the platform assembler and linker.
* **Output:** the `koivu-seed` binary.
* **Milestone:** M0. This is pure **bootstrapping via a host compiler**.
* **When it stops:** at M2. From M2 the seed is written in Scheme and rebuilt by a Koivu compiler produced by the chain, with no external tool involved ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2).

Step 0 is the only step that needs a tool from outside the chain, and only until M2. It does not disappear from the project's practice even then: the Koivu compiler that rebuilds the seed is **not distributed**, so a user starts from a seed artifact and reaches the M2 shape by completing the chain once. That is why a seed artifact has to exist at all, and why the seed is the only compiler Koivu ships.

---

## 2. Step 1: Generating the Bridge Binary (M0)

With a working `koivu-seed` binary, the seed compiles the Stage 2 bridge source code. Stage 2 introduces hygienic macros; closures are already available in Stage 1, because the bridge is itself written in them.

```text
       +-----------------------+

       |       Stage 2         |
       |       Source          |
       +-------+       +-------+

               |       |
       +-------+-------+-------+

       | Scheme  -->  x86_64   |
       |                       |
       +-------+       +-------+

               |       |
               | x86_64|  <--- (Stage 1 Seed binary built in Step 0)
               +-------+
```

* **Input:** Stage 2 bridge source code.
* **Compiler running:** the Stage 1 seed.
* **Intermediate:** Pino IR, built in memory by the seed.
* **Lowering:** the Pino compiler library, linked into the seed.
* **Output:** the `koivu-bridge` binary.
* **Milestone:** M0.

**Lowering is part of this step, not a separate step after it.** The seed lowers Pino IR itself and writes the executable container itself, so no external tool appears here at all. This is bootstrap goal 1 ([Backend](backend.md), section 1), and it is met at M0 - the earliest milestone, not the last.

---

## 3. Step 2: Generating the Stage 3 Binary (Version A)

Using the bridge binary, the initial implementation of Stage 3 (the statically typed Scheme dialect featuring the Nanopass architecture) is compiled.

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
               | x86_64|  <--- (Stage 2 Bridge binary generated in Step 1)
               +-------+
```

* **Input:** Stage 3 source code.
* **Compiler running:** the bridge binary.
* **Intermediate:** Pino IR, built in memory by the bridge.
* **Lowering:** the Pino compiler library, linked into the bridge - the same code the seed carries.
* **Output:** Stage 3 **Version A**.
* **Milestone:** M1.

Two properties of this step are worth stating explicitly. There is no subset restriction: the bridge lowers **every** instruction of the declared Pino ISA, and conformance is a membership test rather than a closure over a special subset ([Backend](backend.md), section 4). And no `.ll` file is produced, so no external lowering appears in this step either.

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

The difference between Version A and Version B is code quality, not capability: both emit machine code. Version A's *own* machine code was produced by the bridge, which lowers through Pino and makes no attempt to optimise anything; Version B's was produced by the production backend. That is the one-generation lag inherent to bootstrapping - a compiler can only use a lowerer it already contains - and it is why the fixpoint check compares B with C rather than A with B.

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
| Step 1 | the seed | **distributed** with the project | published binary on every host, with committed `.s` for reading ([Seed Artifacts](08_seed_artifacts.md), section 2) |
| Step 2 | the bridge binary | produced by the seed in Step 1 | native binary, built on the user's machine |
| Steps 3 and 4 | Stage 3 Versions A and B | produced by the previous step | native binary, built on the user's machine |

Only one row of this table is a distribution question. The seed is the only compiler the project ships; everything after it is produced locally, so its form is decided by the platform rather than by the project's release process. The inventory of seed forms, and what each of them proves and does not prove, is in [Seed Artifacts](08_seed_artifacts.md), sections 2 and 4.

The axis matters here rather than in a footnote because the form of the seed is where the Simple and Secure Paths diverge. A user who assembles the committed `.s` file has performed a local build and can compare the result against the binary they downloaded; a user who only runs the published binary has not, and relies on inspection instead. Both are supported, and the difference between them is described in [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), sections 4 and 5.

---

## 7. macOS: the Simple Path Platform

macOS is the one host where the chain as drawn is not quite what happens, and the reason belongs in the roadmap rather than only in the platform notes.

Emitting assembly solves **distribution**, not **execution**. On Apple Silicon the executable that the seed *produces* must also be signed, not only the seed itself. Whether the seed grows a Mach-O container writer and an ad-hoc signer is open question 1 in [Platforms and Targets](01_platforms.md), section 7, and it is deliberately unsettled. Until it is answered, macOS takes the other route: the seed's output for the bridge is finished by the platform assembler, linker and `codesign` instead of being written as a container.

The consequences for the roadmap, stated plainly:

* **The chain still completes.** Steps 2 to 4 are unchanged: once the platform tools have produced it, the bridge binary is an ordinary native binary.
* **macOS does not reach bootstrap goal 1 in the near term.** Linux and Windows reach M0 with the seed lowering and wrapping the bridge itself; on macOS, Step 1 keeps using platform tools.
* **Whether macOS reaches Steps 3 and 4 is the same open question.** Those steps require Stage 3 to produce a signed Mach-O executable itself, which is exactly whether a Mach-O container writer is in near-term scope.

One gap has to be recorded with it, because the route depends on it and it is not part of the Mach-O question: the Pino compiler emits **bytes**, not assembly text. Rendering lowered code as assembly for a platform assembler to consume therefore needs a printer or a disassembler that the design does not yet have. The committed `.s` seed artifacts of [Seed Artifacts](08_seed_artifacts.md), section 3 need the same thing.

macOS is therefore a **Simple Path** platform in the sense of [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 4: supported, bootstrapping, and reliant on platform tools. This does not weaken the other two hosts and does not change the priority order in [Platforms and Targets](01_platforms.md), section 2.
