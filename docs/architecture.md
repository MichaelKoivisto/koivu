# Koivu Compiler Infrastructure Architecture Map

**Status:** Architecture Specification  
**Component:** Global  

This document serves as the top-level index and navigational map for the Koivu Compiler Infrastructure specifications. 

## 1. Core Architectural Layout

The complete technical design is distributed across the following specialized specifications:

| Component | Focus Area | Path |
| :--- | :--- | :--- |
| **01. Platforms and Targets** | Host/target matrices and related engineering priorities. | [docs/architecture/01_platforms.md](./architecture/01_platforms.md) |
| **02. Bootstrapping Paths & Trust** | Simple vs. Secure compiler lineage. | [docs/architecture/02_bootstrapping_and_trust.md](./architecture/02_bootstrapping_and_trust.md) |
| **03. Koivu Scheme** | Core Domain-Specific Language. | [docs/architecture/03_language.md](./architecture/03_language.md) |
| **04. Stage 1 (Seed)** | A minimalist Lisp-1 compiler. | [docs/architecture/04_stage1_seed.md](./architecture/04_stage1_seed.md) |
| **05. Stage 2 (Bridge)** | Macro-expanding compiler written in Stage 1 Lisp. | [docs/architecture/05_stage2_bridge.md](./architecture/05_stage2_bridge.md) |
| **06. Stage 3 (Production Core)** | Final compiler of compilers. | [docs/architecture/06_stage3_production_core.md](./architecture/06_stage3_producton_core.md) |
| **07. Production Compilers** | Frontends for target programming languages. | [docs/architecture/07_frontends.md](./architecture/07_frontends.md) |

---

## 2. Bootstrapping Strategy

Bootstrapping will work in three stages:

* Stage 1 (Seed): A minimalist Lisp-1 compiler written in pure, generic LLVM IR. 
* Stage 2 (Bridge): A macro-expanding compiler written in Stage 1 Lisp. Its only purpose is to compile Stage 3 compiler to machine binary.
* Stage 3 (Production Core): A statically typed, AOT-compiled Scheme dialect executing a highly modular pipeline of ~50 distinct Nanopass transformations.

## 3. Global Structural Principles

All architectural modules must conform to these design priorities:

* **Minimalist Kernel Surface:** The infrastructure must maintain an absolute minimum interface dependency on the host operating system. Builds must be managed by Koivu Scheme scripts. 

Production modules (Stage 3 and onward) must conform to additional design priorities:

* **Cache-Aligned Data Structures:** Tree data structures must be flattened into sequential matrices (Struct of Arrays layout) to optimize memory bandwidth and cache line saturation on prioritized target hardware.
* **Zero Dynamic Garbage Collection:** The execution pipeline must remain completely free of global heap-scanning garbage collection overhead. Components must implement memory strategies native to their lifecycle (Stage 3 enforces Pass-Based Arenas and Fixed-Size Slab Arrays).

