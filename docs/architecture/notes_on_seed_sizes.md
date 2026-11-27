# How Small Are Compiler Seeds?

**Status:** Developer Notes  

**Component:** Global  

[Seed Artifacts](08_seed_artifacts.md), section 7 sets two ceilings: 1600 KiB for a seed binary on `x86_64` and 2400 KiB on `arm64`, and a tighter pair for `koivu-vesi`, 1200 KiB and 1800 KiB. The obvious next question is whether those are small or large. The honest answer is that the question cannot be answered until "seed" is pinned down, because the numbers people quote for small seeds usually measure something else entirely.

One clarification first, because it decides which row Koivu occupies. The seed is not the program a user trusts: it is published as one target-independent image and lowered by the user with the Vesi they have just checked, so the seed binary compared below is one the user produces rather than one they download ([Seed Artifacts](08_seed_artifacts.md), section 1). **The artifact Koivu asks anyone to trust is Vesi.**

This note collects the comparison cases, sorts them by what they are a seed *for*, and states which figures are reported, estimated or unverified. It is a research note: no number here is a commitment.

Confidence markers used below:

* **[reported]** - a widely published figure that this note did not independently measure;
* **[estimate]** - derived here from a stated basis;
* **[unverified]** - an order of magnitude recalled from experience, to be measured before it is quoted anywhere else.

## 1. Four Different Things Called "A Seed"

Almost every disagreement about seed size is a disagreement about level.

| Level | What the seed can do | Typical size | Example |
| :--- | :--- | :--- | :--- |
| **Bit-level seed** | read hexadecimal digits from a file and jump into the result | hundreds of bytes | GNU `hex0` |
| **Compiler-level seed** | compile a real language, with no external tool | hundreds of KiB to a few MiB | Koivu seed, Mes, TinyCC |
| **Toolchain seed** | build an entire operating system or language ecosystem | tens to hundreds of MiB | GCC bootstrap tarball, JDK, a previous `rustc` |
| **Image seed** | restore a heap image of a compiler that is already running | a few to tens of MiB | Chez boot files, `sbcl.core` |

A 357-byte seed is not a smaller Koivu seed. It is a seed for a different job: it cannot compile anything, and it reaches a compiler only after several further stages, each of which is itself a binary that somebody has to trust. That does not make it worse - the GNU project's reasoning is that each rung is *simple enough to review*, not that the whole ladder is small - but the number cannot be compared with ours directly.

A second axis matters just as much: is the quoted number machine code only, or the whole distributed artifact? A boot file that is mostly data structures is not comparable to a flat machine-code image.

A third axis decides how the Koivu row should be read: is the artifact one a user downloads and trusts, or one they produce themselves from an image using a tool they have already reviewed? The Koivu seed is the second kind. What is published is `koivu-seed.pino`, one target-independent image; the seed binary exists only after a user lowers that image with `koivu-vesi`. So the Koivu row in this section, and the two Koivu rows in section 3, all describe a binary the user builds, and the trust question is asked of Vesi instead. Chez and SBCL sit on the other side of this axis: their boot files and cores are downloaded as-is and are the thing trusted.

## 2. The Cases Named in the Question

### GNU Bootstrapping: stage0, Mes and MesCC

The famous figure is `hex0`, a hand-written hexadecimal monitor: **~357 bytes [reported]**. It is the smallest seed in wide use, and it is the one quoted whenever somebody says "seeds should be tiny".

What that number covers is one rung of a long ladder:

`hex0` -> `hex1` -> `hex2` -> `M0` (a C-subset compiler written in M1 assembly) -> `Mes` (a Scheme interpreter written in C) -> `MesCC` (a C compiler written in Scheme) -> `TinyCC` -> `GCC`.

Sizes along that ladder, all **[unverified]**:

* `M0`: a few KiB of machine code - it is a small compiler written in assembly, not a monitor;
* `Mes`: hundreds of KiB - a Scheme interpreter in C, tens of thousands of lines of C;
* `TinyCC`: around 100 KiB - a self-hosting C compiler.

The honest comparison with Koivu is therefore not `hex0`. It is **the whole prefix needed to reach a compiler of comparable capability** - `hex0` through `Mes` and `MesCC`, or `hex0` through `TinyCC` if a C compiler is what you wanted. Summed, that is hundreds of KiB to a few MiB, which is the same order as our own estimate. GNU wins on the size of the *first* rung and pays for it with a ladder of eight stages; we have one rung and no ladder.

Guix ships this chain as its "bootstrap binaries", which is the practical form of the same idea: a distribution whose trust anchor is a few hundred bytes plus a long, simple chain.

### Chez Scheme

Chez is the closest architectural relative Koivu has: R6RS, nanopasses, a compiler written in Scheme. Its answer to "where do we start" is the opposite of GNU's.

Chez bootstraps from **boot files** - compiled images of the compiler itself, `petite.boot` and `scheme.boot` - together with a C kernel. Order of magnitude for the boot files: **a few MiB [unverified]**, varying by machine type and version.

Two things follow, and both are worth knowing before somebody proposes Chez as a size argument:

* Chez has **no small seed**. Its seed is a Chez binary, produced by an earlier Chez. That is a Trusting-Trust-shaped answer: the chain is reproducible but not independently anchored.
* Chez's own bootstrap story is nevertheless the one Koivu's later stages resemble, because a Scheme compiler written in Scheme is what Stage 3 is.

For our purposes the interesting consequence is that a boot-file architecture lands in the same size range as our whole seed, while providing no independent anchor at all. Being in that range is not a defect.

### SBCL

The largest of the four. `make.sh` requires a **host Common Lisp** - historically CMU CL, in practice now an older SBCL - plus a C runtime, plus a `genesis` step that emits `sbcl.core`.

Order of magnitude **[unverified]**:

* the C runtime: a few hundred KiB of machine code;
* `sbcl.core`: tens of MiB, in the 40-50 MiB range for current versions.

The C runtime is not the seed. The seed is "a complete Common Lisp implementation that already works", which is precisely the dependency Koivu exists to avoid. SBCL is the clearest illustration that image-based self-hosting optimises for development speed and not for auditability.

### Old and Small Lisps

* **Lisp 1.5 (1962):** a hand-written assembly evaluator, a few KiB **[unverified]**. It was an interpreter, not a compiler, and it ran on machines with 32K words of memory, so the number is small for reasons that do not transfer.
* **Maclisp, Interlisp, Zetalisp:** large systems bootstrapped from machine-code or microcode images. No useful small-seed story.
* **Scheme 48:** a bytecode VM in C (roughly 10 KLOC) plus a heap image. Small kernel, big image - the pattern that keeps recurring.
* **PicoLisp, TinyScheme, s7:** C cores of a few hundred KiB **[unverified]**, but they are *interpreters embedded in C*. Their seed is a C compiler, so the problem is moved rather than solved. This is the same objection that applies to any "small Lisp in C" claim.

The recurring pattern across all of these is: **small kernel plus large image**, or **tiny seed plus long ladder**. Koivu chose a third shape - a single small compiler - and that choice is what fixes its size.

## 3. Sorted by Level

Machine code only, ascending, with what each number is a seed *for*:

| System | Level | Size | Confidence |
| :--- | :--- | :--- | :--- |
| GNU `hex0` | bit-level | ~0.4 KB | reported |
| `M0` | compiler-level, C subset | a few KiB | unverified |
| GNU `Mes` | interpreter-level | hundreds of KiB | unverified |
| `TinyCC` | compiler-level, C | ~100 KiB | unverified |
| Koivu `koivu-vesi` | lowerer, `.pino` to machine code | ~600 KiB `x86_64`, ~900 KiB `arm64` | estimate |
| Koivu seed binary | compiler-level, full | 1-1.5 MiB `x86_64`, 1.5-2.2 MiB `arm64` | estimate |
| Chez boot files | image | a few MiB | unverified |
| SBCL runtime + core | image | tens of MiB | unverified |

The two Koivu rows are the binary produced from an image, not an image: `koivu-vesi` from `koivu-vesi.pino`, the seed from `koivu-seed.pino`. Their ceilings are the pairs in [Seed Artifacts](08_seed_artifacts.md), section 7.

Read down that table and the conclusion is unremarkable: a full compiler costs hundreds of KiB to a few MiB, and everything smaller is either a smaller job (a monitor, a C subset) or a bigger job dressed as a small one (an interpreter whose seed is a C compiler).

## 4. What This Means for the Koivu Ceiling

* **The 1.6 / 2.4 MiB ceiling is defensible.** It is the same order as a Chez boot file set, and it is smaller than the GNU prefix needed to reach a comparable compiler. The number that would be indefensible is a comparison against `hex0`, and nobody is proposing that.
* **The trust anchor is the smaller program, and that is deliberate.** Koivu asks a user to trust `koivu-vesi`, whose ceiling is 1200 KiB on `x86_64` and 1800 KiB on `arm64` - below the seed's own budget, because Vesi is a lowerer with no front end in it. The seed image is then lowered by the Vesi the user has already reviewed, so the unreviewed surface is the smaller of the two rather than the larger.
* **The right comparison is capability, not bytes.** The question to ask of any competing seed is: what can it compile, with what external tools, and how many rungs must be trusted to get there. On that measure Koivu's single rung is a good trade: no external tool from M0, and a machine-code-to-source correspondence that is mechanically checkable ([Backend](backend.md), section 8, criterion 7).
* **The interpreter is a Vesi variant, not a seed.** An earlier draft put a tiny Pino interpreter in the seed as a first rung; [Pino Interpreter Notes](notes_on_pino_interpreter.md) retargets the idea to Vesi. Vesi V1 interprets `.pino` instead of lowering it, V2 bundles the interpreter with the image, V3 is a development mode that skips the writer. None of this shrinks the seed - the front end is still the bulk of it - and it would shrink Vesi only by its encoder, its label table and its three container writers. Recorded here as considered and rejected, so it is not rediscovered as an idea: our auditability argument rests on correspondence between source and machine code, not on minimising bytes ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2), and a second implementation of the same semantics would be a second thing to trust.
* **Bit-level seeds are out of scope by design.** Koivu is not a distribution bootstrap and does not intend to provide a sub-kilobyte starting point. GNU's chain already exists for that purpose, and a project can reasonably depend on it being available rather than rebuild it.

## 5. Before Any Number Is Quoted Elsewhere

Sizes change between releases, and this note's numbers are estimates and recollections. Before any of them appears in a blueprint, a blog post or a comparison table, measure it and record the version:

* `hex0` and `M0`: current GNU Mes / stage0 release;
* `Mes`, `TinyCC`: current releases, stripped binaries;
* Chez: boot files for the current version on `x86_64` and `arm64`;
* SBCL: `sbcl.core` for the current version;
* Koivu: `koivu-vesi` and our own seed, once both can be built - which is the measurement [Seed Artifacts](08_seed_artifacts.md), section 7 is waiting for.

The last line is the only one that can change a decision. The rest are context.
