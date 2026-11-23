# Koivu Vesi - the Pino Lowerer

**Status:** Architecture Blueprint  

**Component:** `koivu-vesi`  

> Pintel: "I'm gonna teach you to be a gentleman, and you're gonna teach me to be a pirate."<br>
> Ragetti: "I don't want to be a pirate!"<br>
> Pintel: "Too late."

Vesi (Finnish *vesi*: "water") is the program that turns Pino IR into a target executable. It sits in the bootstrap chain, between a compiler that emits Pino and the machine code a user runs. Its job is narrow on purpose: everything that requires knowing the target lives here, and everything that requires knowing Scheme lives elsewhere.

---

## 0. Scope and Vocabulary

| Term | Definition |
| :--- | :--- |
| **Vesi** | The component defined by this document. The binary is `koivu-vesi` (`koivu-vesi.exe` on Windows). |
| **`.pino`** | Textual Pino IR. Since Vesi exists, this is an **interface between two programs**, not a debug dump (section 2). |
| **Lowering** | Pino IR -> machine code -> executable container. The whole of Vesi's work. |
| **Image** | The `.pino` file that a compiler emits for one program. One program, one image. |
| **Front end** | A compiler that produces an image: the seed, the sapling, and later Stage 3's bootstrap path. |
| **`koivu-pino`** | The development compiler, outside the chain ([Pino IR](pino.md), section 1). It is not Vesi and does not replace it. |
| **`koivu-llc`** | The production LLVM IR lowerer, outside the chain ([Backend](backend.md), section 7.3). It is not Vesi either. |

**Vesi is a tool, not a stage.** Stages in this project are compilers of Scheme, each written in the previous stage's output language. Vesi consumes Pino, not Scheme, so it sits on the tool axis, beside `koivu-llc`, and it does not disturb the stage numbering.

## 1. Why Lowering Is a Separate Program

The earlier design linked the Pino compiler into every compiler that emitted Pino ([Backend](backend.md), section 9, decision 3). That is reversed. The reasons are worth recording, because the reversal was not a matter of taste.

### The front end becomes portable

A compiler that only emits `.pino` needs no instruction encoder, no label table, no backpatch resolver, no branch-displacement encoding, no container writer, and no target description. It needs a reader, an arena, a front end and file output. **It becomes one program for every host.**

That is the decisive argument. Porting a host used to mean porting the whole seed; now it means writing a Vesi for that host, and the front end is not touched at all. The per-host code shrinks to exactly the part that is genuinely per-host.

### One lowering path, not two

With both the seed and the sapling emitting images, the Pino compiler exists **once**. There is no in-process library and no second implementation to keep in step, and the mirror problem that [Backend](backend.md), section 3 accepts as a temporary cost between M1 and M2 disappears entirely.

### The audit seam becomes explicit

The chain now has two questions instead of one:

1. **Does this Scheme source produce this image?** A semantic question, answered by reading a front end.
2. **Does this image produce these bytes?** A mechanical question, answered by a tool.

Both are smaller than "does this Scheme source produce this binary", and the second one is small enough to be checked mechanically for every image, which is what [Backend](backend.md), section 8, criterion 7 asks for. Splitting a hard audit into a hard-but-small part and a mechanical part is the gain; the total amount of code is not reduced.

### The cost, stated plainly

The total is **larger**, not smaller: the front end keeps its size, Vesi adds a second reader and a second arena, and the two together are roughly 1.4 times the single compiler. Against that, size is a ceiling rather than a target ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2), while portability, a single lowering path and a mechanical audit seam are the properties this project actually wants.

### Rejected alternatives

* **An interpreter instead of a lowerer.** Rejected; the full argument is in [Pino Interpreter Notes](notes_on_pino_interpreter.md). It does not shrink the front end, it replaces a mechanical mapping with a semantic one, and it puts a runtime into every produced executable.
* **A bytecode form of Pino.** Rejected. A bytecode is compressed and non-symbolic: it inherits every readability problem of machine code while losing the one thing machine code has, an external specification enforced by hardware. Text is self-describing; bytecode is not.
* **Keeping the library and adding Vesi.** Rejected. Two lowering paths mean two implementations of the same mapping, which is the mirror this project refuses everywhere else.

## 2. `.pino` Is an Interface

An image is exchanged between two programs, so its text is part of the project's contract and is specified rather than merely printed.

### Form

An image is a sequence of top-level forms, as defined in [Pino IR](pino.md), section 3:

```scheme
(pino-module
  (symbols "quote" "if" "cons")
  (fn main (0)
    (push-i32 10)
    (push-i32 20)
    (add)
    (syscall exit)))
```

### Rules that follow from being an interface

* **Canonical printing.** A front end prints an image in exactly one way: one form per line, one instruction per line, a single space between a form and its operands, no trailing whitespace, `\n` line endings, decimal integers with no leading zeros and no `+` sign. Without this the fixpoint check and the committed-artifact check are not well defined.
* **Comments are insignificant.** `;` to end of line is allowed and carries no meaning; a tool that rewrites an image may drop comments, and a comparison ignores them.
* **Arity is explicit.** Every `(fn <name> (<n>) ...)` states its parameter count, because Vesi performs no inference.
* **No target information.** An image is target-independent. Which target it becomes is decided when Vesi runs, not when the image is printed.
* **Versioned.** The first form of an image is `(pino-module ...)`; a future incompatible change introduces a different head symbol rather than silently reinterpreting the old one. Vesi rejects an image it does not understand, by name, and never guesses.

### What an image does not carry

No type information, no source locations, no names for locals, no macro state and no debug metadata. Everything that a front end knew and the lowering does not need is dropped before the image is written. This is what keeps the seam cheap: an image contains exactly what Vesi consumes.

## 3. Position in the Chain

```
Scheme source ──► front end ──► image (.pino) ──► Vesi ──► executable
```

Every front end in the chain produces images; Vesi is the only thing that turns an image into something runnable.

| Compiler | Produces | Lowered by |
| :--- | :--- | :--- |
| Stage 1 seed | `koivu-sapling.pino` | Vesi |
| Stage 2 sapling | Stage 3 `Version A` image | Vesi |
| Stage 3, later | `.ll`, or an image if it is used as a bootstrap front end | its own production backend, or Vesi |

**Cross-compilation becomes a property of Vesi.** An image built once is lowered per target, so `(target "...")` in the build manifest is read by Vesi and not by any front end ([Stage 1 (Seed)](04_stage1_seed.md), section 7).

## 4. Responsibilities

Vesi does:

* read an image and reject a malformed one with a diagnostic and exit code `1`;
* **verify the stack balance of every function statically**, before any byte is emitted — with an implicit operand stack, an unbalanced sequence is silent memory corruption, and Vesi is the last place it can be caught;
* bind `(label <sym>)` to byte offsets;
* patch branch displacements, asserting that each fits the encoding its target description declares;
* encode every instruction through one fixed byte template per instruction per target;
* write the executable container;
* report, on request, the instruction set it encoded, for the ISA conformance test.

Vesi does not:

* check types, resolve scopes, or synthesize control flow — those are front-end jobs, and by the time an image exists they are done;
* expand macros;
* optimise anything;
* read Scheme;
* link, or know what an object file is. Koivu has no separate compilation ([Backend](backend.md), section 9, decision 12).

## 5. Size

Estimated share of what used to be one Stage 1 binary **[estimate]**:

| Component | Share |
| :--- | :--- |
| `.pino` reader, symbol table, arena, file output | ~30% |
| instruction encoder and fixup resolver | ~13% |
| container writer, one format per host | ~15% |
| OS glue, the seven primitives | ~5% |
| **Vesi total** | **~60%** |

The seed keeps its reader, interner, arena and front end (~78% of the old binary) and loses everything target-specific. The pair is larger than the single compiler; each part is simpler; and the seed is no longer per-host.

## 6. Platform Position

Vesi is the **per-host artifact** of the bootstrap chain. The seed is not.

* **Shared POSIX source set.** Linux and macOS share one Vesi source set, with the seven primitives the only host-specific part, issued as a syscall instruction on Linux and as a `libSystem` call on macOS ([Platforms and Targets](01_platforms.md), section 6.1).
* **Containers are per format, not per host.** ELF64, PE32+ and Mach-O are three writers; the first two are reached from different hosts, the third is the one that must also be signed by the user, never by Vesi ([Backend](backend.md), section 5).
* **Porting.** Goal B in [Platforms and Targets](01_platforms.md), section 4 reduces to: write a Pino target description, write or extend a Vesi, cross-compile the seed. The seed itself needs no port.

## 7. Bootstrapping

Vesi is in the chain, so it is also a binary that must come from somewhere.

* **Before M2.** Vesi is written in C and built by the same external C compiler that builds the seed. It is a development scaffold, deleted with the rest of the C code at M2.
* **From M2.** Vesi is written in Scheme, built by the chain: the seed compiles Vesi's source to an image, and an existing Vesi lowers that image into a new Vesi binary.

That gives the project a **second fixpoint**:

| Fixpoint | Compared |
| :--- | :--- |
| the compiler fixpoint | Stage 3 Version B and Version C, byte for byte ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 6) |
| the lowerer fixpoint | a Vesi built by Vesi from its own image, and the Vesi that built it, byte for byte |

Both are needed. A chain whose compilers reach a fixpoint while its lowerer does not is not stable; the artifact that produces machine code must be as reproducible as the artifact that produces images.

## 8. Acceptance Criteria

1. **Determinism.** The same image and the same target produce a byte-identical executable, with stable ordering, no timestamps and no absolute paths.
2. **No silent miscompilation.** An unknown instruction, a malformed image, a stack imbalance or a branch displacement that does not fit is a hard error with a diagnostic. Vesi never emits a guessed encoding.
3. **ISA membership.** Every instruction Vesi encodes belongs to the declared Pino ISA and has a template for the target; the conformance test of [Backend](backend.md), section 4 is run by Vesi on request.
4. **Container validity.** An executable Vesi writes runs on its target with no assembler, linker or system toolchain.
5. **Image independence.** The same image, lowered for two targets, produces two executables with identical behaviour.
6. **Canonical printing.** Re-printing a parsed image reproduces it byte for byte, comments aside.

## 9. Decisions

| # | Decision | Resolution | Consequence |
| :--- | :--- | :--- | :--- |
| 1 | Lowering: library or program? | **Program**, `koivu-vesi` | the front end becomes portable; the total grows; the library disappears |
| 2 | Is Vesi a stage? | **No — a tool on the chain** | the stage numbering is untouched |
| 3 | What do the seed and the sapling emit? | **Images only** | neither carries an encoder or a container writer |
| 4 | Status of `.pino` | **A specified interface**, canonically printed and versioned | a debug dump is no longer enough; the printer is part of the contract |
| 5 | Bytecode form | **Rejected** | text stays self-describing |
| 6 | Interpreter instead of a lowerer | **Rejected** | see [Pino Interpreter Notes](notes_on_pino_interpreter.md) |
| 7 | Where the stack-depth check runs | **In Vesi, on load, before emitting** | the last point at which an imbalance can be caught cheaply |
| 8 | Where `(target ...)` is read | **By Vesi** | cross-compilation is a lowerer property |

## 10. What This Document Supersedes

Recorded so the reconciliation is a checklist rather than a search:

* [Backend](backend.md), section 9, **decision 3** — the Pino compiler is no longer a library linked into each compiler; it is this program. Sections 2 and 3 of that document describe the library and need rewriting.
* [Pino IR](pino.md), section 1 — `.pino` is no longer a debug dump only; it is the interface described in section 2 here. The `koivu-pino` development compiler remains, but it is no longer the only writer of images.
* [Stage 1 (Seed)](04_stage1_seed.md) — the seed emits an image and writes no container; its CLI, layout and size budget follow.
* [Stage 2 (Sapling)](05_stage2_sapling.md) — the sapling emits an image for Stage 3.
* [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 6 — every step gains a lowering sub-step performed by Vesi.
* [Seed Artifacts](08_seed_artifacts.md) — there are now two distributed artifacts per host, and the size budget applies to each.
* [Roadmap to Self-hosting](selfhosting.md) — the T-diagrams gain Vesi as the bottom language of Steps 1 and 2.
* [Stage 1 (Seed)](04_stage1_seed.md), section 7 and [Architecture Map](../architecture.md) — the build is two passes over one manifest.

Until that reconciliation is done, those documents are stale in exactly the places listed above and nowhere else.
