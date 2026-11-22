# Koivu Roadmap to Self-hosting

**Status:** Architecture Blueprint  

**Component:** Global  

> Capt. Barbossa: So you expect to leave me standing on some beach with nothing but a name and your word it's the one I need and watch you sail away on my ship?<br>
> Capt. Jack Sparrow: No. I expect to leave you standing on some beach with absolutely no name at all, watching me sail away on *my* ship, and then I'll shout the name back to you. Savvy?<br>
> Capt. Barbossa: But that still leaves us with the problem of me standing on some beach with naught but a name and your word it's the one I need.

This document maps out the bootstrapping pipeline of the **Koivu** compiler infrastructure. It uses classic **T-diagrams** to show how the project transitions from an external host dependency (`llc`) to a fully self-hosting compiler.

## 0. How to Read This Document

Three conventions are used throughout, and all three are inherited from other blueprints rather than defined here:

* **Step numbers** follow the four-step build chain in [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 6. That chain starts at the bridge build, so building the seed itself is **Step 0**: a prerequisite, not one of the four steps.
* **Milestone names** (M0 to M4) follow [Backend](backend.md), section 1. A milestone is not a release number; it marks the point at which a particular lowering capability appears.
* **The reference host is Linux `x86_64`.** The diagrams show one platform because the chain is the same on every host. Section 6 adds a second axis - in what form each compiler exists - and section 7 covers the one host, macOS, where the chain takes a different shape. Other per-platform differences are out of scope here.

One distinction is worth stating before the first diagram, because the rest of the document depends on it: what the chain eventually drops is the **`llc` tool**, not the **`.ll` format**. Every Koivu compiler keeps the ability to emit textual LLVM IR permanently, as its primary debugging instrument ([Backend](backend.md), section 1).

### T-Diagram Notation Recap
A compiler T-diagram represents:
* **Left:** The source language being compiled.
* **Right:** The target language produced.
* **Bottom:** The language the compiler itself is written in.

---

## 1. Step 0: Building the Seed (M0)

Before the chain can start, the seed has to exist as a running program. Stage 1 is written directly in **LLVM IR**, and there is no Koivu executable yet, so an external host tool (`llc`) must lower it to target machine code.

```text
       +-----------------------+

       |       Stage 1         |
       |       Source          |
       +-------+       +-------+

               |       |
       +-------+-------+-------+

       |   LLVM   -->  x86_64  |
       |   IR                  |
       +-------+       +-------+

               |       |
               |  llc  |  <--- (External LLVM Static Compiler Executable)
               +-------+
```

* **Input:** the Stage 1 `.ll` sources.
* **Tool running:** external `llc`, plus the platform assembler and linker.
* **Output:** the `koivu-seed` binary.
* **Milestone:** M0. This is pure **bootstrapping via a host compiler**.
* **When it stops:** an external `llc` is required for the seed build until M4, when `koivu-llc` can lower the seed's own IR.

This step produces the tool that runs Step 1, and it is the only step that cannot be eliminated by the project's own progress alone - it is the reason a seed artifact has to be distributed at all.

---

## 2. Step 1: Generating the Bridge Binary (M1 interim, M2 long-term)

With a working `koivu-seed` binary, the seed compiles the Stage 2 bridge source code. Stage 2 introduces hygienic macros; closures are already available in Stage 1, because the bridge is itself written in them.

```text
       +-----------------------+

       |       Stage 2         |
       |       Source          |
       +-------+       +-------+

               |       |
       +-------+-------+-------+

       | Stage 1  -->   LLVM   |
       |  Lisp          IR     |
       +-------+       +-------+

               |       |
               | x86_64|  <--- (Stage 1 Seed binary built in Step 0)
               +-------+
```

* **Input:** Stage 2 bridge source code.
* **Compiler running:** the Stage 1 seed.
* **Intermediate:** `koivu-bridge.ll`, S-LLVM IR emitted by the seed.
* **Output:** the `koivu-bridge` binary.
* **Milestones:** M1 with the interim configuration, M2 with the long-term one.

**Lowering is part of this step, not a separate step after it.** Which tool performs it is the entire content of the milestone difference:

* **M0 to M1 (configuration E, interim):** the emitted `koivu-bridge.ll` is lowered and linked by an external `llc`.
* **From M2 (configuration B, long-term):** the seed executes `simple-codegen` and the container writer itself, so no external tool is involved. This is the point at which the bootstrap goal of [Backend](backend.md), section 1 is met.

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

       | Stage 2  -->   LLVM   |
       |  Lisp          IR     |
       +-------+       +-------+

               |       |
               | x86_64|  <--- (Stage 2 Bridge binary generated in Step 1)
               +-------+
```

* **Input:** Stage 3 source code.
* **Compiler running:** the bridge binary.
* **Intermediate:** `koivu-core.ll`, S-LLVM IR emitted by the bridge.
* **Lowering:** an external `llc` until M4, then `koivu-llc`.
* **Output:** Stage 3 **Version A**.

Version A is the first compiler in the chain that emits machine code, but it was itself lowered externally. Note that the seed's `simple-codegen` does **not** help here: its supported subset covers only the IR emitted for the bridge, never the IR emitted for Stage 3 ([Backend](backend.md), section 4).

---

## 4. Step 3: Native Rebuild (Version B)

Once the native lowering stack exists inside the Stage 3 Scheme source, the project can produce a compiler that is lowered by Koivu itself.

```text
       +-----------------------+

       |       Stage 3         |
       |       Source          |
       +-------+       +-------+

               |       |
       +-------+-------+-------+

       | Stage 3  -->  x86_64  |
       | Scheme                |
       +-------+       +-------+

               |       |
               | x86_64|  <--- (Stage 3 Version A)
               +-------+
```

* **Input:** Stage 3 source code.
* **Compiler running:** Stage 3 **Version A**, which contains the native lowering stack.
* **Intermediate:** none - machine code is emitted directly.
* **Output:** Stage 3 **Version B**.
* **Milestone:** M3.

Version B emits machine code and was built by a compiler that emitted IR and was lowered by an external tool. That one-generation lag is inherent to bootstrapping: a compiler can only use a lowerer it already contains.

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

       | Stage 3  -->  x86_64  |
       | Scheme                |
       +-------+       +-------+

               |       |
               | x86_64|  <--- (Stage 3 Version B)
               +-------+
```

* **Input:** Stage 3 source code.
* **Compiler running:** Stage 3 **Version B**.
* **Output:** Stage 3 **Version C**.
* **Milestone:** M3.

When Version B and Version C are **byte-for-byte identical**, the compiler has reached a fixpoint and stable self-hosting is demonstrated. Three conditions make the check meaningful, and they are stated in [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 6: compare B with C rather than A with B, use the same backend configuration on both sides, and require deterministic emission.

**What this does and does not mean.** The fixpoint is where the *compilers* stop needing an external tool: from Version B onward, each compiler is lowered by the previous one. It is not the point at which `llc` disappears from the project. The seed build (Step 0) and the Version A build (Step 2) keep using an external `llc` until M4, when `koivu-llc` can take over both ([Backend](backend.md), section 1).

Nor does a fixpoint prove trustworthiness. It proves reproducibility and self-consistency; a deliberately planted backdoor would be reproduced perfectly along with everything else. That distinction, and the separate Secure Path that addresses it, belong to [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 8.

---

## 6. The Artifact Axis

The steps above answer *which compiler runs*. A second, independent axis answers *in what form that compiler exists*. The step chain is identical on every host; the form is not, and it is the form that decides what a user has to do before Step 1 can start.

| Step | Compiler that runs | Where that compiler comes from | Form |
| :--- | :--- | :--- | :--- |
| Step 0 | external `llc` | the host toolchain | not a Koivu artifact |
| Step 1 | the seed | **distributed** with the project | committed `.s` on Linux and macOS; published `.exe` on Windows ([Seed Artifacts](08_seed_artifacts.md), section 2) |
| Step 2 | the bridge binary | produced by the seed in Step 1 | native binary, built on the user's machine |
| Steps 3 and 4 | Stage 3 Versions A and B | produced by the previous step | native binary, built on the user's machine |

Only one row of this table is a distribution question. The seed is the only compiler the project ships; everything after it is produced locally, so its form is decided by the platform rather than by the project's release process. The inventory of seed forms, and what each of them proves and does not prove, is in [Seed Artifacts](08_seed_artifacts.md), sections 2 and 4.

The axis matters here rather than in a footnote because the form of the seed is where the Simple and Secure Paths diverge. A user who assembles a committed `.s` file has performed a local build; a user who runs a published `.exe` has not, and relies on inspection instead. Both are supported, and the difference between them is described in [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), sections 4 and 5.

---

## 7. macOS: the Simple Path Platform

macOS is the one host where the chain as drawn is not quite what happens, and the reason belongs in the roadmap rather than only in the platform notes.

Shipping `.s` solves **distribution**, not **execution**. On Apple Silicon the executable that the seed *produces* must also be signed, not only the seed itself. The seed has no Mach-O container writer and no signer, so on macOS Step 1 stops one stage earlier than on Linux and Windows:

* the seed emits assembly text for the bridge;
* the platform assembler, linker and `codesign` finish the job.

This is deliberately the shape of option D in [Backend](backend.md), section 3.3 - the option rejected as the project-wide answer, because it breaks only the LLVM dependency and not the external-tool dependency. On macOS it is chosen anyway: macOS ships `.s` regardless, and the alternative is a Mach-O writer plus an ad-hoc signer inside the seed, which is the opposite of the simplest option ([Platforms and Targets](01_platforms.md), section 6.2).

The consequences for the roadmap, stated plainly:

* **The chain still completes.** Steps 2 to 4 are unchanged: once the platform tools have produced it, the bridge binary is an ordinary native binary.
* **macOS does not reach the bootstrap goal in the near term.** Linux and Windows are expected to reach M2 with the seed lowering and linking the bridge itself; on macOS, Step 1 keeps using platform tools.
* **Whether macOS reaches Steps 3 and 4 is open.** Those steps require Stage 3 to emit a signed Mach-O binary itself, which is the same question as whether a Mach-O container writer is in near-term scope ([Platforms and Targets](01_platforms.md), section 7, question 1).

macOS is therefore a **Simple Path** platform in the sense of [Bootstrapping Paths and Trust](02_bootstrapping_and_trust.md), section 4: supported, bootstrapping, and reliant on platform tools. This does not weaken the other two hosts and does not change the priority order in [Platforms and Targets](01_platforms.md), section 2.
