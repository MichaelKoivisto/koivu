# Pino IR Architecture Blueprint

> **Status:** Architecture Blueprint<br>
> **Component:** Stage 1 Core / Stage 2 Bridge / Bootstrap Backend

> Capt. Jack Sparrow: Put it away, son. It's not worth you getting beat again.<br>
> Will Turner: You ignored the rules of engagement. In a fair fight, I'd kill you.<br>
> Capt. Jack Sparrow: That's not much incentive for me to fight fair, is it?

Pino IR (Finnish *pino*: "stack") is a minimalist, S-expression-encoded stack machine Intermediate Representation. It replaces LLVM IR across Stage 1 (Koivu Seed) and Stage 2 (Koivu Bridge). By decoupling the bootstrap pipeline from LLVM toolchains (`llc`) and text-heavy SSA generation, Pino IR keeps the Stage 1 seed minimal, auditable, and capable of direct lowering to native machine code.

LLVM IR remains the primary interchange and lowering format exclusively for Stage 3 (Production Core).

---

## 1. Architectural Rationale & Pipeline Shift

Replacing LLVM IR with Pino IR in Stages 1 and 2 eliminates external toolchain dependencies during bootstrap while enforcing the **Small Seed Over Small Bridge** rule.

| Pipeline Attribute | Legacy Bootstrap Plan | Pino IR Bootstrap Plan |
| :--- | :--- | :--- |
| **Stage 1 Seed Implementation** | Written in generic LLVM IR (`.ll`). | Written in generic LLVM IR (`.ll`). |
| **Stage 1 Output Format** | Textual LLVM IR (`.ll`). | Pino IR S-expressions (`.pino`) (may be printed out for debugging), lowered directly to native binary. |
| **Stage 2 Bridge Output** | Textual LLVM IR (`.ll`); requires `llc` to link Stage 3. | Pino IR S-expressions (`.pino`) lowered directly to native binary. |
| **Stage 3 Production Core** | Emits LLVM IR (`.ll`). | Emits LLVM IR (`.ll`) and native machine code (unchanged). |
| **Evaluator Requirement** | Seed embeds a Lisp evaluator to run `simple-codegen`. | **None.** Stage 1 and Stage 2 lower S-expressions directly to Pino IR. |

### Key Design Invariants

1. **Zero Parser Overhead:** Pino IR uses standard Koivu Scheme S-expressions. The Stage 1 Reader parses both `.scm` source files and `.pino` instruction streams without additional lexer logic.
2. **Implicit Operand Stack:** All arithmetic, memory, and control-flow instructions operate on an implicit evaluation stack. The backend lowerer requires zero register allocation or register spilling logic.
3. **Single-Pass Backpatching:** Forward branch targets (`jmp`, `jz`) emit fixed 32-bit relative placeholders and resolve byte offsets in a single linear scan via a Pass-Based Arena fixup list.
4. **Direct OS Container Emission:** The Pino IR backend wraps emitted machine instructions in minimal, statically linked ELF64 (`Linux`), Mach-O (`macOS` via `libSystem`), or PE32+ (`Windows`) headers directly from memory.

---

## 2. Memory & Data Layout Model

Pino IR preserves all Stage 1 data representation invariants defined in *Koivu Scheme Language* (`03_language.md`) and *Koivu Scheme Stage 1 (Seed) Compiler* (`04_stage1_seed.md`).

> [!WARNING]
> **Untagged Value Representation:** Pino IR does not use pointer tagging. All values on the evaluation stack occupy a uniform **64-bit machine word** (`word64`). Static type-checking in the frontend must guarantee type safety before emitting Pino IR instructions.

### Runtime Object Layouts

| Data Type | Stack Representation (64-bit) | Heap / Arena Layout |
| :--- | :--- | :--- |
| **Fixnum (32-bit Signed)** | Sign-extended 64-bit integer value (`i32` -> `i64`). | Immediate on stack; zero heap allocation. |
| **Symbol** | Raw 64-bit pointer to interned string header. | `{ i32 len, u8[len] bytes, u8 0 }` in bump arena. |
| **Cons Cell** | Raw 64-bit pointer to 16-byte heap pair. | `{ word64 car, word64 cdr }` (16 bytes, 8-byte aligned). |
| **Byte Buffer** | Raw 64-bit pointer to 16-byte descriptor. | `{ ptr data, i32 len, i32 cap }` (16 bytes). |
| **Closure Object** | Raw 64-bit pointer to 16-byte pair. | `{ ptr code_addr, ptr env_ptr }` (16 bytes). |
| **Environment Frame** | Referenced via `env_ptr` register (`R12` / `X19`). | `{ ptr parent_env, word64 slot0, word64 slot1, ... }`. |

### Dedicated Hardware Register Pinning

To eliminate stack-frame bookkeeping in the seed lowerer, Pino IR pins three architectural registers across all generated functions:

| Role | `x86_64` Register | `arm64` Register | Purpose |
| :--- | :--- | :--- | :--- |
| **Evaluation Stack Pointer** | `RSP` | `SP` | Hardware stack used directly as the Pino operand stack. |
| **Current Environment Pointer** | `R12` | `X19` | Points to the active linked lexical environment frame. |
| **Bump Arena Pointer** | `R13` | `X20` | Points to the next free 8-byte aligned byte in the bump arena. |

---

## 3. Pino IR Lexical & Structural Syntax

A `.pino` module is a flat S-expression list containing top-level symbol declarations, function definitions, and linear instruction sequences.

```lisp
(pino-module
  (symbols "quote" "if" "cons" "car" "cdr")

  (fn main ()
    (push-i32 10)
    (push-i32 20)
    (add)
    (sys-exit)))
```

### Top-Level Forms

* `(pino-module <form> ...)`: Root container for a compilation unit.
* `(symbols <string> ...)`: Declares interned string literals placed in the read-only data segment at startup.
* `(fn <symbol> (<param-count>) <inst> ...)`: Declares a compiled procedure entry point with fixed arity `<param-count>`.

---

## 4. Instruction Set Architecture (ISA)

Pino IR consists of **26 instructions** partitioned into five functional groups. Every instruction specifies its exact stack transition (`before -- after`).

### 4.1 Stack & Constant Manipulation

| Instruction | Stack Effect | Semantics |
| :--- | :--- | :--- |
| `(push-i32 <imm>)` | `( -- val )` | Sign-extends 32-bit immediate `<imm>` to 64 bits and pushes onto stack. |
| `(push-sym <sym>)` | `( -- ptr )` | Pushes the 64-bit address of interned symbol `<sym>`. |
| `(push-fn <fn-name>)` | `( -- addr )` | Pushes the code entry address of function `<fn-name>`. |
| `(drop)` | `( a -- )` | Discards the top 64-bit word from the stack. |
| `(dup)` | `( a -- a a )` | Duplicates the top 64-bit word on the stack. |
| `(swap)` | `( a b -- b a )` | Swaps the top two 64-bit words on the stack. |

### 4.2 Fixnum Arithmetic & Comparison

All arithmetic instructions operate on the lower 32 bits of stack words and sign-extend the 32-bit result to 64 bits.

| Instruction | Stack Effect | Semantics |
| :--- | :--- | :--- |
| `(add)` | `( a b -- a+b )` | Pops `b`, pops `a`, pushes `a + b`. |
| `(sub)` | `( a b -- a-b )` | Pops `b`, pops `a`, pushes `a - b`. |
| `(cmp-eq)` | `( a b -- bool )` | Pops `b` and `a`; pushes `1` if `a == b` (pointer or integer), else `0`. |
| `(cmp-lt)` | `( a b -- bool )` | Pops `b` and `a`; pushes `1` if signed `a < b`, else `0`. |

### 4.3 Lexical Environments & Closures

Variables are addressed statically via compile-time `(depth, index)` coordinates, matching Section 4 of `04_stage1_seed.md`.

| Instruction | Stack Effect | Semantics |
| :--- | :--- | :--- |
| `(env-push <slots>)` | `( arg0..argN -- )` | Allocates `(slots + 1) * 8` bytes in bump arena, links `parent_env = R12/X19`, pops arguments into slots, and updates `R12/X19`. |
| `(env-pop)` | `( -- )` | Restores `R12/X19 = [R12/X19 + 0]` (parent frame pointer). |
| `(env-get <depth> <idx>)` | `( -- val )` | Traverses `<depth>` parent pointers from `R12/X19` and pushes `slot[idx]`. |
| `(env-set <depth> <idx>)` | `( val -- )` | Pops `val`, traverses `<depth>` parent pointers from `R12/X19`, and writes `slot[idx] = val`. |
| `(make-closure <fn>)` | `( -- ptr )` | Allocates 16 bytes in bump arena; writes `{ code_addr(<fn>), env_ptr(R12/X19) }` and pushes pointer. |

### 4.4 Memory & Primitive Data Structures

| Instruction | Stack Effect | Semantics |
| :--- | :--- | :--- |
| `(alloc <bytes>)` | `( -- ptr )` | Advances bump pointer `R13/X20` by `<bytes>` (8-byte aligned); aborts if `ABS_MEM_LIMIT_BYTES` exceeded. |
| `(load64 <offset>)` | `( ptr -- val )` | Pops `ptr` and pushes 64-bit word at `[ptr + offset]`. |
| `(store64 <offset>)` | `( ptr val -- )` | Pops `val`, pops `ptr`, and writes 64-bit word `val` to `[ptr + offset]`. |
| `(load8 <offset>)` | `( ptr -- byte )` | Pops `ptr` and pushes zero-extended byte at `[ptr + offset]`. |
| `(store8 <offset>)` | `( ptr byte -- )` | Pops `byte`, pops `ptr`, and writes low 8 bits to `[ptr + offset]`. |

*(Note: Stage 1 `cons`, `car`, `cdr`, `set-car!`, `set-cdr!`, and `byte-buffer` operations lower directly to `(alloc 16)`, `(load64 0/8)`, `(store64 0/8)`, `(load8 0)`, and `(store8 0)` in the frontend, keeping the core ISA minimal.)*

### 4.5 Control Flow & Host OS Primitives

| Instruction | Stack Effect | Semantics |
| :--- | :--- | :--- |
| `(label <sym>)` | `( -- )` | Binds symbol `<sym>` to the current byte offset in `EmitBuffer`. |
| `(jmp <sym>)` | `( -- )` | Unconditional 32-bit relative jump to `<sym>`. |
| `(jz <sym>)` | `( cond -- )` | Pops `cond`; jumps to `<sym>` if `cond == 0`. |
| `(call <arity>)` | `( closure arg0..argN -- ret )` | Saves caller `R12/X19`, loads closure `env_ptr` into `R12/X19`, calls `code_addr`, restores `R12/X19`, and pushes return value. |
| `(tail-call <arity>)` | `( closure arg0..argN -- )` | Overwrites current stack frame arguments, loads closure `env_ptr` into `R12/X19`, and jumps directly to `code_addr` (constant stack space). |
| `(ret)` | `( val -- )` | Pops return value into hardware return register (`RAX` / `X0`) and returns to caller. |
| `(syscall <id>)` | `( a0..aN -- ret )` | Invokes one of the 6 mandatory host OS primitives (`mmap`, `open`, `fstat`, `read`, `write`, `close/exit`). |

---
## 5. Target Lowering Specifications

Each Pino IR instruction maps to a fixed, context-free byte template. No register allocator or instruction scheduler is required in Stage 1 or Stage 2.

### 5.1 Example Lowering: `(add)` and `(jz <label>)`

```assembly
; Target: x86_64
; Pino IR: (add)
pop rbx                 ; 5B
pop rax                 ; 58
add eax, ebx            ; 01 D8
movsxd rax, eax         ; 48 63 C0 (sign-extend 32-bit fixnum to 64-bit word)
push rax                ; 50

; Pino IR: (jz target_label)
pop rax                 ; 58
test rax, rax           ; 48 85 C0
jz rel32_placeholder    ; 0F 84 00 00 00 00 (patched via backpatch list)
```

```assembly
; Target: arm64
; Pino IR: (add)
ldr x1, [x21], #8       ; Pop 64-bit word from dedicated evaluation stack (X21)
ldr x0, [x21], #8       ; Pop second 64-bit word
add w0, w0, w1          ; 32-bit fixnum addition
sxtw x0, w0             ; Sign-extend 32-bit result to 64 bits
str x0, [x21, #-8]!     ; Push 64-bit result onto evaluation stack

; Pino IR: (jz target_label)
ldr x0, [x21], #8       ; Pop condition word
cbz x0, rel19_placeholder ; Compare and branch if zero (patched via backpatch list)
```

> [!WARNING]
> **ARM64 Stack Alignment Constraint:** The `arm64` hardware architecture enforces strict 16-byte alignment on `SP` whenever `SP` is used as a base address register. The `arm64` Pino IR lowerer must either allocate 16 bytes per stack slot on `SP` (leaving 8 bytes as padding) or pin a dedicated general-purpose register (`X21`) as the Pino evaluation stack pointer while reserving `SP` strictly for hardware call/return addresses. Using `X21` cuts stack memory traffic by 50% and prevents alignment faults.

### 5.2 Forward Jump Backpatching

Because Pino IR lowers S-expressions in a single linear pass, forward jumps (`jmp`, `jz`) encounter target labels before their final byte offsets are known.

| Pass Step | Action | Data Structure |
| :--- | :--- | :--- |
| **1. Emit Jump** | Write jump opcode and zero-initialized offset bytes into `EmitBuffer`. | Append `(label-sym . patch-offset)` to Pass-Based Arena fixup list. |
| **2. Bind Label** | Record current `EmitBuffer` byte offset when `(label <sym>)` is reached. | Insert `(label-sym . target-offset)` into symbol/label table. |
| **3. Resolve Fixups** | At function or module end, compute `target-offset - next-inst-offset` and overwrite placeholder bytes. | Reset Pass-Based Arena fixup list upon completion. |

---

## 6. Executable Container Generation

To eliminate external linkers (`ld`, `link.exe`), the Pino IR backend prepends a minimal OS executable header directly to the emitted machine code buffer before flushing to disk.

| Host OS & Format | Header Size | Execution & System Call Strategy |
| :--- | :--- | :--- |
| **Linux (`x86_64` / `arm64`) — ELF64** | **120 bytes** | Single `PT_LOAD` segment mapped RWX (`flags = 7`) at `0x400000`; entry at `0x400078`. Direct `syscall` / `svc #0` instructions. |
| **macOS (`arm64`) — Mach-O** | **~448 bytes** | `__PAGEZERO` and `__TEXT` load commands; dynamically linked against `libSystem.B.dylib` (raw syscalls are unstable on macOS). Requires ad-hoc `codesign -s -`. |
| **Windows (`x86_64`) — PE32+** | **~512 bytes** | Minimal DOS stub + PE header + single `.text` section + minimal Import Directory importing `kernel32.dll` (`VirtualAlloc`, `CreateFileA`, `ReadFile`, `WriteFile`, `CloseHandle`, `ExitProcess`). |

---

## 7. Bootstrapping & Self-Hosting Roadmap

Replacing LLVM IR in Stages 1 and 2 updates the repository layout under `bootstrap/` and removes `llc` from the bootstrap trust chain:

1. **M0 — Assembly Seed Lowerer (`bootstrap/stage1-pino/`):**
   * Implement the S-expression Reader, symbol interner, bump allocator, Pino IR lowerer, and OS binary emitter in minimal `x86_64` and `arm64` assembly (~800–1,200 lines per target).
   * Deprecate `bootstrap/stage1-ll/*.ll` and external LLVM build scripts.
2. **M1 — Stage 1 Compiler in Koivu Scheme (`bootstrap/stage1-scm/`):**
   * Implement the macro-free Stage 1 compiler (`koivu-seed.scm`) in Stage 1 Scheme, lowering `.scm` directly into Pino IR (`.pino`).
   * Compile `koivu-seed.scm` with the assembly seed to produce a self-hosted `koivu-seed` binary.
3. **M2 — Stage 2 Bridge (`bootstrap/stage2-bridge/`):**
   * `koivu-seed` compiles `koivu-bridge.scm` (adding hygienic macros and `flat-vector` support) via Pino IR directly into a standalone `koivu-bridge` executable with zero external tool dependencies.
4. **M3 — Stage 3 Production Core (`src/`):**
   * `koivu-bridge` compiles the Stage 3 Nanopass compiler (`src/`), which introduces linear-scan register allocation, SSA optimizations, and LLVM IR (`.ll`) emission for production targets (`C`, `C++`, `Rust`, `Swift`).
