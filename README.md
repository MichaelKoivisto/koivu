# Koivu

*Koivu* is a research project exploring a minimalist, self-hosting, Lisp-driven compiler infrastructure. 

## Project Status

> [!WARNING]
> This is an early-stage research repository. It does not currently contain user-facing utilities, stable APIs, or general-purpose runtime components. 

The project is currently establishing its core bootstrap pipeline layers. It is not open for general runtime use or outside application deployment at this stage.

## Architecture Pipeline

The infrastructure bootstraps and operates via a multi-stage execution model:

1. **Stage 1 (Seed):** A minimal S-expression compiler, written in C before it becomes self-compilable and in Scheme afterwards. It builds Pino IR - an S-expression stack machine - and writes it out as a `.pino` image, with an arena allocator and a no-GC policy. It writes no machine code.
2. **Stage 2 (Sapling):** A macro-expanding compiler built from one source set with the seed's Scheme front end plus a hygienic macro expander. It compiles Stage 3 source to a `.pino` image. Closures are already present in Stage 1, since the sapling itself is written in them.
3. **Stage 3 (Production Core):** A statically typed, ahead-of-time (AOT) compiled dialect of Scheme utilizing a Nanopass architectural design.

`koivu-vesi` is not a stage: it is the Pino lowerer, a tool on the chain. It reads a `.pino` image, verifies it, and writes the executable for a target, or renders the same encoding as assembly. It is the only component in the bootstrap chain that knows what a target is.

## Repository Directory Overview

* `docs/` — [Architecture Blueprints](docs/architecture.md), [Vision](docs/vision.md), and documentation [Style Guide](docs/style-guide.md).
* `bootstrap/` - The bootstrap chain: `stage1/` (the seed), `pino/` (Vesi, the Pino lowerer) and `stage2/` (the macro-expanding sapling), plus the development build scripts that start them.
* `targets/` - Target description data files, read by Vesi.
* `tools/` - Command-line tools outside the bootstrap chain: `koivu-llc`.
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


