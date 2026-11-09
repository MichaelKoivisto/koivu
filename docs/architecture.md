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
| [**Self-hosting**](./architecture/selfhosting.md) | Roadmap to self-hosting. |
| [**Koivu Scheme**](./architecture/03_language.md) | Core Domain-Specific Language. |
| [**Stage 1 (Seed)**](./architecture/04_stage1_seed.md) | A minimalist Lisp-1 compiler. |
| [**Stage 2 (Bridge)**](./architecture/05_stage2_bridge.md) | Macro-expanding compiler written in Stage 1 Lisp. |
| [**Stage 3 (Production Core)**](./architecture/06_stage3_production_core.md) | Final compiler of compilers. |
| [**Data-Oriented Design**](./architecture/data_oriented_design.md) | Data-Oriented Design for compiler passes. |
| [**Backend**](./architecture/backend.md) | Backend: emission of LLVM IR, optimizations, lowering. |
| [**Production Frontends**](./architecture/07_frontends.md) | Frontends for target programming languages. |

---

## Bootstrapping Strategy

Bootstrapping will work in multiple stages:

* Stage 1 (Seed): A minimalist statically typed Lisp-1 compiler written in pure, generic LLVM IR. 
* Stage 2 (Bridge): A macro-expanding compiler written in Stage 1 Lisp. Its only purpose is to compile Stage 3 compiler to machine binary.
* Stage 3 (Production Core): A statically typed, AOT-compiled Scheme dialect executing a highly modular pipeline of ~50 distinct Nanopass transformations.

The **Koivu** project relies heavily on bootstrapping, but this happens in two distinct contexts: during the project's **initial development phase** and later during **end-user installation**.

### Bootstrapping Development (Achieving Self-Hosting)
This is the process the **core developers** use to build the compiler infrastructure from scratch, moving from a foreign host environment to a self-sufficient ecosystem.

* **The Starting Point:** The compiler does not exist yet. Developers write a tiny "seed" compiler (Stage 1) in external LLVM IR and use the system's LLVM toolchain (`llc`) to compile it.
* **The Multi-Stage Bridge:** 
  * Stage 1 compiles the source code of Stage 2 (adding macros and closures).
  * Stage 2 compiles the source code of Stage 3 (the production Scheme dialect).
* **The Goal (Self-Hosting):** Developers write a native machine code backend (e.g., x86_64) directly *in Stage 3 Scheme*. Once Stage 3 can compile its own source code without invoking LLVM, the development bootstrap is complete. The external LLVM scaffolding is dropped, creating a **meta-circular, self-hosting language**.

### Bootstrapping the Build (End-User Installation)
Once Koivu is fully self-hosting, **end-users** will need a way to build it from source on their own machines without needing an existing Koivu binary pre-installed. 

* **The Problem:** A self-hosting compiler requires itself to build itself. An end-user downloading the source code only has text files, not the executable binary.
* **The Solution (The Checked-in Seed):** To break this chicken-and-egg problem, the repository distributes a minimized, pre-compiled "bootstrap seed" Lisp compiler alongside the source code.
* **The End-User Build Flow:**
  1. The user downloads the Koivu source code repository.
  2. The build system executes the minimal, pre-baked bootstrap seed.
  3. This seed reads the Stage 3 Scheme source code and uses it to compile a basic, functioning Koivu compiler binary.
  4. The newly compiled binary then recompiles the full source code a second time to generate the optimized, production-ready compiler.

---

## Global Structural Principles

All architectural modules must conform to these design priorities:

* **Minimalist Kernel Surface:** The infrastructure must maintain an absolute minimum interface dependency on the host operating system. Builds must be managed by Koivu Scheme scripts. 

Seed compiler (Stage 1) must conform to a unique design priority:

* **Simplicity:** Seed's source code (and resulting binaries) should be minimal in size and simple in design and logic, 
to facilitate human review and inspection of both source code and binaries.

Production modules (Stage 3 and onward) must conform to additional design priorities:

* **Cache-Aligned Data Structures:** Tree data structures must be flattened into sequential arrays to optimize memory bandwidth and cache line saturation on prioritized target hardware.
* **Minimum Dynamic Garbage Collection:** The execution pipeline must maintain precise control on global heap-scanning garbage collection overhead, going as far as No-GC policy when reasonable. Majority of data must live in flat arrays to minimize the number of entities requiring garbage collection. 



