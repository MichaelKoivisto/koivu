# Koivu

*Koivu* is a research project exploring a minimalist, self-hosting, Lisp-driven compiler infrastructure. 

## Project Status

> [!WARNING]
> This is an early-stage research repository. It does not currently contain user-facing utilities, stable APIs, or general-purpose runtime components. 

The project is currently establishing its core bootstrap pipeline layers. It is not open for general runtime use or outside application deployment at this stage.

## Architecture Pipeline

The infrastructure bootstraps and operates via a multi-stage execution model:

1. **Stage 1 (Seed):** A minimal S-expression compiler written in LLVM IR, relying on Arena Allocator and No-GC policy.
2. **Stage 2 (Bridge):** A macro-expanding compiler written in Stage 1 Lisp, adding support for hygienic macros and structured lexical closures.
3. **Stage 3 (Production Core):** A statically typed, ahead-of-time (AOT) compiled dialect of Scheme utilizing a Nanopass architectural design and `flat-vector` Intermediate Representations.

## Repository Directory Overview

* `docs/` — [Architecture Blueprints](docs/architecture.md), [Vision](docs/vision.md), and documentation [Style Guide](docs/style-guide.md).
* `bootstrap/` - Initial self-hosting environments (Assembly interpreter seed and macro-expansion bridges).
* `src/` - Stage 3 production infrastructure.
  * `frontends/` - AST generation targets (including structural interfaces for C/C++).
  * `midend/` - Tree-walking optimization modules and pattern-matching engines.
  * `backends/` - Linear scan register allocation and target machine code emitters.
* `runtime/` - Data-oriented allocation systems (Pass-Based Arenas and Fixed-Size Object Pools).
* `tests/` - Internal regression suites and megafile compilation testing.

## License

This project is licensed under the Apache License v2.0 with LLVM Exceptions. See the `LICENSE` file for details.

## AI Disclosure

AI disclosure: see [AI_DISCLOSURE.md](AI_DISCLOSURE.md). This project uses AI-generated human-reviewed code and documentation.


