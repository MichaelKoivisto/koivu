
# Koivu Scheme Stage 1 (Seed) Compiler

> **Status:** Architecture Blueprint<br>
> **Component:** Stage 1

> Barbossa: Jack... Jack! Did you not notice? That be the same island we made you the governor of on our last little trip.<br>
> Jack Sparrow: I did notice.<br>
> Barbossa: Perhaps you'll conjure up another miraculous escape, but I doubt it. Off you go.<br>
> Jack Sparrow: The last time you left me a pistol with one shot.<br>
> Barbossa: By the powers, you're right. Where be Jack's pistol? Bring it forward.<br>
> Jack Sparrow: Seeing as there's two of us, a gentleman would give us a pair of pistols.<br>
> Barbossa: It'll be one pistol as before, and you can be the gentleman and shoot the lady; and starve yourself to death.

Koivu Stage 1 (**Koivu Seed**) is a minimalist, statically typed, ahead-of-time (AOT) Lisp-1 compiler. Its core purpose is to compile the Stage 2 macro-expanding sapling compiler (`koivu-sapling.scm`) to a Pino image and exit, maintaining a minimal footprint and zero external dependencies for auditability and simplicity. "Zero external dependencies" means no third-party dependencies; what it means per host, and why it is not the same as a statically linked binary, is stated in section 3.

The seed emits Pino IR as a `.pino` image and writes no machine code, no executable container and no assembler input: `koivu-vesi` lowers the image ([Koivu Vesi](koivu-vesi.md)). Earlier drafts had the seed write machine code itself and keep Pino IR in memory only. The image is now the seed's product, and that is what makes the seed the same program on every host and puts the whole target-specific path in one place. Its implementation language is staged: C before M2, Scheme afterwards ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2; [Backend](backend.md), decision 4). The language changes once; everything else in this document is written to be independent of it.

## 1. Identity, Versioning, and CLI

* **Official Name:** `Koivu Seed`
* **Executable Names:** `koivu-seed` (POSIX), `koivu-seed.exe` (Windows `x86_64`)
* **Version Format:** 4-digit zero-padded unsigned integer (e.g., `Koivu Seed v0001`), manually incremented.
* **Output:** a Pino image, `<name>.pino`, and nothing else. The seed writes no executable container, so it needs no assembler and no linker, and no build step between it and Vesi. An image is target-independent, so the seed has no target option at all: which target an image becomes is decided when Vesi runs, from `(target "...")` in the build manifest ([Koivu Vesi](koivu-vesi.md), section 3).

### Command-Line Interface
1. **Single Argument:** `koivu-seed <input.scm>` compiles the specified source file to `<input>.pino`, written beside the source.
2. **Zero Arguments:** `koivu-seed` looks for `koivu-sapling.scm` in the current working directory and compiles it to `koivu-sapling.pino`.
3. **Missing Default Input:** If no argument is present and `koivu-sapling.scm` is missing, it prints `Koivu Seed v0001` to `stdout` and exits with code `0`.
4. **Build Manifest:** `koivu-seed --build build.koivu` reads a build manifest and writes one image per program it lists, each named `<name>.pino` beside the manifest (section 7). Without the flag the input is one program's root source. The two are different things, and which one was meant is not inferred from the extension.

**No output option.** The seed takes no `-o` and no `--emit-pino`. The second would name a choice that does not exist, since an image is the only thing the seed produces; the first cannot be honest either, because one output path cannot serve a manifest with several programs, and an option that exists in one of two modes is worse than none. The image name follows from the input or from the manifest, and a test that needs two images side by side compares a fresh one against a committed golden image instead (section 8).

**One file, always.** The seed never takes a list of sources. A multi-file program has exactly one root source file and the rest enter through `include`, which the reader resolves textually ([Koivu Scheme](03_language.md), Multi-File Programs). Composition therefore lives in the source, where a reviewer can read it, rather than in the invocation.

**Entry and exit.** Every image the seed writes begins with an `entry` procedure that calls `main` and passes its return value to the host exit primitive:

```scheme
(fn entry (0)
  (push-fn main)
  (call 0)
  (syscall exit))
```

`main` itself stays an ordinary arity-0 procedure that returns, so no procedure in the image is exempt from the calling convention, and the container's fixed entry offset lands on `entry` because it is first ([Pino IR](pino.md), section 3). Vesi synthesizes no control flow, so emitting this sequence is the seed's job ([Koivu Vesi](koivu-vesi.md), section 4). A program with no `main`, or with two, is rejected at compile time ([Koivu Scheme](03_language.md), Program Entry Point).

## 2. Memory Management & Execution Bounds

Targeting hosts with at least 2 GiB of RAM, Koivu Seed uses a **Bump Allocator** with a strict **No-GC** policy.

> [!WARNING]
> **Memory Allocation Capping:** No garbage collector is used. Runaway allocation loops will exhaust the bump arena and trigger an immediate process abort.

* **Key Parameters:**
  * `ABS_MEM_LIMIT_BYTES`: `536870912` (512 MiB) hard-coded total arena reserved via `mmap` / `VirtualAlloc`.
  * `MAX_INPUT_BYTES`: `16777216` (16 MiB) maximum total size of the sources a program draws in, counted across every file reached through `include`.
  * `EMIT_BUFFER_BYTES`: `67108864` (64 MiB) pre-allocated slice for the emitted image text.
* **Arena Mechanics:** Allocations advance a bump pointer and verify against `ABS_MEM_LIMIT_BYTES`; exceeding the limit writes an error to `stderr` and exits with code `1`.
* **Tail-Call Optimization (TCO):** Tail calls lower to the Pino `(tail-call)` instruction, which overwrites the current frame's arguments and jumps to the callee. Constant stack space follows from the instruction, not from a lowerer's cooperation, so nothing has to be checked or trusted.
* **Infinite Loop Protection:** Allocating loops are caught by arena limits; non-allocating development loops rely on a `MAX_COMPILE_STEPS` step counter before exiting with code `1`.

## 3. Buffered File I/O and System Calls

Koivu Seed avoids streaming state machines by performing whole-file buffered I/O via flat **Byte buffer** structures (`{ ptr data, i32 len, i32 cap }`):

* **Input (`SourceBuffer`):** Opens the `.scm` source file, verifies size $\le$ `MAX_INPUT_BYTES`, allocates `file_size + 1` bytes from the bump arena (appending a `0x00` sentinel byte), reads the entire file in one system call, and closes the handle.
* **Output (`EmitBuffer`):** Appends the image text into the pre-allocated `EMIT_BUFFER_BYTES` slice. On successful compilation, flushes `data[0..len]` to disk in a single write call and closes the file. Overflowing `EMIT_BUFFER_BYTES` aborts with an error.

### Required Host System Calls
Platform-specific glue code must abstract exactly seven host OS primitives, counted individually:

| Primitive | POSIX (`Linux` / `macOS`) | Windows (`x86_64`) | Purpose |
| :--- | :--- | :--- | :--- |
| **Reserve Memory** | `mmap` | `VirtualAlloc` | Allocate the `ABS_MEM_LIMIT_BYTES` bump arena |
| **Open File** | `open` | `CreateFileA` | Open `.scm` input or create the output image |
| **Query Size** | `fstat` / `lseek` | `GetFileSizeEx` | Determine source file byte length |
| **Read Stream** | `read` | `ReadFile` | Load entire `.scm` source into `SourceBuffer` |
| **Write Stream** | `write` | `WriteFile` | Flush `EmitBuffer` to file or write to `stdout`/`stderr` |
| **Close File** | `close` | `CloseHandle` | Release an open file handle |
| **Exit Process** | `exit` | `ExitProcess` | Terminate the process with a status code |

**One POSIX source set.** Linux and macOS share the glue: `bootstrap/stage1/os/posix` is one source set, not two. The seven primitives above are the only part that differs between them, and only in how a primitive is issued - a syscall instruction on Linux, a call into `libSystem` on macOS, because syscall numbers are not a stable ABI there and `libSystem` is the supported interface. Everything above that boundary is shared ([Platforms and Targets](01_platforms.md), section 6.1).

This has one consequence for the project's own claims, so it is stated rather than implied: on macOS the seed is a **dynamically linked** Mach-O executable. "Zero external dependencies" therefore means "no third-party dependencies" - on macOS the seed links against the OS-supplied `libSystem`, and static linking against macOS system libraries is not an option. On Linux the same holds only for the C scaffold before M2, which a C compiler builds against libc; from M2 the seed emits syscalls itself and links nothing. See [Platforms and Targets](01_platforms.md), section 6.1.

### Stream Logging Conventions
* **`stdout`:** Prints `Koivu Seed v0001` when invoked with no arguments and no `koivu-sapling.scm` is present, or prints a brief completion confirmation upon successful compilation (exit code `0`).
* **`stderr`:** Reserved exclusively for diagnostic error messages. Any failure exits immediately with a non-zero exit code (`1`).

## 4. Supported Language Capabilities

Koivu Seed compiles a statically typed subset of Koivu Scheme sufficient to build the Stage 2 macro-expanding compiler.

### Basic Data Types
* **Signed 32-bit Integers (Fixnums):** held in a uniform 64-bit stack word as a sign-extended 32-bit value. Arithmetic operates on the low 32 bits and sign-extends the result ([Pino IR](pino.md), section 2).
* **Symbols:** Interned immutable string pointers compared by memory address (`eq?`).
* **Cons Cells:** Untagged 16-byte pairs (`CAR` + `CDR` pointers). Static type-checking ensures type-safe instruction emission.
* **Byte Buffers:** Flat byte vectors (`{ ptr, i32 len, i32 cap }`) for source input and image output.

### Closures (simplified)

Stage 1 uses the simplest closure model that still gives correct lexical scoping. It is deliberately not an implementation of the full R6RS closure semantics.

* **Closure object:** `{ code_ptr, env_ptr }` - two pointers, 16 bytes, the same shape as a Cons cell. There is no tag, no arity field and no captured-variable descriptor in the object.
* **Environment frames:** `{ parent_env_ptr, slot0, slot1, ... }`. A frame belongs to one invocation of one lambda and holds all of that invocation's variables. Frames are **linked to their parent, never copied**, so a closure creation is a single two-field allocation.
* **Variable reference:** compiled to a compile-time `(depth, index)` pair - a fixed number of pointer hops followed by a fixed slot offset. No name lookup, no hash tables, no symbol search at run time.
* **`set!` on captured variables is allowed.** Because frames are shared rather than copied, mutation through one closure is visible through every closure that captured the same frame. This is what the Stage 2 passes need, and it costs nothing extra given the frame layout above.
* **Explicitly out of scope for Stage 1:** free-variable analysis, lambda lifting, closure conversion, variable-arity lambdas (fixed arity only), more than one frame per call, `call/cc`, and introspection of a closure beyond `procedure?`.
* **No GC:** closure objects and frames are allocated from the bump arena like every other object and live until the process exits. This is consistent with the No-GC policy in section 2.
* **Tail calls** lower to `(tail-call)`, which overwrites the current frame's arguments and jumps to the callee - constant stack space by construction, with no hint that a lowerer may ignore.

The model is recorded as resolved decision 11 in the [Backend](backend.md) blueprint.

### Special Forms & Primitives

| Category | Required Forms / Intrinsics | Purpose |
| :--- | :--- | :--- |
| **Special Forms** | `quote`, `if`, `set!`, `define`, `lambda` | Core control flow, bindings, and lexical closures |
| **Symbols** | `symbol?`, `eq?` | Pointer-equality identifier matching |
| **Cons Cells** | `cons`, `car`, `cdr`, `pair?`, `null?`, `set-car!`, `set-cdr!` | S-expression traversal and AST mutation |
| **Fixnum Math** | `+`, `-`, `<`, `=`, `integer?` | Array indexing, offsets, and bounds validation |
| **Byte Buffers** | `make-byte-buffer`, `byte-buffer-ref`, `byte-buffer-append!` | Reading source text and emitting target code |
| **Process Control** | `error` | Print diagnostic message to `stderr` and call OS exit (`1`) |

### Explicit Omissions
* **No native macro expander (`syntax-rules` / `syntax-case`):** Stage 1 compiles raw macro-free Scheme; Stage 2 implements macro expansion as user-level S-expression transformations.
* **No multiple return values (`values`, `call-with-values`):** Use Cons cells instead.
* **No runtime `eval` in compiled programs:** the executables the chain produces contain no reader and no interpreter. `eval` is unavailable to the sapling, to Stage 3, and to anything they compile.
* **No runtime garbage collection:** every object, including closures and their environment frames, lives in the bump arena until the process exits (see section 2).

**These omissions describe the language the seed compiles, not the language the seed is written in.** The seed is a compiler and nothing else: it carries a reader and a front end, but no evaluator and no `apply`, and it never interprets Scheme at build time ([Backend](backend.md), section 3 and decision 5). Nothing interprets Pino IR either: the image is lowered by `koivu-vesi`, a separate program ([Koivu Vesi](koivu-vesi.md)). From M2 the seed is itself written in Koivu Scheme, which is consistent with this: a compiler written in Scheme compiles Scheme without evaluating it.

## 5. Primitives and the Absence of a Runtime Library

Stage 1 primitives need no runtime library. Each one lowers either to a single Pino instruction or to a short, fixed sequence of them ([Pino IR](pino.md), section 4):

* `cons` becomes `(alloc 16)` followed by two stores; `car`, `cdr`, `set-car!` and `set-cdr!` become loads and stores at fixed offsets 0 and 8.
* `+`, `-`, `<` and `=` become `(add)`, `(sub)`, `(cmp-lt)` and `(cmp-eq)`.
* Byte-buffer operations become `(alloc)`, `(load8)`, `(store8)` and their 64-bit counterparts.
* `error` becomes `(syscall write)` to `stderr` followed by `(syscall exit)`.

Three consequences follow, and all three are the point:

* **Nothing is called at run time** except the seven host primitives of section 3. A compiled Koivu program is self-contained code plus the container around it.
* **There is no intrinsic layer**, no calling convention for a runtime library, and no symbol names to agree on between the front end and a library that does not exist.
* **The primitive set is bounded by the instruction set**, so a front-end change cannot quietly introduce a run-time dependency: an instruction outside the Pino ISA is a build error, caught before any image is written ([Backend](backend.md), section 4).

**Naming convention:** internal seed procedures follow Scheme naming even in the C implementation (`koivu_alloc`, `koivu_sys_write`, `koivu_byte_buffer_append`), and are organised around the instruction set rather than around the host language's idioms. This is what makes the C-to-Scheme rewrite at M2 a translation rather than a redesign ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2).

## 6. Error Handling

All errors must write a human-readable diagnostic message to `stderr` and terminate the process immediately with exit code `1`.

| Error Condition | Build Mode | Required Action |
| :--- | :--- | :--- |
| **Arena or Output Buffer Exhaustion** | All Builds | Print out-of-memory error to `stderr` and exit (`1`) |
| **File Open / Read / Create Failure** | All Builds | Print I/O error with filename to `stderr` and exit (`1`) |
| **Syntax / Malformed S-Expression** | All Builds | Print parse error to `stderr` and exit (`1`) |
| **Static Type Mismatch** | Development | Print type mismatch error to `stderr` and exit (`1`); may be stripped in production builds to minimize binary size |
| **Compile-Time Step Limit Exceeded** | Development | Print infinite-loop warning to `stderr` and exit (`1`); stripped in production builds |
| **Instruction Outside the Pino ISA** | All Builds | Print the offending instruction to `stderr` and exit (`1`); never write a partial image |

## 7. Source Code Structure & Build Process

### Layout

The seed's sources live in `bootstrap/stage1/`. The directory name carries no language suffix, because the implementation language changes once while the path must not: build scripts, ignore rules and the porting procedure in [Platforms and Targets](01_platforms.md), section 4 all refer to it.

| Path | Role |
| :--- | :--- |
| `bootstrap/stage1/main` | Entry point, CLI argument parsing, and top-level compilation driver |
| `bootstrap/stage1/reader` | S-expression reader |
| `bootstrap/stage1/symbols` | Symbol interner |
| `bootstrap/stage1/arena` | Bump allocator and byte buffers |
| `bootstrap/stage1/frontend` | S-expression to Pino IR: type checks, `(depth, index)` resolution, primitive lowering |
| `bootstrap/stage1/os/` | The seven primitives of section 3: `posix` for Linux and macOS, `windows` for Windows `x86_64` |
| `bootstrap/build.sh`, `bootstrap/build.cmd` | Development build scripts for the whole chain (see below) |
| `bootstrap/pino/main` | Vesi's entry point and command-line interface |
| `bootstrap/pino/read` | `.pino` reader and the static stack-balance verifier |
| `bootstrap/pino/encode` | One byte template per Pino instruction per target |
| `bootstrap/pino/fixup` | Label table and backpatch resolver |
| `bootstrap/pino/container/` | One file per executable format: `elf64`, `pe32plus`, `macho` |
| `bootstrap/pino/target` | Reads a target description from `targets/` |
| `targets/` | Target description data files, both kinds defined in [Backend](backend.md), section 6 |
| `tools/` | Command-line tools outside the bootstrap chain: `koivu-llc` |

A row naming a single file is one source file in the current language of the program it belongs to (`main.c` now, `main.scm` from M2); the `bootstrap/pino/` rows follow Vesi's language rather than the seed's. A row naming a directory holds one file per host or per format.

**Two languages at once, between M0 and M2.** The Scheme front end has to exist before the seed is rewritten in it, because the sapling is built from it: the sapling is the seed's Scheme front end plus a macro expander, compiled by the C seed ([Stage 2 (Sapling)](05_stage2_sapling.md), section 1). So `bootstrap/stage1/` holds `*.c` and `*.scm` side by side until M2 - the C files as the scaffold that builds the first binaries, the Scheme files as the front end from which the sapling, and from M2 the seed itself, are built. At M2 the `.c` files are deleted, and the directory is what its name always said it was: the seed's source, in whatever language the seed is written in.

`bootstrap/pino/` is Vesi's source set - `koivu-vesi`, the Pino lowerer ([Koivu Vesi](koivu-vesi.md)). The directory is named for what its contents read, not for the binary they build, so it keeps the name `pino` rather than becoming `bootstrap/vesi/`. It sits beside `bootstrap/stage1/` because it is not part of the seed at all: the seed writes an image and stops, and the sapling's images go through the same Vesi ([Backend](backend.md), section 2). Stage 2 sources live in `bootstrap/stage2/`. Stage 3 is the production codebase rather than a bootstrap step, so it lives in `src/`; both are described in their own blueprints.

`tools/` holds the command-line tools that are not part of the chain. With lowering now in the chain as `koivu-vesi` ([Koivu Vesi](koivu-vesi.md)), that leaves `koivu-llc`, the production LLVM IR lowerer ([Backend](backend.md), section 7.3).

There is no `kernel32.def` and no module-definition file of any kind: the PE writer builds the import directory itself, so no linker reads a definition file.

### Build Process (development builds)

The seed and Vesi are built by a C compiler before M2 and by a Koivu compiler produced by the chain from M2 onwards. Neither procedure is the distribution mechanism; the forms in which they are published, and what each of them can prove, are defined in [Seed Artifacts](08_seed_artifacts.md), section 2.

`build.sh` and `build.cmd` sit at the top of `bootstrap/` rather than inside `bootstrap/stage1/`, because they start two sibling programs - the seed and Vesi - and a script that lives inside one of them would be claiming to own the other. They are deliberately the thinnest files in the tree. They select the host's source set and start what has to be started - the external C compiler before M2, then the seed and Vesi in order; they hold no knowledge of what depends on what, no conditional compilation logic and no generated files. That is the whole of their job, and it is bounded by the rule in the [Architecture Map](../architecture.md): build orchestration belongs to Koivu, and a shell script may only start a program.

* **Before M2:** `build.sh` invokes the host's LLVM C compiler on the C sources, always selecting `os/posix`; `build.cmd` does the same on Windows `x86_64` with `os/windows`. It builds two programs - the seed and Vesi - and the C compiler is the only external build tool the project ever uses, and only during early development.
* **From M2:** a Koivu compiler produced by the chain compiles the Scheme sources to images, and an existing Vesi lowers them. No C compiler, assembler, linker or platform toolchain is involved.

**The target is a build driven by Koivu.** Multi-file builds are Koivu's own responsibility, and the description is **read as data**, not executed: the seed has no evaluator, so a build description written in Koivu Scheme is a manifest of programs and their root sources, which the compiler reads and acts on ([Backend](backend.md), decision 5). Because every program has one root source and `include` supplies the rest ([Koivu Scheme](03_language.md), Multi-File Programs), the manifest needs no source lists, no ordering and no dependency graph. There is no separate compilation and nothing to link ([Backend](backend.md), decision 12).

**Two passes over one manifest.** A build is the seed writing every image the manifest lists, then Vesi lowering every image it lists: the same manifest, read twice, by the two programs that each own half of the job. The seed never learns what a target is, and Vesi never learns what Scheme is. `build.sh` starts the two in order and does nothing else. Producing several programs is a loop over manifest entries, not a compiler mode. Shell scripts survive only where the host leaves no alternative - starting the first binary, or reaching the external C compiler before M2 - and even there they only invoke.

The per-host artifact table is in [Platforms and Targets](01_platforms.md), section 2.

### Build Manifest

A manifest is Scheme **data** read by the compiler, not a program it runs: the seed has no evaluator, so a build description cannot be code ([Backend](backend.md), decision 5).

```scheme
(build
  (program "koivu-sapling"
    (root "bootstrap/stage2/koivu-sapling.scm")))
```

| Element | Meaning |
| :--- | :--- |
| `(build <program> ...)` | the whole manifest |
| `(program <name> (root <path>))` | one program; `<name>` is also the base name of its image, `<name>.pino`, written beside the manifest |
| `(target "...")` | optional, defaults to the host; read by Vesi, not by the seed, so it selects what the images are lowered to rather than what is compiled ([Koivu Vesi](koivu-vesi.md), section 3) |

* **The file is `build.koivu` at the repository root**, and paths inside it are relative to its own directory, so the build does not depend on where it is invoked from. The distinct extension follows the ASDF `.asd` tradition and marks the file as not-a-program, so nobody compiles it by accident.
* **There is no ordering and no dependency graph.** `include` already encodes both ([Koivu Scheme](03_language.md), Multi-File Programs).
* **There are no source lists, per-file flags or conditionals.** A manifest that needs logic has outgrown being a manifest, and that is a design smell to fix rather than a feature to add.
* **The manifest describes what Koivu builds.** Before M2 that excludes the seed itself, which `build.sh` and the C compiler produce, and Vesi for the same reason, so until then the manifest has one entry - the sapling - which is an honest statement of how much of the build Koivu actually owns at that point.

A manifest has to exist at all because of the rule in the [Architecture Map](../architecture.md): without one, building several programs means several compiler invocations, and whatever issues them is a script deciding what to build. The manifest is what puts that loop inside Koivu instead of in a shell.

## 8. Testing Strategy

The Stage 1 regression suite in `tests/` must verify:

1. **CLI & Error Handling Tests:** Missing files, oversized inputs, malformed S-expressions, type mismatches, zero-argument fallback behavior (`koivu-sapling.scm` vs. version print), and a rejected instruction outside the Pino ISA.
2. **Lisp Unit Tests:** Isolated `.scm` programs testing fixnum arithmetic, Cons cell mutation, symbol interning (`eq?`), closures, tail-call recursion, and byte-buffer operations. Each is compiled to an image, lowered by Vesi and run, so a unit test takes the same path as test 3 and differs from it only in scope.
3. **Integration Tests:** End-to-end compilation of multi-function Scheme programs to images, lowered by Vesi, each resulting executable run directly to verify runtime output. No assembler and no linker appear in the path, so a failure here is a failure of the seed, of Vesi, or of the image between them - and never of a tool nobody in this project wrote.
4. **Production Smoke Self-Test:** Executing `koivu-seed` with no `koivu-sapling.scm` present in the working directory to verify that `Koivu Seed v0001` prints cleanly to `stdout` with exit code `0`.
5. **Sapling Test:** Compilation of the Stage 2 Sapling source to an image, and lowering of that image to the sapling executable.
6. **ISA Conformance Test:** The invariant of [Backend](backend.md), section 4 is machine-checked. The sapling and Stage 3 sources are compiled, the emitted images are captured, and the build fails if any instruction in them falls outside the declared Pino ISA or has no template for a supported target. Without this test a front-end change can silently invalidate the lowerer.
7. **Determinism Test:** Compiling the same source twice produces a byte-identical image, with stable ordering, no timestamps and no absolute paths ([Backend](backend.md), section 8, criterion 4). Because the seed takes no output option, a second compile of one source overwrites the first, so the fresh image is compared against a committed golden one, regenerated by CI and failed on mismatch - the same pattern the committed `.s` artifacts use ([Seed Artifacts](08_seed_artifacts.md), section 3). The self-hosting fixpoint check depends on this property, so it is tested long before it is needed.
