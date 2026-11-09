# Koivu Compiler Infrastructure Architecture Map

**Status:** Architecture Blueprint  
**Component:** Global  

This document serves as the top-level index and navigational map for the Koivu Compiler Infrastructure specifications. 

## 1. Core Architectural Layout

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

