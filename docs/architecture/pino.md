# Pino IR Architecture Blueprint

> **Status:** Architecture Blueprint<br>
> **Component:** Stage 1 Core / Stage 2 Sapling / Bootstrap Backend

> Capt. Jack Sparrow: Put it away, son. It's not worth you getting beat again.<br>
> Will Turner: You ignored the rules of engagement. In a fair fight, I'd kill you.<br>
> Capt. Jack Sparrow: That's not much incentive for me to fight fair, is it?

Pino IR (Finnish *pino*: "stack") is a minimalist, S-expression-encoded stack machine intermediate representation used by Stage 1 (Koivu Seed) and Stage 2 (Koivu Sapling). It decouples the bootstrap pipeline from LLVM toolchains and from text-heavy SSA generation, and it gives both stages one fixed, mechanically checkable mapping to native machine code.

LLVM IR remains the interchange and lowering format of Stage 3 (Production Core) and later.

---

## 1. Role and Pipeline Position

| | Pino IR | LLVM IR |
| :--- | :--- | :--- |
| **Produced by** | Stage 1, Stage 2 | Stage 3 and later |
| **Form** | S-expressions describing a stack machine: in memory while a compiler runs, written out as a `.pino` image | textual `.ll` |
| **Lowered by** | `koivu-vesi`, from the image the compiler wrote ([Koivu Vesi](koivu-vesi.md)) | `koivu-llc`, or LLVM's own tools |
| **Optimising** | no - one fixed byte template per instruction | yes - full production pipeline |
| **Leaves the process?** | yes, as a `.pino` image | yes, as a `.ll` file |

**No evaluator is required.** Stage 1 and Stage 2 build Pino IR and write it out as an image; nothing interprets Scheme at build time, and nothing interprets Pino IR either. The image is lowered by `koivu-vesi`, a program of its own ([Koivu Vesi](koivu-vesi.md)).

### Textual `.pino` is the interface to the lowerer

An image is what a front end hands to the lowerer: one `.pino` file per program, written by the compiler and read by `koivu-vesi`. It is a specified format rather than a printable debugging aid, and [Koivu Vesi](koivu-vesi.md), section 2 fixes what it may contain and how it is printed.

What that means in practice:

* **Another program reads it.** A malformed image is rejected with a diagnostic; nothing is guessed at.
* **It is printed canonically.** One form per line, one instruction per line, fixed spacing and number format, so two images can be compared byte for byte.
* **It is versioned.** An incompatible change introduces a different head symbol instead of reinterpreting the old one.

It is also still what it always was: a readable artifact. A reviewer can read an image and see the instruction sequence a compiler produced without running anything, and the committed `.s` files serve the same reader one level lower ([Seed Artifacts](08_seed_artifacts.md), section 3).

**It is not a compatibility promise.** An image is an internal exchange between two programs of the same release. No third party is expected to write one by hand, and no compatibility across releases is offered beyond the versioned head symbol.

### Two output forms, both from the lowerer

Neither the seed nor the sapling writes anything but an image, and neither carries a printer of any kind. Everything a human reads comes from `koivu-vesi`, which owns the encoder and can therefore render the same instructions as bytes or as text:

* **`.pino`** is what a compiler writes and the lowerer reads. It is the only form that crosses a component boundary.
* **`.s`** is for people, not for the pipeline. The committed seed assembly ([Seed Artifacts](08_seed_artifacts.md), section 3) is produced by `koivu-vesi` from the same image the binary is produced from, so the two cannot drift apart: they are two renderings of one encoding pass. A printer inside a front end would restate every byte template in a second representation, and that representation would have to be audited alongside the first.

**The stack-depth verifier lives in the lowerer too.** With an implicit operand stack, an unbalanced sequence is silent memory corruption rather than an error, so `koivu-vesi` checks the balance of every function when it loads an image, before any byte is emitted ([Koivu Vesi](koivu-vesi.md), section 4). That is the last point at which the mistake is still cheap to report, and it is reached by every program the chain builds, not only by the ones a developer chose to check.

### Why the bootstrap stages do not use LLVM IR

Considered and rejected: keeping LLVM IR in Stages 1 and 2, as the production stages do.

* It requires `llc` - an external, opaque, optimizing translator - in the bootstrap chain, so the seed's machine code cannot be mechanically derived from its source. That defeats the auditability priority recorded in [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2.
* SSA and typed IR are the wrong tools for a seed that must stay small: they demand value numbering, virtual registers and a real lowering pipeline.
* A stack machine needs no register allocation, no scheduling and no spilling, so lowering becomes a single linear pass over fixed byte templates - which is exactly what a small, auditable seed needs.

## 2. Memory and Data Layout Model

Pino IR preserves the Stage 1 data representation invariants defined in [Koivu Scheme Language](03_language.md) and [Stage 1 (Seed)](04_stage1_seed.md).

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
| **Environment Frame** | Referenced through the Environment Pointer role. | `{ ptr parent_env, word64 slot0, word64 slot1, ... }`. |

### Pinned Machine State

The lowerer keeps no stack frames, no spill slots and no register allocator. Instead it relies on three pieces of mutable machine state held continuously across all generated functions. These are **roles, not registers**:

| Role | Invariant | Modified by |
| :--- | :--- | :--- |
| **Operand Stack Pointer** | points at the topmost occupied word of the Pino operand stack | every instruction with a non-empty stack effect |
| **Environment Pointer** | points at the active lexical environment frame | `(env-push)`, `(env-pop)`, `(call)`, `(tail-call)` |
| **Arena Pointer** | points at the next free 8-byte aligned byte in the bump arena | `(alloc)`, `(env-push)`, `(make-closure)` |

Any concrete mapping of these roles must satisfy three requirements:

1. **Base-address usability.** The operand stack pointer and the arena pointer appear as base registers in the load and store templates, with 8-byte granularity, so the mapping must permit base addressing that is not 16-byte aligned.
2. **Survival across generated calls.** The seed defines the calling convention for its own generated code, so it may require whatever it needs rather than inheriting an external ABI. The environment pointer is saved and restored explicitly by the `(call)` sequence (section 4.5); the operand stack pointer and the arena pointer are never touched by a callee except through the balance of its own stack effects. No role depends on a host ABI to be preserved.
3. **No clash with the host.** The mapping must stay valid at the process entry point and at the syscall boundary, where the host OS - not the seed - decides what a register means.

Which concrete resource realises a role is a **target description** decision ([Backend](backend.md), section 6), not part of the ISA. The first two targets make different choices:

| Role | `x86_64` (example) | `arm64` (example) |
| :--- | :--- | :--- |
| Operand Stack Pointer | `RSP` | `X21` |
| Environment Pointer | `R12` | `X19` |
| Arena Pointer | `R13` | `X20` |

**Why the operand stack pointer is not portable.** `x86_64` can put the operand stack on the hardware stack pointer: `push` and `pop` have one-byte encodings, and generated code calls nothing but itself and the host's syscall entry, so no external alignment rule applies to `RSP` there. On `arm64` the hardware stack pointer must be 16-byte aligned whenever it is used as a base address register, while the operand stack advances in 8-byte units - so `SP` is reserved strictly for call and return addresses and a general register carries the operand stack. A target description states which of the two shapes it has, and the lowering templates follow from that statement.

The asymmetry has one observable consequence: on `x86_64` a return address sits on the same stack as the operands, while on `arm64` the two stacks are separate. Both are correct as long as the operand stack is balanced at every call boundary - which is exactly what the static stack-depth verifier (section 1) exists to check.

## 3. Lexical and Structural Syntax

A Pino module is a flat S-expression list containing top-level symbol declarations, function definitions, and linear instruction sequences.

```lisp
(pino-module
  (symbols "quote" "if" "cons" "car" "cdr")

  (fn entry (0)
    (push-fn main)
    (call 0)
    (syscall exit))

  (fn main (0)
    (push-i32 10)
    (push-i32 20)
    (add)
    (ret)))
```

### Top-Level Forms

* `(pino-module <form> ...)`: Root container for a compilation unit.
* `(symbols <string> ...)`: Declares interned string literals placed in the read-only data segment at startup.
* `(fn <symbol> (<param-count>) <inst> ...)`: Declares a compiled procedure with fixed arity `<param-count>`.

Arity is always an explicit integer. Variable arity is not part of the ISA.

### The First Function Is `entry`

An image always begins with a procedure named `entry`, which calls `main` and passes its return value to the host exit primitive. The container's entry field is a fixed offset at the start of the code (section 6), so the ordering rule is what makes the entry a fact of the image rather than a consequence of whatever the front end happened to emit first. Vesi checks the rule when it loads an image ([Koivu Vesi](koivu-vesi.md), section 4).

`main` stays an ordinary arity-0 procedure that returns. This is the point of the rule rather than an incidental detail: if `main` were the entry and ended with `(syscall exit)` instead of `(ret)`, then exactly one procedure in every program would be exempt from the calling convention, and no verifier could express that exemption - at process entry the return register holds nothing, so a stray `(ret)` in `main` would jump through garbage on `arm64` and pop garbage on `x86_64`. With `entry` first, `main` returns normally and the three instructions above are the only place the process exits.

`entry` uses nothing but `(push-fn)`, `(call)` and `(syscall exit)`: the return value `(call 0)` leaves on the stack becomes the exit status argument, so the sequence needs no instruction the ISA does not already have and no special case in the front end.

The name is internal to the image. The container's entry is a byte offset, and Koivu's container writers carry no symbol table, so `entry` is not the host's `_start` symbol and does not pretend to be one.

## 4. Instruction Set Architecture (ISA)

Pino IR consists of **27 instructions** partitioned into five functional groups. Every instruction specifies its exact stack transition (`before -- after`).

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

Variables are addressed statically via compile-time `(depth, index)` coordinates, matching [Stage 1 (Seed)](04_stage1_seed.md), section 4.

| Instruction | Stack Effect | Semantics |
| :--- | :--- | :--- |
| `(env-push <slots>)` | `( arg0..argN -- )` | Allocates `(slots + 1) * 8` bytes in bump arena, links `parent_env` to the current frame, pops arguments into slots, and updates the Environment Pointer role. |
| `(env-pop)` | `( -- )` | Restores the Environment Pointer role to the parent frame pointer. |
| `(env-get <depth> <idx>)` | `( -- val )` | Traverses `<depth>` parent pointers from the current frame and pushes `slot[idx]`. |
| `(env-set <depth> <idx>)` | `( val -- )` | Pops `val`, traverses `<depth>` parent pointers, and writes `slot[idx] = val`. |
| `(make-closure <fn>)` | `( -- ptr )` | Allocates 16 bytes in bump arena; writes `{ code_addr(<fn>), env_ptr }` and pushes the pointer. |

### 4.4 Memory & Primitive Data Structures

| Instruction | Stack Effect | Semantics |
| :--- | :--- | :--- |
| `(alloc <bytes>)` | `( -- ptr )` | Advances the bump pointer by `<bytes>` (8-byte aligned); aborts if `ABS_MEM_LIMIT_BYTES` is exceeded. |
| `(load64 <offset>)` | `( ptr -- val )` | Pops `ptr` and pushes the 64-bit word at `[ptr + offset]`. |
| `(store64 <offset>)` | `( ptr val -- )` | Pops `val`, pops `ptr`, and writes the 64-bit word `val` to `[ptr + offset]`. |
| `(load8 <offset>)` | `( ptr -- byte )` | Pops `ptr` and pushes the zero-extended byte at `[ptr + offset]`. |
| `(store8 <offset>)` | `( ptr byte -- )` | Pops `byte`, pops `ptr`, and writes the low 8 bits to `[ptr + offset]`. |

*(Note: Stage 1 `cons`, `car`, `cdr`, `set-car!`, `set-cdr!` and the byte-buffer operations lower directly to `(alloc 16)`, `(load64 0/8)`, `(store64 0/8)`, `(load8 0)` and `(store8 0)` in the frontend, keeping the core ISA minimal.)*

### 4.5 Control Flow & Host OS Primitives

| Instruction | Stack Effect | Semantics |
| :--- | :--- | :--- |
| `(label <sym>)` | `( -- )` | Binds symbol `<sym>` to the current byte offset in the emit buffer. |
| `(jmp <sym>)` | `( -- )` | Unconditional relative jump to `<sym>`. |
| `(jz <sym>)` | `( cond -- )` | Pops `cond`; jumps to `<sym>` if `cond == 0`. |
| `(call <arity>)` | `( closure arg0..argN -- ret )` | Saves the caller's environment pointer, loads the closure's `env_ptr`, calls `code_addr`, restores the environment pointer, and pushes the return value. |
| `(tail-call <arity>)` | `( closure arg0..argN -- )` | Overwrites the current frame's arguments, loads the closure's `env_ptr`, and jumps directly to `code_addr` (constant stack space). |
| `(ret)` | `( val -- )` | Pops the return value into the hardware return register (`RAX` / `X0`) and returns to the caller. |
| `(syscall <id>)` | `( a0..aN -- ret )` | Invokes one of the mandatory host OS primitives. |

The host OS primitives are `mmap`, `open`, `fstat`, `read`, `write`, `close` and `exit` - **seven** calls, counted individually, each with its own entry in the target's syscall table. They are the complete set the seed is allowed to use; anything else must be built on top of them.

The sapling uses the same seven. Its images are lowered by the same Vesi, which carries the syscall templates and the container writer, so it needs no primitive the seed does not already have.

**Branch encoding is target-specific, not fixed.** `(jmp)` and `(jz)` lower to the target's own relative branch instruction - `rel32` on `x86_64`, `rel19` via `b`/`cbz` on `arm64` - so the backpatch placeholder width comes from the target description rather than from the ISA. The seed's own code is far below the ±1 MB arm64 range; the encoder asserts the range instead of silently truncating, and a range overflow is a build error.

## 5. Target Lowering Specifications

Each Pino IR instruction maps to a fixed, context-free byte template. No register allocator and no instruction scheduler are required.

### 5.1 Example Lowering: `(add)` and `(jz <label>)`

```assembly
; Target: x86_64  (operand stack on RSP)
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
; Target: arm64  (operand stack on X21, SP reserved for call/return)
; Pino IR: (add)
ldr x1, [x21], #8       ; Pop 64-bit word from the operand stack
ldr x0, [x21], #8       ; Pop second 64-bit word
add w0, w0, w1          ; 32-bit fixnum addition
sxtw x0, w0             ; Sign-extend 32-bit result to 64 bits
str x0, [x21, #-8]!     ; Push 64-bit result onto the operand stack

; Pino IR: (jz target_label)
ldr x0, [x21], #8       ; Pop condition word
cbz x0, rel19_placeholder ; Compare and branch if zero (patched via backpatch list)
```

### 5.2 Forward Jump Backpatching

Because Pino IR lowers in a single linear pass, forward jumps encounter target labels before their final byte offsets are known.

| Pass Step | Action | Data Structure |
| :--- | :--- | :--- |
| **1. Emit jump** | Write the jump opcode and zero-initialized offset bytes into the emit buffer. | Append `(label-sym . patch-offset)` to the fixup list. |
| **2. Bind label** | Record the current emit-buffer byte offset when `(label <sym>)` is reached. | Insert `(label-sym . target-offset)` into the label table. |
| **3. Resolve fixups** | At function or module end, compute `target-offset - next-inst-offset` and overwrite the placeholder bytes. | Reset the fixup list on completion. |

Each fixup records the encoding width it must satisfy, taken from the target description. A displacement that does not fit the encoding is a build error, never a truncation.

## 6. Executable Container Generation

To eliminate external linkers (`ld`, `link.exe`), `koivu-vesi` prepends a minimal OS executable header to the emitted machine code before flushing to disk.

| Host OS & Format | Header Size | Execution & System Call Strategy |
| :--- | :--- | :--- |
| **Linux (`x86_64` / `arm64`) - ELF64** | **120 bytes** | Single `PT_LOAD` segment mapped RWX (`flags = 7`) at `0x400000`; entry at `0x400078`. Direct `syscall` / `svc #0` instructions. |
| **macOS (`arm64`) - Mach-O** | **~448 bytes** | `__PAGEZERO` and `__TEXT` load commands; links against `libSystem`. Vesi writes the container **unsigned**. |
| **Windows (`x86_64`) - PE32+** | **~512 bytes** | Minimal DOS stub + PE header + single `.text` section + minimal Import Directory importing `kernel32.dll` (`VirtualAlloc`, `CreateFileA`, `ReadFile`, `WriteFile`, `CloseHandle`, `ExitProcess`). |

**Vesi writes containers; it does not sign them.** Writing a Mach-O and ad-hoc signing it are two different jobs, and only the first belongs in Vesi. A code directory and a superblob are a second binary format to implement and audit, bought for no gain: the user runs `codesign --force --sign -` on the produced executable, which needs no certificate, no developer account and no network, and is the same command they already run for any locally built binary on Apple Silicon.

**The entry field is a constant.** All three headers carry one - `e_entry`, `LC_MAIN`, `AddressOfEntryPoint` - and in each case it points at the first byte of code, because an image always begins with `entry` (section 3). No front end reports an entry point and Vesi does not search for one: it writes the same fixed value into every container it produces.

Raw syscalls are not a stable interface on macOS, so the executables Vesi produces link against `libSystem`, as the seed itself does ([Platforms and Targets](01_platforms.md), section 6.1). All three container formats are in scope and none is deferred; the signing step is the user's, not Vesi's.

## 7. Bootstrapping and Self-Hosting Roadmap

The milestones below are the ones defined in [Backend](backend.md), section 1. Pino IR is the IR of the first two.

1. **M0 - the seed compiles the sapling.** The seed, written in C and built with an LLVM C compiler, implements the S-expression reader, the symbol interner, the bump allocator and the front end. It compiles the sapling source to an image, and `koivu-vesi` - also C before M2 - lowers that image to the sapling executable with no external tool.
2. **M1 - the sapling compiles Stage 3.** The sapling adds hygienic macros and compiles Stage 3 source to an image, which Vesi lowers into a working Version A, again with no external tool. It needs no `flat-vector` support, because Stage 3's own source uses no `define-flat-vector` form ([Koivu Scheme](03_language.md), Purpose and Scope).
3. **M2 - the seed becomes self-compilable.** The seed is rewritten in Scheme and rebuilt by a Koivu compiler produced by the chain, lowered through Pino. The C seed and the C Vesi are deleted. This is the boundary between early and late development ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2), and the point from which committed `.s` seeds become worth publishing ([Seed Artifacts](08_seed_artifacts.md), section 3).
4. **M3 - Stage 3 emits machine code natively.** Version A compiles Stage 3 source to Version B.
5. **M4 - fixpoint.** Version B produces a byte-identical Version C.

## 8. Open Items

None. Both items previously listed here are settled, and recorded in the sections that own them:

| Item | Resolution |
| :--- | :--- |
| Mach-O container writer | Vesi writes an unsigned Mach-O; the user ad-hoc signs the result (section 6; [Platforms and Targets](01_platforms.md), section 6.2) |
| Static stack-depth verifier | runs in `koivu-vesi` when it loads an image, before any byte is emitted ([Koivu Vesi](koivu-vesi.md), section 4) |

Nothing remains open about macOS. The last item was release process rather than this document, and it is settled: every release publishes a binary for every supported platform ([Platforms and Targets](01_platforms.md), section 2).
