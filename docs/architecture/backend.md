# Koivu Backend - IR Emission and Machine-Code Lowering

**Status:** Architecture Blueprint

**Component:** Koivu Backend

> Anamaria: You stole my boat!<br>
> Capt. Jack Sparrow: ...Borrowed! Borrowed without permission. With every intention of bringing it back.<br>

Koivu backend is closely aligned with LLVM backend architecture: follows the same approach, uses the same or similar formats and similar algorithms.

---

## 0. Scope and Vocabulary

"Backend" in Koivu covers two different jobs with opposite directions of translation. Confusing them has already caused ambiguity in the blueprints, so this document always states which one is meant.

| Term | Definition |
| :--- | :--- |
| **S-LLVM IR** | In-memory generic LLVM IR abstract syntax tree, conforming to the [`ast-s-llvm-ir-` schema](ast-s-llvm-ir.md) and written in Koivu S-Expression LLVM IR syntax. |
| **Emitter** | AST -> text. Turns S-LLVM IR into a textual `.ll` file. |
| **Lowerer** | IR -> machine code. Turns LLVM IR into target assembly, an object file, or an executable. |
| **Target Description** | Scheme data describing the target-specific subset of ISA and ABI that a lowerer needs. |
| **Simple Target Description** | Minimal target description covering only the instructions the Stage 1 seed can emit. |
| **Production Target Description** | Full target description used by the production code generator. |
| **`koivu-llc`** | Command-line tool that lowers LLVM IR to machine code using the production backend libraries. Intended as a drop-in replacement for LLVM's `llc`. |

**Documentation rule:** blueprints do not use the bare word "backend" as a component name. Write "emitter" or "lowerer".

## 1. The Two LLVM Dependencies

Koivu has two independent relationships with LLVM. They are resolved at different milestones and must not be described as a single "LLVM dependency".

| Dependency | What it is | Resolution | Status after resolution |
| :--- | :--- | :--- | :--- |
| **LLVM IR as an interchange format** | `.ll` / S-LLVM IR as the artifact passed between stages | **Permanent by design** | Retained in all stages, forever |
| **LLVM's `llc` as a lowering tool** | External program that turns IR into machine code | Replaced by `koivu-llc` | Removed at late stages of development |

Emitting `.ll` is never removed from any Koivu compiler, including after the project is fully self-hosting. A textual IR dump is the primary debugging instrument for a compiler infrastructure, and Koivu is a long-term, always-evolving project: an IR emission option will remain useful even when the seed, the full backend and the production frontends are all implemented.

The `.ll` sources of the Stage 1 seed remain the canonical, human-auditable form of the seed. Derived artifacts (assembly, binaries) are described in [Seed Artifacts](08_seed_artifacts.md).

### Bootstrap Goal

The project goal is: **the bridge build must not depend on any external tool.** This is stronger than "no LLVM" - it excludes `llc`, the system assembler and the linker alike.

The goal is met at M2, when the seed executes the lowerer and the container writer itself. Until then, an external `llc` is the accepted interim path.

### Milestones

| Milestone | Stage 1 emitter | `simple-codegen` | `koivu-llc` | External `llc` still required for |
| :--- | :--- | :--- | :--- | :--- |
| **M0** | emits `.ll` | - | - | seed build, bridge build |
| **M1** | emits `.ll` | - | - | seed build, bridge build, Stage 3 Version A build |
| **M2** | emits `.ll` | executed by the seed | - | seed build, Stage 3 Version A build |
| **M3** | emits `.ll` | executed by the seed | - | seed build, Stage 3 Version A build (production backend appears, fixpoint reached) |
| **M4** | emits `.ll` | executed by the seed | available | nothing |

M3 marks the arrival of the production lowering stack inside Stage 3: Version A builds Version B natively, and the fixpoint check is performed (see [Roadmap to Self-hosting](selfhosting.md)). M4 marks `koivu-llc` as a shipped command-line replacement for `llc`.

Because the seed itself executes the lowerer and the container writer (resolved decision 7), the bridge build stops depending on an external `llc` at M2, which is where the bootstrap goal is met. M0 and M1 use the interim configuration E.

## 2. Backend Library and Tool Inventory

| Library / Tool | Direction | Input | Output | Available from | Implementation | Consumers |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `(koivu backend s-llvm-ir)` | AST -> text | S-LLVM IR AST (`ast-s-llvm-ir-`) | `.ll` file | M0 | hand-written `.ll` inside the seed; Scheme from Stage 2 up | `koivu-seed`, `koivu-bridge` |
| `(koivu backend simple-codegen)` | AST -> machine code | in-memory S-LLVM IR AST emitted by Stage 1 when compiling the bridge | machine code for the target | M2 | Stage 1 Lisp, executed by the seed | `koivu-seed` |
| container writer | machine code -> executable | machine code plus a target description | linked executable (ELF, PE or Mach-O) | M2 | Stage 1 Lisp, executed by the seed | `koivu-seed` |
| `(koivu backend syntax llvm-ir)` | AST -> text | `flat-ast-llvm-ir-` | `.ll` file | M3 | Scheme | Stage 3, `koivu-llc` |
| `(koivu backend analysis)` | IR analysis | IR | IR plus analysis metadata | M3 | Scheme | production pipeline |
| `(koivu backend transforms)` | IR -> IR | IR | IR | M3 | Scheme | production pipeline |
| `(koivu backend codegen)` | IR -> machine-ready IR | IR | machine-ready IR | M3 | Scheme | production pipeline |
| `(koivu backend machine-code-layer)` | machine-ready IR -> machine code | machine-ready IR | assembly or object code | M3 | Scheme | Stage 3, `koivu-llc` |
| `koivu-llc` (tool) | textual `.ll` -> machine code, command line | textual `.ll` file | assembly or object code | M4 | Scheme: production libraries, an LLVM IR parser and a CLI shim | build system, end users |

## 3. Stage 1 Backend

The Stage 1 backend consists of exactly two components. They differ not only in function but in **where they run**: the emitter runs inside the seed, the lowerer runs inside the bridge.

### 3.1 Simple IR Emitter (M0)

The absolute minimum backend: it takes the S-LLVM IR data structures held in Stage 1 compiler memory and prints a correct textual representation of them into a `.ll` file. It does not parse LLVM IR, does not transform it and does not know anything about targets.

* **Contract:** it must be able to print every IR form that Stage 1 can produce when compiling Lisp sources for the Stage 2 bridge.
* **Input:** S-LLVM IR AST, built by the front end as plain Lisp data structures.
* **Output:** a single `.ll` file, ready to be lowered by an external `llc`.
* **Implementation:** a deliberate mirror (resolved decision 5). Inside the seed the emitter is hand-written LLVM IR; from Stage 2 up the same behaviour is provided as an actual Scheme library. Both implementations must produce identical `.ll` for the same S-LLVM IR AST, which is checked by the release criterion in section 8.

### 3.2 Simple Code Generator (M2)

The `(koivu backend simple-codegen)` library does naive lowering of LLVM IR to target machine code. It performs no IR transformations and no target-aware optimizations; lowering is its only capability.

* **Implementation:** Stage 1 Lisp, **executed** by the seed (resolved decision 7). The seed does not compile it into the bridge; it evaluates it during the build of the bridge. The function is therefore not part of the seed binary, but the evaluator that runs it is.
* **Scope:** exactly the IR subset that Stage 1 emits when compiling the bridge. It does **not** need to support the IR contained in Stage 1's own hand-written source.
* **Input:** in-memory S-LLVM IR AST only. No component in this chain parses textual LLVM IR, so `simple-codegen` works directly on the data structures the emitter has already built.
* **Output:** machine code for the target, which the container writer turns into a linked executable. Together they replace `llc`, the assembler and the linker for the bridge build.
* **Container formats:** ELF and PE in the near term, Mach-O eventually (resolved decision 6). They are written by a Lisp function, so the seed keeps only the ability to run, allocate from its arena and write bytes. Mach-O is deferred because macOS ships as `.s` and keeps using platform tools (see [Platforms and Targets](01_platforms.md), section 6.2).
* **Target support:** uses simplified target descriptions (see section 5).
* **Behaviour on unsupported input:** a hard, explicit error. Silent miscompilation is forbidden.
* **Auditability:** the Lisp sources are reviewed as ordinary code and do not count against the seed's binary size budget. The evaluator that runs them does.

### 3.3 Where the Lowering Code Runs

**Design priority: a small seed always takes priority over a small bridge.** This rule governs every trade-off in this section, and it is recorded among the global structural principles in the [Architecture Map](../architecture.md).

**Bootstrap goal:** the bridge build must not depend on any external tool - not on `llc`, not on the system assembler, not on the linker. Lowering code can only be run by a program that already exists, so that program is the seed itself. Five configurations were considered:

| Option | `simple-codegen` and container writer implemented in | Runs inside the seed | External tools needed to build the bridge | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| **A. Native in seed** | hand-written `.ll` inside the seed | yes, as native code | none | rejected: raw IR is a poor medium for byte offsets and container constants, and three container formats written in hand-written IR are expensive to produce and to audit |
| **B. Evaluated by seed** | Stage 1 Lisp, executed by the seed's evaluator | yes, as evaluated Lisp | none | **long-term answer** |
| **C. Compiled into bridge** | Stage 1 Lisp, compiled by the seed into the bridge | no | `llc` | rejected: circular, because the bridge does not exist yet when its own executable has to be written |
| **D. Platform assembler** | seed emits `.s`, the platform assembler and linker finish the job | no | assembler, linker | rejected: breaks the LLVM dependency only, not the external-tool dependency; Windows has no assembler |
| **E. External `llc`** | seed emits `.ll`, `llc` lowers and links it | no | `llc` | **interim answer** |

**B is the long-term answer and E is the interim one (resolved decision 7).** Until the seed has an evaluator, the bridge is built the interim way: the seed emits `.ll` and an external `llc` lowers and links it. When B lands, the same build is performed entirely by the seed, and the bootstrap goal is met.

**Why B and not A.** The container writer is small, but the lowerer is not. A Lisp lowerer plus an evaluator is smaller and far more auditable than the same lowerer written in hand-written LLVM IR. A is technically possible and is recorded here so that it is not re-derived as a new idea; it is rejected on seed size and auditability, consistent with the priority stated above.

Two costs follow from B, and both must be paid explicitly:

* **The seed must contain an evaluator.** Environments, `apply`, special forms and primitive dispatch become part of the seed binary. This is real seed growth and must be covered by the seed size budget in [Seed Artifacts](08_seed_artifacts.md). It is not a container writer in `.ll`, but it is not free.
* **Evaluator and compiler must agree.** The same Lisp sources are executed by the seed and may later be compiled by it for other purposes. Semantic divergence between the two is a correctness risk, so an equivalence check belongs to the release criteria (section 8).

## 4. Supported IR Subset and Conformance

The correctness of `simple-codegen` depends on one invariant:

> **Closure invariant:** `supported_subset(simple-codegen) >= IR_forms(Stage 1 compiling the bridge)`

This is a build-time, machine-checked requirement, not a review guideline.

### Conformance test (required)

1. Compile the bridge sources with the seed, capturing the emitted IR forms.
2. Check that every captured form belongs to the declared `simple-codegen` subset.
3. Fail the build if any form is missing from the subset.

The test belongs to the Stage 1 regression suite (see [Stage 1 (Seed)](04_stage1_seed.md), section 8). Its purpose is to prevent a front-end change from silently invalidating the lowerer.

### Explicitly out of scope for `simple-codegen`

* IR contained in the Stage 1 hand-written source.
* IR required to build Stage 3, which is lowered by an external `llc` until `koivu-llc` exists (resolved decision 8).

Consequence: after M2, an external `llc` is required for the seed build and the Stage 3 Version A build, until `koivu-llc` replaces it at M4.

## 5. Target Descriptions

Target descriptions are stored as Scheme source files. They are deliberately a **subset** of what LLVM target definitions provide, not a clone.

| Kind | Used by | Scope | Milestone |
| :--- | :--- | :--- | :--- |
| **Simple Target Description** | `(koivu backend simple-codegen)` | only the instructions required by the Stage 1 seed when compiling the Stage 2 bridge | M2 |
| **Production Target Description** | production code generator, `koivu-llc` | full instruction set required by the production pipeline | M3 |

Adding a target means writing a target description and, for the seed, cross-compiling it from an existing host. The step-by-step procedure is described in [Platforms and Targets](01_platforms.md).

## 6. Production Backend

### 6.1 Production Generic LLVM IR Emitter

Stage 3 and other production compilers emit LLVM IR via the `(koivu backend syntax llvm-ir)` library. Production backends use the `flat-ast-llvm-ir` data scheme for representing the LLVM IR AST in memory.

#### Bootstrapping vs. Production AST Layers

| Architectural Metric | Bootstrapping Layer | Production Layer |
| :--- | :--- | :--- |
| **Design Priority** | Simplicity & Easy Human Audit | Cache Line Saturation & No-GC |
| **Physical Memory Shape** | Nested Pointer Lists (Pairs) | Flat, Contiguous `u32` Array Vectors |
| **Library Descriptor** | `(koivu backend s-llvm-ir)` | `(koivu backend syntax llvm-ir)` |
| **Data Node Prefix** | **`ast-s-llvm-ir-`** | **`flat-ast-llvm-ir-`** |
| **Node Indexing Model** | Recursive list traversal (`car`/`cdr`) | Flat index offsets (`+1`, `+2`, `+3`) |

The bootstrapping layer has two consumers: the Stage 1 seed itself, and the Stage 2 bridge, which links the Scheme implementation of the same contract in order to emit IR for Stage 3.

### 6.2 Production Lowering Stack

Later-stage Koivu libraries provide maximum capabilities for code generation in Stage 3 and other production compilers:

* `(koivu backend analysis)`: Computes program information (like dominance trees, scalar evolution, and alias analysis) without altering the IR.

* `(koivu backend transforms)`: Contains sub-libraries like Scalar, Vectorize, IPO (Interprocedural Optimizations), and Utils that execute the actual transform passes (e.g., Dead Code Elimination, Loop Unrolling, Inlining).

* `(koivu backend codegen)`: Bridges the gap between target-independent code generation and the final target emission. Contains CodeGenPrepare, a critical IR-to-IR transform pass that runs right before code generation to mutate the IR specifically to benefit the target machine.

* `(koivu backend machine-code-layer)`: Definitive library for code emission. The Machine Code Layer handles assembly-level constructs entirely divorced from LLVM IR (e.g., labels, sections, raw target instructions).

### 6.3 Production Target Descriptions

Koivu backend stores production target descriptions as Scheme source files.

### 6.4 Target Description Converter

Koivu will provide a tool written in Scheme for parsing LLVM Target Descriptions and converting them to Scheme-format Koivu Target Descriptions.

### 6.5 `koivu-llc` - CLI Replacement for `llc`

`koivu-llc` (`koivu-llc.exe` on Windows) is a command-line tool built on top of the production lowering stack, with a thin CLI shim added. Its purpose is to remove the dependency on LLVM's `llc` at late stages of development, while keeping the `.ll` format as a first-class interchange and debugging format.

* **Goal:** drop-in replacement for `llc` for the IR subset that Koivu emits.
* **Built from:** `(koivu backend codegen)` and `(koivu backend machine-code-layer)`, plus production target descriptions.
* **Milestone:** M4 (requires M3, because it depends on the production lowering stack).
* **Input format:** textual `.ll` (resolved decision 3). A drop-in `llc` replacement must read textual LLVM IR, which implies an LLVM IR parser in the production stack. The cost of such a parser is analysed in [Parsing LLVM IR in Koivu Scheme](notes_on_llvm_ir_parsing.md). The parser is a production-stage component and is never part of the Stage 1 seed.
* **`.ll` output is not removed:** Koivu compilers of all stages keep an option to emit `.ll`, and `koivu-llc` keeps the ability to consume it.

## 7. Non-goals

* `(koivu backend simple-codegen)` does not optimize, does not cover the full IR, and is not a general-purpose `llc` replacement.
* `koivu-llc` does not aim to cover the whole LLVM IR grammar or the whole `llc` feature set; it aims to cover what Koivu emits.
* LLVM IR emission is never removed from any stage, including after full self-hosting.

## 8. Acceptance Criteria

1. **Emitter validity:** `.ll` produced by `(koivu backend s-llvm-ir)` is accepted by external `llc` without warnings for all Stage 1 test programs.
2. **Lowerer equivalence:** the linked executable produced by `simple-codegen` runs on the target without any external assembler or linker, and passes the same test suite as the `llc`-lowered and linked output for the same input.
3. **Subset conformance:** the closure invariant of section 4 is checked automatically in CI.
4. **Determinism:** emitter and lowerer output is deterministic (stable ordering, no timestamps, no absolute paths), because the self-hosting fixpoint check compares binaries byte-for-byte.
5. **`koivu-llc` parity:** for the supported subset, `koivu-llc` output passes the same tests as `llc` output.
6. **Evaluator/compiler equivalence:** for the same Lisp source, evaluation by the seed and compilation by the seed produce the same observable results across the test suite. This criterion exists because option B puts both a reader/compiler and an evaluator in the seed. It explicitly covers **closure semantics**: mutation visibility through `set!` on captured variables, shared frames between sibling closures created in one invocation, and the lifetime of an environment that outlives its creating call.
7. **Emitter mirror equivalence:** the hand-written `.ll` emitter inside the seed and the Scheme implementation of `(koivu backend s-llvm-ir)` produce identical `.ll` output for the same S-LLVM IR AST. This criterion exists because decision 5 keeps two implementations of the same behaviour.

## 9. Decisions

### Resolved

| # | Decision | Resolution | Consequence |
| :--- | :--- | :--- | :--- |
| 1 | `simple-codegen` input format | **In-memory S-LLVM IR AST only** | the seed needs no LLVM IR parser at M2 |
| 2 | `simple-codegen` output format | **Linked executable**, produced together with the container writer | together they replace `llc`, the assembler and the linker for the bridge build |
| 3 | `koivu-llc` input format | **Textual `.ll`** (true drop-in) | the production stack needs an LLVM IR parser, see [notes](notes_on_llvm_ir_parsing.md); the parser is never part of the seed |
| 4 | Does `simple-codegen`'s subset cover the Stage 3 build? | **No** | the supported subset covers only the IR emitted by Stage 1 for the bridge; the Stage 3 build is lowered by `llc` until `koivu-llc` |
| 5 | `(koivu backend s-llvm-ir)` in Stage 1: contract or mirror? | **Mirror: two implementations of the same behaviour**, hand-written `.ll` inside the seed and Scheme from Stage 2 up | an equivalence check becomes a release criterion (section 8, criterion 7) |
| 6 | Executable container formats written by `simple-codegen` | **All three eventually: ELF, PE, Mach-O. Near term: ELF and PE only** | the seed must produce a runnable executable on every supported host; Mach-O is deferred because macOS ships as `.s` and keeps using platform tools (see [Platforms and Targets](01_platforms.md), section 6.2) |
| 7 | Where `simple-codegen` and the container writer run (see section 3.3) | **B long-term: Stage 1 Lisp executed by the seed's evaluator. E interim: external `llc` until the evaluator exists** | the seed gains an evaluator but no native container writer; the bootstrap goal is met at M2 |
| 8 | How the Stage 3 build is lowered after M2 | **External `llc` until M4** | the supported IR subset does not need to cover the IR emitted for Stage 3; `koivu-llc` takes over at M4 |
| 9 | Bootstrap goal | **The bridge build must not depend on any external tool** - no `llc`, no assembler, no linker | fixes the acceptance point at M2 and rules out option D, which breaks only the LLVM dependency |
| 10 | Stage 1 closure representation | **Chained frames: `closure = { code_ptr, env_ptr }`, frames linked by a parent pointer, variable access by a compile-time `(depth, index)` pair** | no free-variable analysis and no copying at closure creation; `set!` on captured variables is allowed and shares state; environments live in the arena, so no GC is needed |

### Provisional decisions

Decisions 5 and 8 are recorded as provisional. Both may be re-evaluated in the future:

* **Decision 5** may be revisited if maintaining two emitter implementations proves more expensive than the auditability it buys. The alternative is a single implementation, described in prose as a behavioural contract.
* **Decision 8** may be revisited if a compiled-in copy of `simple-codegen` in the bridge turns out to be cheaper than keeping `llc` in the Stage 3 build until M4. That would extend the supported IR subset to cover the IR emitted for Stage 3.

No decisions are currently open.
