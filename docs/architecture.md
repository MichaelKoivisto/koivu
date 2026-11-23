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
| [**Stage 2 (Bridge)**](./architecture/05_stage2_bridge.md) | Macro-expanding compiler written in Stage 1 Lisp. |
| [**Stage 3 (Production Core)**](./architecture/06_stage3_production_core.md) | Final compiler of compilers. |
| [**Production Frontends**](./architecture/07_frontends.md) | Frontends for target programming languages. |
| [**Seed Artifacts**](./architecture/08_seed_artifacts.md) | Seed artifacts, trust levels and verification recipes. |
| [**Self-hosting**](./architecture/selfhosting.md) | Roadmap to self-hosting. |
| [**Data-Oriented Design**](./architecture/data_oriented_design.md) | Data-Oriented Design for compiler passes. |
| [**Backend**](./architecture/backend.md) | IR emission, machine-code lowering, target descriptions, `koivu-llc`. |

---

## Bootstrapping Strategy

Bootstrapping will work in multiple stages:

* Stage 1 (Seed): A minimalist statically typed Lisp-1 compiler written in pure, generic LLVM IR. It will also gain an evaluator, so that it can execute build-time Lisp code (see [Backend](architecture/backend.md), section 3.3). 
* Stage 2 (Bridge): A macro-expanding compiler written in Stage 1 Lisp. Its only purpose is to compile the Stage 3 compiler: it emits LLVM IR, which an external `llc` lowers to a machine binary until `koivu-llc` exists.
* Stage 3 (Production Core): A statically typed, AOT-compiled Scheme dialect executing a highly modular pipeline of ~50 distinct Nanopass transformations.

The **Koivu** project relies heavily on bootstrapping, but this happens in two distinct contexts: during the project's **initial development phase** and later during **end-user installation**.

### Bootstrapping Development (Achieving Self-Hosting)
This is the process the **core developers** use to build the compiler infrastructure from scratch, moving from a foreign host environment to a self-sufficient ecosystem.

* **The Starting Point:** The compiler does not exist yet. Developers write a tiny "seed" compiler (Stage 1) in external LLVM IR and use the system's LLVM toolchain (`llc`) to compile it.
* **The Multi-Stage Bridge:** 
  * Stage 1 compiles the source code of Stage 2 (adding macros).
  * Stage 2 compiles the source code of Stage 3 (the production Scheme dialect).
* **The Goal (Self-Hosting):** Developers write a native machine code backend (e.g., x86_64) directly *in Stage 3 Scheme*. Once Stage 3 can compile its own source code without invoking `llc`, the development bootstrap is complete and a **meta-circular, self-hosting language** is achieved.
* **What is dropped, and what is not:** the LLVM **tool** (`llc`) is dropped. The `.ll` **format** is kept in every stage, permanently, as the primary debugging and interchange format (see [Backend](architecture/backend.md), section 1). A narrower goal is met earlier: the bridge build stops depending on any external tool at M2.

### Bootstrapping the Build (End-User Installation)
Once Koivu is fully self-hosting, **end-users** will need a way to build it from source on their own machines without needing an existing Koivu binary pre-installed. 

* **The Problem:** A self-hosting compiler requires itself to build itself. An end-user downloading the source code only has text files, not the executable binary.
* **The Solution (The Checked-in Seed):** To break this chicken-and-egg problem, the repository distributes a minimized, pre-compiled "bootstrap seed" Lisp compiler alongside the source code.
* **The End-User Build Flow:**
  1. The user downloads the Koivu source code repository.
  2. The build system executes the minimal, pre-baked bootstrap seed.
  3. The seed compiles the Stage 2 bridge source code into a working bridge binary. Until the seed can produce executables by itself, this step is completed by an external `llc` (see [Backend](architecture/backend.md), section 1).
  4. The bridge compiles the Stage 3 Scheme source code into a basic, functioning Koivu compiler binary.
  5. The new compiler recompiles the full source code a second time to generate the optimized, production-ready compiler.

The forms in which the seed is distributed, and what each of them can prove, are described in [Seed Artifacts](architecture/08_seed_artifacts.md).

---

## Global Structural Principles

All architectural modules must conform to these design priorities:

* **Minimalist Kernel Surface:** The infrastructure must maintain an absolute minimum interface dependency on the host operating system. Builds must be managed by Koivu Scheme scripts. 

Seed compiler (Stage 1) must conform to a strict design priority:

* **Auditability & Simplicity:** The compiler's source code and resulting binaries must be transparent in design logic, and auditability outranks footprint: a seed binary slightly larger but simpler to verify is preferable to a smaller opaque one. Size is a ceiling to stay under, not a quantity to minimise. See [Bootstrapping Paths and Trust](architecture/02_bootstrapping_and_trust.md), section 2.

Bootstrap components must conform to one overriding priority:

* **Small Seed Over Small Bridge:** Wherever a trade-off exists between the size and complexity of the Stage 1 seed and the size and complexity of the Stage 2 bridge, the seed always wins. Additional logic belongs in the bridge, in Lisp code evaluated by the seed, or in a later stage. The seed must never grow in order to keep the bridge small. See [Backend](architecture/backend.md), section 3.3, for the configurations this rule decides.

Koivu Scheme compilers (all stages) must conform to a very specific design priority:

* **Maximum Language Expressiveness:**  Stay traditional, dynamic, and macro-rich. Provide maximum cognitive flexibility and clean, expressive notation to reason about code, transform graphs, and manipulate syntax.

Production modules (with the exception of Lisp compilers) must enforce performance-critical design priorities:

* **Cache-Aligned Data Structures:** Tree data structures must be flattened into sequential vector arrays to maximize memory bandwidth utilization 
and optimize cache-line saturation on targeted hardware architectures.
* **Bounded Dynamic Allocation (Low/No-GC):** The execution pipeline must maintain rigid control over runtime memory overhead by prioritizing flat-array layouts 
to eliminate heap-scanning garbage collection costs, defaulting to strict Arena Allocation and No-GC policies wherever practicable.


