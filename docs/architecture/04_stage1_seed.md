
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

Koivu Stage 1 (**Koivu Seed**) is a minimalist, statically typed, ahead-of-time (AOT) Lisp-1 compiler written in pure, generic LLVM IR. Its core purpose is to compile the Stage 2 macro-expanding bridge compiler (`koivu-bridge.scm`) into executable code and exit, maintaining a minimal footprint and zero external dependencies for auditability and simplicity.

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
* **Tail-Call Optimization (TCO):** Tail calls lower to LLVM IR `tail call` instructions (or native jumps) to ensure recursive Stage 2 passes execute in constant stack space.
* **Infinite Loop Protection:** Allocating loops are caught by arena limits; non-allocating development loops rely on a `MAX_COMPILE_STEPS` step counter before exiting with code `1`.

## 3. Buffered File I/O and System Calls

Koivu Seed avoids streaming state machines by performing whole-file buffered I/O via flat **Byte buffer** structures (`{ ptr data, i32 len, i32 cap }`):

* **Input (`SourceBuffer`):** Opens the `.scm` source file, verifies size $\le$ `MAX_INPUT_BYTES`, allocates `file_size + 1` bytes from the bump arena (appending a `0x00` sentinel byte), reads the entire file in one system call, and closes the handle.
* **Output (`EmitBuffer`):** Appends emitted LLVM IR or machine code bytes into the pre-allocated `EMIT_BUFFER_BYTES` slice. On successful compilation, flushes `data[0..len]` to disk in a single write call and closes the file. Overflowing `EMIT_BUFFER_BYTES` aborts with an error.

### Required Host System Calls
Platform-specific glue code must abstract exactly six host OS primitives:

| Primitive | POSIX (`Linux` / `macOS`) | Windows (`x86_64`) | Purpose |
| :--- | :--- | :--- | :--- |
| **Reserve Memory** | `mmap` | `VirtualAlloc` | Allocate the `ABS_MEM_LIMIT_BYTES` bump arena |
| **Open File** | `open` | `CreateFileA` | Open `.scm` input or create `.ll` output |
| **Query Size** | `fstat` / `lseek` | `GetFileSizeEx` | Determine source file byte length |
| **Read Stream** | `read` | `ReadFile` | Load entire `.scm` source into `SourceBuffer` |
| **Write Stream** | `write` | `WriteFile` | Flush `EmitBuffer` to file or write to `stdout`/`stderr` |
| **Close / Exit** | `close` / `exit` | `CloseHandle` / `ExitProcess` | Release file handles and terminate process |

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
* **No dynamic `eval` or runtime garbage collection.**

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
| `bootstrap/stage1-ll/koivu_seed_glue_posix.ll` | System call glue for `Linux` and `macOS` |
| `bootstrap/stage1-ll/koivu_seed_glue_windows.ll` | System call glue for Windows `x86_64` |
| `bootstrap/stage1-ll/kernel32.def` | Windows `kernel32.dll` import definitions |
| `bootstrap/stage1-ll/<subsystem>.ll` | An example subsystem |

### Build & Distribution Artifacts

* **Development Build Scripts:**
  * `koivu_seed_build_posix.sh` — Compiles Stage 1 `.ll` files into `koivu-seed` on `Linux` / `macOS`.
  * `koivu_seed_build_windows.cmd` — Compiles Stage 1 `.ll` files into `koivu-seed.exe` on Windows `x86_64`.
* **Production Distribution:**
  * **Windows (`x86_64`):** Distributed as a pre-built `koivu-seed.exe` binary.
  * **POSIX (`Linux` / `macOS`):** Distributed as a target assembly file (`.s`) to be assembled and linked locally before running the Stage 2 bootstrap build.

## 8. Testing Strategy

The Stage 1 regression suite in `tests/` must verify:

1. **CLI & Error Handling Tests:** Missing files, oversized inputs, malformed S-expressions, type mismatches, and zero-argument fallback behavior (`koivu-bridge.scm` vs. version print).
2. **Lisp Unit Tests:** Isolated `.scm` programs testing fixnum arithmetic, Cons cell mutation, symbol interning (`eq?`), closures, tail-call recursion, and byte-buffer operations.
3. **Integration Tests:** End-to-end compilation of multi-function Scheme programs to `.ll`, assembled via LLVM and executed to verify runtime output.
4. **Production Smoke Self-Test:** Executing `koivu-seed` with no `koivu-bridge.scm` present in the working directory to verify that `Koivu Seed v0001` prints cleanly to `stdout` with exit code `0`.

