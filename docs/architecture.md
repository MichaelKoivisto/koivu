# Koivu Compiler Infrastructure Architecture Map

**Status:** Architecture Blueprint  

**Component:** Global  

This document serves as the top-level index and navigational map for the Koivu Compiler Infrastructure specifications. 

---

## Core Architectural Layout

The complete technical design is distributed across the following specialized documents:

| Component | Focus Area |
| :--- | :--- |
| [**Platforms and Targets**](./architecture/01_platforms.md) | Host/target matrices and related engineering priorities. |
| [**Bootstrapping Paths & Trust**](./architecture/02_bootstrapping_and_trust.md) | Simple vs. Secure compiler lineage. |
| [**Koivu Scheme**](./architecture/03_language.md) | Core Domain-Specific Language. |
| [**Stage 1 (Seed)**](./architecture/04_stage1_seed.md) | A minimalist Lisp-1 compiler. |
| [**Stage 2 (Sapling)**](./architecture/05_stage2_sapling.md) | Macro-expanding compiler written in Stage 1 Lisp. |
| [**Stage 3 (Production Core)**](./architecture/06_stage3_production_core.md) | Final compiler of compilers. |
| [**Production Frontends**](./architecture/07_frontends.md) | Frontends for target programming languages. |
| [**Seed Artifacts**](./architecture/08_seed_artifacts.md) | Seed artifacts, trust levels and verification recipes. |
| [**Self-hosting**](./architecture/selfhosting.md) | Roadmap to self-hosting. |
| [**Data-Oriented Design**](./architecture/data_oriented_design.md) | Data-Oriented Design for compiler passes. |
| [**Pino IR**](./architecture/pino.md) | The bootstrap IR: instruction set, data layout, and the `.pino` image format. |
| [**Backend**](./architecture/backend.md) | IR emission, machine-code lowering, target descriptions, `koivu-llc`. |
| [**Koivu Vesi**](./architecture/koivu-vesi.md) | The Pino lowerer: the `.pino` interface, instruction encoding, containers, and the chain's per-host artifact. |
| [**Seed Sizes**](./architecture/notes_on_seed_sizes.md) | Developer note: how large compiler seeds are in comparable chains, and why those figures are not directly comparable. |

---

## Bootstrapping Strategy

Bootstrapping will work in multiple stages:

* Stage 1 (Seed): A minimalist statically typed Lisp-1 compiler. It is written in C before M2 and in Scheme afterwards, builds Pino IR and prints it as a `.pino` image; `koivu-vesi` lowers that image to machine code and writes the executable container. The seed therefore carries no instruction encoder, no container writer and no target description, and it contains no evaluator: it is a compiler and nothing else (see [Koivu Vesi](architecture/koivu-vesi.md), section 1). 
* Stage 2 (Sapling): A macro-expanding compiler written in Stage 1 Lisp. Its only purpose is to compile the Stage 3 compiler: it builds Pino IR and prints it as a `.pino` image, which `koivu-vesi` lowers exactly as it lowers the seed's, so no external tool is involved.
* Stage 3 (Production Core): A statically typed, AOT-compiled Scheme dialect executing a highly modular pipeline of ~50 distinct Nanopass transformations.

The **Koivu** project relies heavily on bootstrapping, but this happens in two distinct contexts: during the project's **initial development phase** and later during **end-user installation**.

### Bootstrapping Development (Achieving Self-Hosting)
This is the process the **core developers** use to build the compiler infrastructure from scratch, moving from a foreign host environment to a self-sufficient ecosystem.

* **The Starting Point:** The compiler does not exist yet. Developers write the seed (Stage 1) in C and build it with an external C compiler - the only external tool the project ever uses ([Bootstrapping Paths & Trust](architecture/02_bootstrapping_and_trust.md), section 2).
* **The Multi-Stage Sapling:** 
  * Stage 1 compiles the source code of Stage 2 (adding macros).
  * Stage 2 compiles the source code of Stage 3 (the production Scheme dialect).
* **The Goal (Self-Hosting):** Developers write a native machine code backend (e.g., x86_64) directly *in Stage 3 Scheme*. Once Stage 3 can compile its own source code without invoking any external tool, the development bootstrap is complete and a **meta-circular, self-hosting language** is achieved.
* **What is dropped, and what is not:** two different things are dropped, at different times. The **external C compiler** that builds the seed is dropped at M2, when a Koivu compiler produced by the chain can rebuild the seed from its own source. The **`llc` tool** is never in the chain to begin with: Stages 1 and 2 use Pino IR rather than LLVM IR, and that IR is lowered by `koivu-vesi`, which is Koivu's own program rather than an external tool. The `.ll` **format** survives permanently, but only in Stage 3, as its debugging instrument and as `koivu-llc`'s input (see [Backend](architecture/backend.md), sections 1 and 7). The first bootstrap goal - the sapling build depending on no external tool - is met at M0.

### Bootstrapping the Build (End-User Installation)
Once Koivu is fully self-hosting, **end-users** will need a way to build it from source on their own machines without needing an existing Koivu binary pre-installed. 

* **The Problem:** A self-hosting compiler requires itself to build itself. An end-user downloading the source code only has text files, not the executable binary.
* **The Solution (The Distributed Seed):** To break this chicken-and-egg problem, the project publishes a minimized, pre-built seed compiler for each host alongside the source code. Binaries are published, not committed; the assembly of the same seed is committed as a convenience for readers, never as a build input ([Seed Artifacts](architecture/08_seed_artifacts.md), sections 2 and 3).
* **The End-User Build Flow:**
  1. The user downloads the Koivu source code repository.
  2. The build system executes the minimal, pre-baked bootstrap seed.
  3. The seed compiles the Stage 2 sapling source code into a working sapling binary. It lowers Pino IR and writes the executable container itself, so no external tool appears in this step (see [Backend](architecture/backend.md), section 1).
  4. The sapling compiles the Stage 3 Scheme source code into a basic, functioning Koivu compiler binary.
  5. The new compiler recompiles the full source code a second time to generate the optimized, production-ready compiler.

The forms in which the seed is distributed, and what each of them can prove, are described in [Seed Artifacts](architecture/08_seed_artifacts.md).

---

## Global Structural Principles

All architectural modules must conform to these design priorities:

* **Minimalist Kernel Surface:** The infrastructure must maintain an absolute minimum interface dependency on the host operating system. Build orchestration is Koivu's own job - **Koivu must be able to build its multi-file sources with Koivu** - and it is never delegated to a build system: no makefiles, no CMake, no Visual Studio projects, no Python or Perl scripts, no secondary compiler toolchain. Each of those is an unaudited dependency in the build of a compiler whose entire purpose is to have none.

  Multi-file means whole-program, and the files are joined by `include` in the source rather than by a command line: a program has one root source, the reader splices the rest into it, and there is no separate compilation, no object files and no linker ([Koivu Scheme](architecture/03_language.md); [Backend](architecture/backend.md), section 9, decision 12).

  Thin OS scripts are the one exception, and only where the host leaves no alternative: a `.sh` or `.cmd` file may start the first binary, or reach the external C compiler before M2, because every supported OS ships a shell and nothing smaller is guaranteed. The line is between **invoking** and **deciding**. A script may select sources and run one program; as soon as it decides what to build, in what order, or with which flags, it has become a build tool, and a build tool written in shell is an external dependency with extra steps. See [Stage 1 (Seed)](architecture/04_stage1_seed.md), section 7.

Seed compiler (Stage 1) must conform to a strict design priority:

* **Auditability & Simplicity:** The compiler's source code and resulting binaries must be transparent in design logic, and auditability outranks footprint: a seed binary slightly larger but simpler to verify is preferable to a smaller opaque one. Size is a ceiling to stay under, not a quantity to minimise. See [Bootstrapping Paths and Trust](architecture/02_bootstrapping_and_trust.md), section 2.

Bootstrap components must conform to one overriding priority:

* **Small Seed Over Small Sapling:** Wherever a trade-off exists between the size and complexity of the Stage 1 seed and the size and complexity of the Stage 2 sapling, the seed always wins. Additional logic belongs in the sapling or in a later stage; nothing is delegated to Lisp code evaluated by the seed, because the seed contains no evaluator. The seed must never grow in order to keep the sapling small. See [Backend](architecture/backend.md), section 3.

Koivu Scheme compilers (all stages) must conform to a very specific design priority:

* **Maximum Language Expressiveness:**  Stay traditional, dynamic, and macro-rich. Provide maximum cognitive flexibility and clean, expressive notation to reason about code, transform graphs, and manipulate syntax.

Production modules (with the exception of Lisp compilers) must enforce performance-critical design priorities:

* **Cache-Aligned Data Structures:** Tree data structures must be flattened into sequential vector arrays to maximize memory bandwidth utilization 
and optimize cache-line saturation on targeted hardware architectures.
* **Bounded Dynamic Allocation (Low/No-GC):** The execution pipeline must maintain rigid control over runtime memory overhead by prioritizing flat-array layouts 
to eliminate heap-scanning garbage collection costs, defaulting to strict Arena Allocation and No-GC policies wherever practicable.


