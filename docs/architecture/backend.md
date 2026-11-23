# Koivu Backend - IR and Machine-Code Lowering

**Status:** Architecture Blueprint

**Component:** Koivu Backend

> Anamaria: You stole my boat!<br>
> Capt. Jack Sparrow: ...Borrowed! Borrowed without permission. With every intention of bringing it back.<br>

Koivu backend is closely aligned with LLVM backend architecture: it follows the same approach, uses the same or similar formats and similar algorithms in the production pipeline. In the bootstrap stages it deliberately diverges, because there the simplicity of the seed outranks the quality of the generated code.

---

## 0. Scope and Vocabulary

"Backend" in Koivu covers two jobs with opposite directions of translation. This document always states which one is meant.

| Term | Definition |
| :--- | :--- |
| **Pino IR** | S-expression-encoded stack-machine intermediate representation used by Stage 1 and Stage 2. Defined in [Pino IR](pino.md). |
| **Container writer** | The part of Vesi that prepends an OS executable header to the emitted machine code. |
| **LLVM IR** | The textual format defined by the LLVM specifications. The production interchange format of Stage 3 and later. |
| **Emitter** | AST -> text. Turns an in-memory LLVM IR representation into a textual `.ll` file. |
| **Lowerer** | IR -> machine code. |
| **Target Description** | Data describing the target-specific subset of ISA and ABI that a lowerer needs. |
| **`koivu-llc`** | Command-line tool that lowers textual LLVM IR using the production backend libraries. A drop-in replacement for LLVM's `llc`, used outside the bootstrap chain. |
| **`koivu-vesi`** | The Pino lowerer: reads a `.pino` image, verifies it, and writes a target executable, or renders the same encoding as assembly text. In the bootstrap chain; defined in [Koivu Vesi](koivu-vesi.md). |

**Documentation rule:** blueprints do not use the bare word "backend" as a component name. Write "Vesi", "emitter" or "lowerer".

## 1. Two Intermediate Representations

Koivu uses two IRs. The boundary between them is a stage boundary, not a preference.

| | Pino IR | LLVM IR |
| :--- | :--- | :--- |
| **Used by** | Stage 1, Stage 2 | Stage 3 and later |
| **Form** | S-expression stack machine, written out as a canonical `.pino` image ([Pino IR](pino.md)) | Textual `.ll`, a public and documented format |
| **Lowered by** | `koivu-vesi`, from the image the compiler wrote ([Koivu Vesi](koivu-vesi.md)) | `koivu-llc`, or LLVM's own tools |
| **Optimising** | no - one fixed byte template per instruction | yes - full production pipeline |
| **Why** | the seed must be small, must need no register allocator, and must produce machine code whose correspondence to the source is mechanically checkable | Stage 3 is a production compiler and needs real optimisation |

The stack machine is what makes the bootstrap tractable: with an implicit operand stack there is no register allocation, no instruction scheduling and no spilling, so lowering is a single linear pass over a fixed set of byte templates. That is also what makes the result auditable, which is the priority recorded in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2.

### Bootstrap Goals

Two distinct goals, reached at different milestones:

1. **The sapling build must not depend on any external tool** - no `llc`, no assembler, no linker, and no build system beyond the thin OS script that starts the seed and Vesi. `koivu-vesi` is a Koivu artifact, not an external tool. Met at **M0**.
2. **The seed build must not depend on any external tool** - the seed can be rebuilt from its own source by a Koivu compiler produced by the chain. Met at **M2**.

Goal 1 is the bootstrap goal proper. Goal 2 is what moves the seed from early to late development and allows a public seed release.

### Milestones

A milestone marks the point at which a lowering capability appears. It is not a release number.

| Milestone | What works | External tools still needed |
| :--- | :--- | :--- |
| **M0** | The C seed compiles the sapling source to an image; Vesi lowers it; the sapling binary runs | a C compiler, to build the seed and Vesi |
| **M1** | The sapling compiles Stage 3 source to an image; Vesi lowers it; Version A runs | a C compiler, to build the seed and Vesi |
| **M2** | A Koivu compiler produced by the chain rebuilds the seed and Vesi from their Scheme sources; the C scaffold is retired | none, given an existing Koivu compiler |
| **M3** | Version A compiles Stage 3 source to Version B, emitting machine code natively | none |
| **M4** | Version B produces a byte-identical Version C | none |

M2 is the milestone that matters most outside this document: it is the boundary between early and late development defined in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2, and therefore the point from which machine-code auditability outranks everything else.

## 2. The Pino Lowerer

Lowering is a **program**, not a library: `koivu-vesi`, defined in [Koivu Vesi](koivu-vesi.md). Nothing links it in, and it has a command-line interface of its own.

| Property | Value |
| :--- | :--- |
| **Direction** | `.pino` image -> machine code -> executable |
| **Input** | one image file per program |
| **Output** | an executable for the selected target, or the same encoding as `.s` |
| **Available from** | M0 |
| **Consumers** | none - it is run, not linked |
| **Implementation** | C until M2, Scheme afterwards |

What it contains:

* the `.pino` reader, and the static stack-balance verifier that runs before any byte is emitted;
* the instruction encoder - one fixed byte template per Pino instruction per target;
* the label table and the backpatch resolver;
* the container writer (section 5);
* target descriptions (section 6).

What it deliberately does not contain:

* no type checking, no scope resolution and no control-flow synthesis - those belong to a front end and are finished before an image exists;
* no register allocator - the operand stack is the register file;
* no instruction scheduler;
* no peephole pass;
* no IR-to-IR transformation of any kind;
* no macro expander;
* no linker and no object-file format - Koivu has no separate compilation (section 9, decision 12).

**Why a program and not a library.** A library would have to be linked into each compiler that emits Pino, which puts the encoder, the container writer and the target descriptions inside every front end and makes each of them target-specific. As a program, the front end needs none of that and becomes one artifact for every host. The full argument, including the cost, is in [Koivu Vesi](koivu-vesi.md), section 1.

**Behaviour on unsupported input:** a hard, explicit error. Silent miscompilation is forbidden.

## 3. Where the Lowering Code Runs

Lowering runs in `koivu-vesi`, outside every compiler in the chain. Neither the seed nor the sapling contains an encoder, a container writer or a target description: they read Scheme, build Pino IR, write an image and stop.

* **Stage 1.** The seed reads Scheme, builds Pino IR and writes `koivu-sapling.pino`. Vesi lowers that image to the sapling executable.
* **Stage 2.** The sapling does the same, with a larger front end: hygienic macros and `flat-vector` become available. Its image is lowered by the same Vesi.

Two consequences follow, and both are deliberate:

* **No evaluator.** Nothing in the seed interprets Scheme at build time. The seed is a compiler and nothing else. This is a substantial reduction compared with a design in which the seed evaluates its own backend.
* **One lowering implementation, in one place.** There is no in-process copy to keep in step with a second one, and no compiler can disagree with Vesi about what an instruction means, because there is only Vesi. It is still written twice - C before M2, Scheme after - but that is the same single rewrite the seed goes through, and it is closed by the same kind of criterion: the C version and the Scheme version must produce identical output, checked over the whole test suite (section 8, criterion 9).

The seed's implementation language is a staged decision described in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2.

## 4. Pino ISA Conformance

Pino IR is a fixed instruction set, so conformance is a membership test rather than a subset closure:

> **ISA invariant:** every instruction emitted by Stage 1 and by Stage 2 belongs to the declared Pino ISA, and every instruction has a lowering for every supported target.

This is a build-time, machine-checked requirement, not a review guideline.

### Conformance test (required)

1. Compile the sapling sources with the seed, capturing the emitted `.pino` image.
2. Compile the Stage 3 sources with the sapling, capturing the emitted image.
3. Check that every instruction in both images is in the declared ISA and has a template for each supported target.
4. Fail the build otherwise.

The test belongs to the regression suites of Stage 1 and Stage 2. Its purpose is to prevent a front-end change from introducing an instruction that Vesi cannot lower.

### Explicitly out of scope

* Lowering LLVM IR. Nothing in the bootstrap chain reads or writes `.ll`; that is Stage 3's business.
* Optimisation. Vesi has none, and none is planned.

## 5. Container Writers

Vesi writes the executable container itself, so no compiler in the chain needs an assembler and no build needs a linker.

| Target | Format | Notes |
| :--- | :--- | :--- |
| Linux `x86_64` | ELF64 | near term |
| Windows `x86_64` | PE32+ | near term |
| macOS `arm64` | Mach-O | near term; written unsigned, see below |

Resolved decision: all three formats are in scope and none is deferred. Vesi writes every container unsigned.

**Vesi writes containers; it does not sign them.** Mach-O is the one format that carries a signing requirement on the target platform, and the two jobs separate cleanly: the emitter writes an unsigned container, and the user ad-hoc signs the result with `codesign --force --sign -`, which needs no certificate, no developer account and no network. A code directory and a superblob inside Vesi would be a second binary format to implement and audit, bought for no gain. Raw syscalls are not a stable interface on macOS, so the Mach-O path links against `libSystem` ([Platforms and Targets](01_platforms.md), section 6.1).

## 6. Target Descriptions

Target descriptions are stored as Scheme source files. They are a **subset** of what LLVM target definitions provide, not a clone.

| Kind | Used by | Scope | Milestone |
| :--- | :--- | :--- | :--- |
| **Pino target description** | Vesi | the byte template for each Pino instruction, plus the ABI facts the container writer needs | M0 |
| **Production target description** | production code generator, `koivu-llc` | full instruction set required by the production pipeline | M3 |

Adding a target means writing a Pino target description - one template per instruction, and a container writer for its format. The step-by-step procedure is described in [Platforms and Targets](01_platforms.md).

## 7. Production Backend

Everything in this section belongs to Stage 3 and later. None of it is in the seed or the sapling.

### 7.1 Production LLVM IR Emitter

Stage 3 and other production compilers emit LLVM IR via `(koivu backend syntax llvm-ir)`, using the `flat-ast-llvm-ir` in-memory scheme. Emitting `.ll` is a permanent capability: a textual IR dump is the primary debugging instrument for a compiler infrastructure, and it is never removed, including after full self-hosting.

### 7.2 Production Lowering Stack

* `(koivu backend analysis)` - computes program information (dominance trees, scalar evolution, alias analysis) without altering the IR.
* `(koivu backend transforms)` - the transform passes: dead code elimination, loop unrolling, inlining, vectorisation, interprocedural optimisation.
* `(koivu backend codegen)` - target-independent code generation, including `CodeGenPrepare`.
* `(koivu backend machine-code-layer)` - emission of assembly-level constructs: labels, sections, raw target instructions.

### 7.3 `koivu-llc`

`koivu-llc` (`koivu-llc.exe` on Windows) is a command-line tool built on the production lowering stack with a thin CLI shim.

* **Purpose:** a drop-in replacement for LLVM's `llc` for the IR subset Koivu emits.
* **Placement:** **outside the bootstrap chain.** The seed and the sapling never lower LLVM IR, because they lower Pino. `koivu-llc` exists for Stage 3's textual output, for the multi-language frontends planned on top of Stage 3, and for the wider set of LLVM-like tools the project intends to maintain.
* **Milestone:** not tied to a bootstrap milestone. It depends on the production lowering stack (M3) and is scheduled independently.
* **Input format:** textual `.ll`. A drop-in `llc` replacement must read textual LLVM IR, which implies an LLVM IR parser in the production stack. The cost of that parser is analysed in [Parsing LLVM IR in Koivu Scheme](notes_on_llvm_ir_parsing.md). The parser is never part of the seed.

**The production stack is a library before it is a tool.** `koivu-llc` is one client of it; a build program written in Koivu Scheme is another. Because Stage 3 is written in the language it compiles, a build program can be compiled together with the production stack and then call it directly. That is why Koivu needs no `(compile ... into ...)` form: in Stage 3, compiling is an ordinary function call, and a front-end directive that duplicated it would be a second way to say the same thing. The seed and the sapling are not in that position - neither can be reached from Scheme code - which is why their build is driven by a data manifest instead ([Stage 1 (Seed)](04_stage1_seed.md), section 7).

## 8. Acceptance Criteria

1. **ISA conformance:** the invariant of section 4 is checked automatically in CI, for both Stage 1 and Stage 2.
2. **Container validity:** executables produced by Vesi run on their target with no external assembler, linker or system toolchain.
3. **No external tool in the sapling build:** from M0, the sapling build invokes nothing outside the seed and Vesi.
4. **Determinism:** Pino lowering and container writing are deterministic - stable ordering, no timestamps, no absolute paths - because the self-hosting fixpoint check compares binaries byte-for-byte.
5. **Seed self-compilation equivalence:** from M2, a seed rebuilt from Scheme source by a Koivu compiler behaves identically to the seed built by the C scaffold across the full test suite. This is the criterion that retires the C seed.
6. **Fixpoint:** Version B and Version C are byte-for-byte identical.
7. **Mechanical auditability:** the mapping from Pino IR to emitted bytes is fixed and can be checked by a tool, so a distributed seed binary can be verified against the Pino source it was lowered from.
8. **`koivu-llc` parity:** for the supported subset, `koivu-llc` output passes the same tests as `llc` output.
9. **Lowerer equivalence:** the C and the Scheme implementation of Vesi produce byte-identical output for every image in the test suite. This is the criterion that retires the C version at M2.

## 9. Decisions

| # | Decision | Resolution | Consequence |
| :--- | :--- | :--- | :--- |
| 1 | IR used by Stage 1 and Stage 2 | **Pino IR only** | no LLVM IR anywhere in the bootstrap chain |
| 2 | IR used by Stage 3 and later | **LLVM IR** | `.ll` emission is permanent and is never removed |
| 3 | Pino compiler: library or tool? | **Program**, `koivu-vesi`, run by the build and never linked into a compiler | the front end stays portable and target-independent, at the cost of two artifacts per host instead of one; reasoning and rejected alternatives in [Koivu Vesi](koivu-vesi.md), section 1 |
| 4 | Seed implementation language | **C until M2, Scheme afterwards**; the C source is deleted, not maintained | no permanent mirror; the two versions of the seed overlap only between M1 and M2, and criterion 5 closes that window. Vesi goes through the same rewrite, closed by criterion 9 |
| 5 | Does the seed contain an evaluator? | **No** | the seed is a compiler and nothing else |
| 6 | `koivu-llc` input format | **Textual `.ll`** (true drop-in) | the production stack needs an LLVM IR parser, see [notes](notes_on_llvm_ir_parsing.md); the parser is never part of the seed |
| 7 | `koivu-llc` placement | **Outside the bootstrap chain** | it serves Stage 3, the planned frontends and LLVM-like tooling, not the seed or the sapling |
| 8 | Executable container formats | **All three: ELF, PE and Mach-O, none deferred** | Vesi writes every container unsigned; signing is a user step, see section 5 |
| 9 | Bootstrap goal 1 | **The sapling build must not depend on any external tool** | met at M0 |
| 10 | Bootstrap goal 2 | **The seed build must not depend on any external tool** | met at M2; this is the early/late boundary |
| 11 | Stage 1 closure representation | **Chained frames: `closure = { code_ptr, env_ptr }`, frames linked by a parent pointer, variable access by a compile-time `(depth, index)` pair** | no free-variable analysis and no copying at closure creation; `set!` on captured variables is allowed and shares state; environments live in the arena, so no GC is needed |
| 12 | Compilation model | **Whole-program only: no separate compilation, no object files, no linker.** A compilation starts from one root source and produces one image, which Vesi lowers to one executable | further files enter through `include`, textually, at read time ([Koivu Scheme](03_language.md), Multi-File Programs); producing several executables is a loop over programs, not a compiler mode |
| 13 | Program entry point | **A top-level procedure `main` of arity 0, whose return value is the exit status**; the executable's startup stub calls it | a program with no `main` or two is a build error; arguments are read through primitives instead of being passed as a list, so nothing is allocated before `main` runs ([Koivu Scheme](03_language.md), Program Entry Point) |
| 14 | Build description | **`build.koivu`, a manifest read as data by the compiler**, listing programs and their root sources | no executable build script and no ordering, because `include` encodes the program and the compiler has no evaluator ([Stage 1 (Seed)](04_stage1_seed.md), section 7) |

No decisions are currently open. The release policy that was the last open question outside this document is settled as well: every release publishes a binary for every supported platform ([Platforms and Targets](01_platforms.md), section 2).
