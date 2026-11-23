
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

Koivu Stage 1 (**Koivu Seed**) is a minimalist, statically typed, ahead-of-time (AOT) Lisp-1 compiler written in pure, generic LLVM IR. Its core purpose is to compile the Stage 2 macro-expanding bridge compiler (`koivu-bridge.scm`) into executable code and exit, maintaining a minimal footprint and zero external dependencies for auditability and simplicity. "Zero external dependencies" means no third-party dependencies; what it means per host, and why it is not the same as a statically linked binary, is stated in section 3.

## 1. Identity, Versioning, and CLI

* **Official Name:** `Koivu Seed`
* **Executable Names:** `koivu-seed` (POSIX), `koivu-seed.exe` (Windows `x86_64`)
* **Version Format:** 4-digit zero-padded unsigned integer (e.g., `Koivu Seed v0001`), manually incremented.
* **Compilation Target:** Emits generic LLVM IR (`.ll`) during early development, transitioning to direct native machine code in self-hosting builds.

### Command-Line Interface
1. **Single Argument:** `koivu-seed <input.scm>` compiles the specified source file into `<input>.ll`.
2. **Zero Arguments:** `koivu-seed` looks for `koivu-bridge.scm` in the current working directory and compiles it to `koivu-bridge.ll`.
3. **Missing Default Input:** If no argument is present and `koivu-bridge.scm` is missing, it prints `Koivu Seed v0001` to `stdout` and exits with code `0`.

## 2. Memory Management & Execution Bounds

Targeting hosts with at least 2 GiB of RAM, Koivu Seed uses a **Bump Allocator** with a strict **No-GC** policy. 

> [!WARNING]
> **Memory Allocation Capping:** No garbage collector is used. Runaway allocation loops will exhaust the bump arena and trigger an immediate process abort.

* **Key Parameters:**
  * `ABS_MEM_LIMIT_BYTES`: `536870912` (512 MiB) hard-coded total arena reserved via `mmap` / `VirtualAlloc`.
  * `MAX_INPUT_BYTES`: `16777216` (16 MiB) maximum input `.scm` file size.
  * `EMIT_BUFFER_BYTES`: `67108864` (64 MiB) pre-allocated slice for output IR/code.
* **Arena Mechanics:** Allocations advance a bump pointer and verify against `ABS_MEM_LIMIT_BYTES`; exceeding the limit writes an error to `stderr` and exits with code `1`.
* **Tail-Call Optimization (TCO):** Tail calls lower to LLVM IR `musttail` calls (or native jumps) to guarantee that recursive Stage 2 passes execute in constant stack space. A bare `tail` marker is not sufficient: it is a hint that LLVM may ignore.
* **Infinite Loop Protection:** Allocating loops are caught by arena limits; non-allocating development loops rely on a `MAX_COMPILE_STEPS` step counter before exiting with code `1`.

## 3. Buffered File I/O and System Calls

Koivu Seed avoids streaming state machines by performing whole-file buffered I/O via flat **Byte buffer** structures (`{ ptr data, i32 len, i32 cap }`):

* **Input (`SourceBuffer`):** Opens the `.scm` source file, verifies size $\le$ `MAX_INPUT_BYTES`, allocates `file_size + 1` bytes from the bump arena (appending a `0x00` sentinel byte), reads the entire file in one system call, and closes the handle.
* **Output (`EmitBuffer`):** Appends emitted LLVM IR or machine code bytes into the pre-allocated `EMIT_BUFFER_BYTES` slice. On successful compilation, flushes `data[0..len]` to disk in a single write call and closes the file. Overflowing `EMIT_BUFFER_BYTES` aborts with an error.

### Required Host System Calls
Platform-specific glue code must abstract exactly seven host OS primitives, counted individually:

| Primitive | POSIX (`Linux` / `macOS`) | Windows (`x86_64`) | Purpose |
| :--- | :--- | :--- | :--- |
| **Reserve Memory** | `mmap` | `VirtualAlloc` | Allocate the `ABS_MEM_LIMIT_BYTES` bump arena |
| **Open File** | `open` | `CreateFileA` | Open `.scm` input or create `.ll` output |
| **Query Size** | `fstat` / `lseek` | `GetFileSizeEx` | Determine source file byte length |
| **Read Stream** | `read` | `ReadFile` | Load entire `.scm` source into `SourceBuffer` |
| **Write Stream** | `write` | `WriteFile` | Flush `EmitBuffer` to file or write to `stdout`/`stderr` |
| **Close File** | `close` | `CloseHandle` | Release an open file handle |
| **Exit Process** | `exit` | `ExitProcess` | Terminate the process with a status code |

**macOS is not a raw-syscall platform.** The seven primitives above are the same on every host, but on macOS they cannot be reached through syscall instructions: syscall numbers are not a stable ABI there, and `libSystem` is the supported interface. The macOS glue therefore lives in a separate file, `koivu_seed_glue_macos.ll`, and calls `libSystem` instead of issuing `svc`.

This has one consequence for the project's own claims, so it is stated rather than implied: on macOS the seed is a **dynamically linked** Mach-O executable. "Zero external dependencies" therefore means "no third-party dependencies" - on macOS the seed links against the OS-supplied `libSystem`, and static linking against macOS system libraries is not an option. See [Platforms and Targets](01_platforms.md), section 6.1.

### Stream Logging Conventions
* **`stdout`:** Prints `Koivu Seed v0001` when invoked with no arguments and no `koivu-bridge.scm` is present, or prints a brief completion confirmation upon successful compilation (exit code `0`).
* **`stderr`:** Reserved exclusively for diagnostic error messages. Any failure exits immediately with a non-zero exit code (`1`).

## 4. Supported Language Capabilities

Koivu Seed compiles a statically typed subset of Koivu Scheme sufficient to build the Stage 2 macro-expanding compiler.

### Basic Data Types
* **Signed 32-bit Integers (Fixnums):** Mapped directly to `i32` hardware registers.
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
* **Tail calls** lower to LLVM IR `musttail` calls, not to a bare `tail` marker: only `musttail` guarantees the constant stack space that the Stage 2 passes rely on.

The model is recorded as resolved decision 10 in the [Backend](backend.md) blueprint, and its runtime behaviour is covered by the evaluator/compiler equivalence criterion there.

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

**These omissions describe the language the seed compiles, not the language the seed executes.** The seed itself does carry a reader, an evaluator and `apply`, because resolved decision 7 in [Backend](backend.md) places `simple-codegen` and the container writer in Stage 1 Lisp that the seed evaluates during the bridge build. The two statements are compatible: no compiled Koivu program has `eval`, while the seed evaluates Lisp because it is the build tool. The evaluator is real seed growth and is covered by the seed size budget in [Seed Artifacts](08_seed_artifacts.md).

## 5. Compiler Intrinsics

Koivu Seed must expose low-level compiler intrinsics in generic LLVM IR to implement all Stage 1 primitive operations, memory allocation, and OS system-call wrappers.

* **Naming Convention:** Intrinsic names must follow Scheme conventions (e.g., `%koivu-alloc`, `%koivu-sys-write`, `%koivu-byte-buffer-set!`) and lower directly to inline LLVM IR sequences or thin OS glue calls.

```llvm
; Example intrinsic signature for bump-pointer allocation
declare ptr @koivu_alloc(i64 %bytes)
```

## 6. Error Handling

All errors must write a human-readable diagnostic message to `stderr` and terminate the process immediately with exit code `1`.

| Error Condition | Build Mode | Required Action |
| :--- | :--- | :--- |
| **Arena or Output Buffer Exhaustion** | All Builds | Print out-of-memory error to `stderr` and exit (`1`) |
| **File Open / Read / Create Failure** | All Builds | Print I/O error with filename to `stderr` and exit (`1`) |
| **Syntax / Malformed S-Expression** | All Builds | Print parse error to `stderr` and exit (`1`) |
| **Static Type Mismatch** | Development | Print type mismatch error to `stderr` and exit (`1`); may be stripped in production builds to minimize binary size |
| **Compile-Time Step Limit Exceeded** | Development | Print infinite-loop step limit error to `stderr` and exit (`1`); stripped in production builds |

## 7. Source Code Structure & Build Process

All Stage 1 compiler source code is structured into modular subsystems under `bootstrap/stage1-ll/`, 
covering CLI entry, memory management, parsing, environments, typing, and OS glue. 

### Source Layout

| File / Path | Role |
| :--- | :--- |
| `bootstrap/stage1-ll/koivu_seed_main.ll` | Entry point, CLI argument parsing, and top-level compilation driver |
| `bootstrap/stage1-ll/koivu_seed_glue_linux.ll` | System call glue for Linux `x86_64` - raw syscalls |
| `bootstrap/stage1-ll/koivu_seed_glue_macos.ll` | Glue for macOS `arm64` - calls `libSystem` instead of issuing syscalls (see section 3) |
| `bootstrap/stage1-ll/koivu_seed_glue_windows.ll` | System call glue for Windows `x86_64` |
| `bootstrap/stage1-ll/kernel32.def` | Windows `kernel32.dll` import definitions |
| `bootstrap/stage1-ll/<subsystem>.ll` | An example subsystem |

The glue layer cannot be shared between Linux and macOS, because the two reach the same primitives in different ways. Whether the remaining POSIX sources - emitter and ELF writer - can be shared is open question 2 in [Platforms and Targets](01_platforms.md), section 7.

### Build Process (development builds)

* `koivu_seed_build_posix.sh` — assembles and links the Stage 1 `.ll` files into `koivu-seed` on `Linux` and on `macOS`. The macOS branch adds the `libSystem` link step.
* `koivu_seed_build_windows.cmd` — compiles the Stage 1 `.ll` files into `koivu-seed.exe` on Windows `x86_64`, using `kernel32.def`.

These scripts are development tools and are not the distribution mechanism. The forms in which the seed is published, and what each of them can prove, are defined in [Seed Artifacts](08_seed_artifacts.md), section 2; the per-host artifact table is in [Platforms and Targets](01_platforms.md), section 2.

## 8. Testing Strategy

The Stage 1 regression suite in `tests/` must verify:

1. **CLI & Error Handling Tests:** Missing files, oversized inputs, malformed S-expressions, type mismatches, and zero-argument fallback behavior (`koivu-bridge.scm` vs. version print).
2. **Lisp Unit Tests:** Isolated `.scm` programs testing fixnum arithmetic, Cons cell mutation, symbol interning (`eq?`), closures, tail-call recursion, and byte-buffer operations.
3. **Integration Tests:** End-to-end compilation of multi-function Scheme programs to `.ll`, assembled via LLVM and executed to verify runtime output.
4. **Production Smoke Self-Test:** Executing `koivu-seed` with no `koivu-bridge.scm` present in the working directory to verify that `Koivu Seed v0001` prints cleanly to `stdout` with exit code `0`.
5. **Bridge Test:** Compilation of Stage 2 Bridge compiler source code to Stage 2 Bridge executable.
6. **Subset Conformance Test:** The closure invariant of [Backend](backend.md), section 4 is machine-checked. The bridge sources are compiled with the seed, the emitted IR forms are captured, and the build fails if any of them falls outside the declared `simple-codegen` subset. Without this test a front-end change can silently invalidate the lowerer.
7. **Evaluator/Compiler Equivalence Test:** For the same Lisp source, evaluation by the seed and compilation by the seed must produce the same observable results ([Backend](backend.md), section 8, criterion 6). This test covers closure semantics explicitly: mutation visibility through `set!` on captured variables, shared frames between sibling closures created in one invocation, and the lifetime of an environment that outlives its creating call.


