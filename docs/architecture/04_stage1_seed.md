
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

Koivu Stage 1 (**Koivu Seed**) is a minimalist, statically typed, ahead-of-time (AOT) Lisp-1 compiler. Its core purpose is to compile the Stage 2 macro-expanding bridge compiler (`koivu-bridge.scm`) into executable code and exit, maintaining a minimal footprint and zero external dependencies for auditability and simplicity. "Zero external dependencies" means no third-party dependencies; what it means per host, and why it is not the same as a statically linked binary, is stated in section 3.

The seed emits native machine code wrapped in an executable container that it writes itself, so it needs no assembler and no linker. Its implementation language is staged: C before M2, Scheme afterwards ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2; [Backend](backend.md), decision 4). The language changes once; everything else in this document is written to be independent of it.

## 1. Identity, Versioning, and CLI

* **Official Name:** `Koivu Seed`
* **Executable Names:** `koivu-seed` (POSIX), `koivu-seed.exe` (Windows `x86_64`)
* **Version Format:** 4-digit zero-padded unsigned integer (e.g., `Koivu Seed v0001`), manually incremented.
* **Compilation Target:** native machine code for the selected target, in an executable container written by the seed. No intermediate file is produced at any point: Pino IR exists only in the seed's memory ([Pino IR](pino.md)). The host is the default target; another target is selected by name when the seed is used to produce a seed for that platform ([Platforms and Targets](01_platforms.md), section 4).

### Command-Line Interface
1. **Single Argument:** `koivu-seed <input.scm>` compiles the specified source file into an executable `<input>` (`<input>.exe` on Windows).
2. **Zero Arguments:** `koivu-seed` looks for `koivu-bridge.scm` in the current working directory and compiles it to `koivu-bridge`.
3. **Missing Default Input:** If no argument is present and `koivu-bridge.scm` is missing, it prints `Koivu Seed v0001` to `stdout` and exits with code `0`.

## 2. Memory Management & Execution Bounds

Targeting hosts with at least 2 GiB of RAM, Koivu Seed uses a **Bump Allocator** with a strict **No-GC** policy.

> [!WARNING]
> **Memory Allocation Capping:** No garbage collector is used. Runaway allocation loops will exhaust the bump arena and trigger an immediate process abort.

* **Key Parameters:**
  * `ABS_MEM_LIMIT_BYTES`: `536870912` (512 MiB) hard-coded total arena reserved via `mmap` / `VirtualAlloc`.
  * `MAX_INPUT_BYTES`: `16777216` (16 MiB) maximum input `.scm` file size.
  * `EMIT_BUFFER_BYTES`: `67108864` (64 MiB) pre-allocated slice for emitted machine code and container bytes.
* **Arena Mechanics:** Allocations advance a bump pointer and verify against `ABS_MEM_LIMIT_BYTES`; exceeding the limit writes an error to `stderr` and exits with code `1`.
* **Tail-Call Optimization (TCO):** Tail calls lower to the Pino `(tail-call)` instruction, which overwrites the current frame's arguments and jumps to the callee. Constant stack space follows from the instruction, not from a lowerer's cooperation, so nothing has to be checked or trusted.
* **Infinite Loop Protection:** Allocating loops are caught by arena limits; non-allocating development loops rely on a `MAX_COMPILE_STEPS` step counter before exiting with code `1`.

## 3. Buffered File I/O and System Calls

Koivu Seed avoids streaming state machines by performing whole-file buffered I/O via flat **Byte buffer** structures (`{ ptr data, i32 len, i32 cap }`):

* **Input (`SourceBuffer`):** Opens the `.scm` source file, verifies size $\le$ `MAX_INPUT_BYTES`, allocates `file_size + 1` bytes from the bump arena (appending a `0x00` sentinel byte), reads the entire file in one system call, and closes the handle.
* **Output (`EmitBuffer`):** Appends emitted machine code and container bytes into the pre-allocated `EMIT_BUFFER_BYTES` slice. On successful compilation, flushes `data[0..len]` to disk in a single write call and closes the file. Overflowing `EMIT_BUFFER_BYTES` aborts with an error.

### Required Host System Calls
Platform-specific glue code must abstract exactly seven host OS primitives, counted individually:

| Primitive | POSIX (`Linux` / `macOS`) | Windows (`x86_64`) | Purpose |
| :--- | :--- | :--- | :--- |
| **Reserve Memory** | `mmap` | `VirtualAlloc` | Allocate the `ABS_MEM_LIMIT_BYTES` bump arena |
| **Open File** | `open` | `CreateFileA` | Open `.scm` input or create the output executable |
| **Query Size** | `fstat` / `lseek` | `GetFileSizeEx` | Determine source file byte length |
| **Read Stream** | `read` | `ReadFile` | Load entire `.scm` source into `SourceBuffer` |
| **Write Stream** | `write` | `WriteFile` | Flush `EmitBuffer` to file or write to `stdout`/`stderr` |
| **Close File** | `close` | `CloseHandle` | Release an open file handle |
| **Exit Process** | `exit` | `ExitProcess` | Terminate the process with a status code |

**macOS is not a raw-syscall platform.** The seven primitives above are the same on every host, but on macOS they cannot be reached through syscall instructions: syscall numbers are not a stable ABI there, and `libSystem` is the supported interface. The macOS glue therefore lives in a separate file and calls `libSystem` instead of issuing `svc`.

This has one consequence for the project's own claims, so it is stated rather than implied: on macOS the seed is a **dynamically linked** Mach-O executable. "Zero external dependencies" therefore means "no third-party dependencies" - on macOS the seed links against the OS-supplied `libSystem`, and static linking against macOS system libraries is not an option. See [Platforms and Targets](01_platforms.md), section 6.1.

### Stream Logging Conventions
* **`stdout`:** Prints `Koivu Seed v0001` when invoked with no arguments and no `koivu-bridge.scm` is present, or prints a brief completion confirmation upon successful compilation (exit code `0`).
* **`stderr`:** Reserved exclusively for diagnostic error messages. Any failure exits immediately with a non-zero exit code (`1`).

## 4. Supported Language Capabilities

Koivu Seed compiles a statically typed subset of Koivu Scheme sufficient to build the Stage 2 macro-expanding compiler.

### Basic Data Types
* **Signed 32-bit Integers (Fixnums):** held in a uniform 64-bit stack word as a sign-extended 32-bit value. Arithmetic operates on the low 32 bits and sign-extends the result ([Pino IR](pino.md), section 2).
* **Symbols:** Interned immutable string pointers compared by memory address (`eq?`).
* **Cons Cells:** Untagged 16-byte pairs (`CAR` + `CDR` pointers). Static type-checking ensures type-safe instruction emission.
* **Byte Buffers:** Flat byte vectors (`{ ptr, i32 len, i32 cap }`) for source input and code emission.

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
* **No runtime `eval` in compiled programs:** the binaries the seed produces contain no reader and no interpreter. `eval` is unavailable to the bridge, to Stage 3, and to anything they compile.
* **No runtime garbage collection:** every object, including closures and their environment frames, lives in the bump arena until the process exits (see section 2).

**These omissions describe the language the seed compiles, not the language the seed is written in.** The seed is a compiler and nothing else: it carries a reader and a front end, but no evaluator and no `apply`, and it never interprets Scheme at build time ([Backend](backend.md), section 3 and decision 5). Nothing interprets Pino IR either - the library that lowers it is compiled into the seed, not evaluated by it. From M2 the seed is itself written in Koivu Scheme, which is consistent with this: a compiler written in Scheme compiles Scheme without evaluating it.

## 5. Primitives and the Absence of a Runtime Library

Stage 1 primitives need no runtime library. Each one lowers either to a single Pino instruction or to a short, fixed sequence of them ([Pino IR](pino.md), section 4):

* `cons` becomes `(alloc 16)` followed by two stores; `car`, `cdr`, `set-car!` and `set-cdr!` become loads and stores at fixed offsets 0 and 8.
* `+`, `-`, `<` and `=` become `(add)`, `(sub)`, `(cmp-lt)` and `(cmp-eq)`.
* Byte-buffer operations become `(alloc)`, `(load8)`, `(store8)` and their 64-bit counterparts.
* `error` becomes `(syscall write)` to `stderr` followed by `(syscall exit)`.

Three consequences follow, and all three are the point:

* **Nothing is called at run time** except the seven host primitives of section 3. A compiled Koivu program is self-contained code plus the container around it.
* **There is no intrinsic layer**, no calling convention for a runtime library, and no symbol names to agree on between the front end and a library that does not exist.
* **The primitive set is bounded by the instruction set**, so a front-end change cannot quietly introduce a run-time dependency: an instruction the Pino compiler cannot lower is a build error ([Backend](backend.md), section 4).

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
| **Instruction Without a Lowering** | All Builds | Print the offending instruction and target to `stderr` and exit (`1`); never emit a partial or guessed encoding |

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
| `bootstrap/stage1/os/` | The seven primitives of section 3, one file per host: `linux`, `macos`, `windows` |
| `bootstrap/stage1/build.sh`, `bootstrap/stage1/build.cmd` | Development build scripts (see below) |
| `bootstrap/pino/encode` | One byte template per Pino instruction per target |
| `bootstrap/pino/fixup` | Label table and backpatch resolver |
| `bootstrap/pino/container/` | One file per executable format: `elf64`, `pe32plus`, `macho` |
| `bootstrap/pino/target` | Reads a target description from `targets/` |
| `targets/` | Target description data files, both kinds defined in [Backend](backend.md), section 6 |

A row naming a single file is one source file in the seed's current language (`main.c` now, `main.scm` from M2). A row naming a directory holds one file per host or per format.

`bootstrap/pino/` is the Pino compiler library. It is not part of the seed alone: the bridge links the same library, which is why it sits beside `bootstrap/stage1/` rather than inside it ([Backend](backend.md), section 2). Stage 2 and Stage 3 sources live in `bootstrap/stage2/` and `bootstrap/stage3/` and are described in their own blueprints.

There is no `kernel32.def` and no module-definition file of any kind: the PE writer builds the import directory itself, so no linker reads a definition file.

### Build Process (development builds)

The seed is built by a C compiler before M2 and by a Koivu compiler produced by the chain from M2 onwards. Neither procedure is the distribution mechanism; the forms in which the seed is published, and what each of them can prove, are defined in [Seed Artifacts](08_seed_artifacts.md), section 2.

* **Before M2:** `build.sh` compiles the C sources with the host's LLVM C compiler, selecting `os/linux` or `os/macos`; `build.cmd` does the same on Windows `x86_64` with `os/windows`. The C compiler is the only external build tool the project ever uses, and only during early development.
* **From M2:** a Koivu compiler produced by the chain compiles the Scheme sources, lowers Pino IR and writes the container itself. No C compiler, assembler, linker or platform toolchain is involved.

The per-host artifact table is in [Platforms and Targets](01_platforms.md), section 2.

## 8. Testing Strategy

The Stage 1 regression suite in `tests/` must verify:

1. **CLI & Error Handling Tests:** Missing files, oversized inputs, malformed S-expressions, type mismatches, zero-argument fallback behavior (`koivu-bridge.scm` vs. version print), and a rejected instruction with no lowering for the selected target.
2. **Lisp Unit Tests:** Isolated `.scm` programs testing fixnum arithmetic, Cons cell mutation, symbol interning (`eq?`), closures, tail-call recursion, and byte-buffer operations.
3. **Integration Tests:** End-to-end compilation of multi-function Scheme programs to executables, each run directly to verify runtime output. No assembler and no linker appear in the path, so a failure here is a failure of the seed itself.
4. **Production Smoke Self-Test:** Executing `koivu-seed` with no `koivu-bridge.scm` present in the working directory to verify that `Koivu Seed v0001` prints cleanly to `stdout` with exit code `0`.
5. **Bridge Test:** Compilation of Stage 2 Bridge compiler source code to Stage 2 Bridge executable.
6. **ISA Conformance Test:** The invariant of [Backend](backend.md), section 4 is machine-checked. The bridge and Stage 3 sources are compiled, the emitted instruction sets are captured, and the build fails if any instruction falls outside the declared Pino ISA or has no template for a supported target. Without this test a front-end change can silently invalidate the lowerer.
7. **Determinism Test:** Compiling the same source twice produces byte-identical executables, with stable ordering, no timestamps and no absolute paths ([Backend](backend.md), section 8, criterion 4). The self-hosting fixpoint check depends on this property, so it is tested long before it is needed.
