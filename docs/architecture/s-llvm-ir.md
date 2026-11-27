# Koivu In-Memory LLVM IR (S-LLVM IR)

**Status:** Architecture Blueprint  
**Component:** Koivu Backend  

Stage 3 and every production compiler built on it hold their intermediate representation as LLVM IR, in memory, for the whole of a compilation. This document specifies that in-memory form: the node layout, the library that builds it, and the two consumers that read it. It is the only description of LLVM IR as data in the project.

Two facts bound the scope:

* **It exists in the production stack only.** The seed and the sapling build Pino IR and write a `.pino` image; neither contains any part of this ([Backend](backend.md), decision 1).
* **It is not a second IR.** There is one LLVM IR in Koivu, and this is its in-memory form. A `.ll` file is the same IR written as text at the edges; it is never an intermediate the stack reads back.

---

## 1. Producers and Consumers

| Role | Component | Notes |
| :--- | :--- | :--- |
| **Producer** | constructors in `(koivu backend llvm-ir)` | how a pass builds IR |
| **Producer** | the `.ll` parser | the reader literal `#llvm_ir{...}` calls it, and its output is the same nodes ([Koivu Scheme](03_language.md), Reader Macros) |
| **Consumer** | the `.ll` emitter | AST -> text, for the permanent IR dump ([Backend](backend.md), section 7.1) |
| **Consumer** | the production lowering stack | `analysis`, `transforms` and `codegen` traverse the same nodes with no file written ([Backend](backend.md), section 7.2) |

The last row is the reason the representation exists at all. Version A of Stage 3 builds LLVM IR in memory and lowers it itself, so no `.ll` file appears in that path ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 6, step 3). The emitter is a second consumer of the same tree, not a step the tree must pass through.

Two producers and two consumers over one tree has a consequence worth stating: a front end that builds IR with constructors and a front end that writes `#llvm_ir{...}` produce the same data, so every pass sees one shape and no pass needs to know which route an instruction arrived by.

## 2. Node Layout

Five node kinds. Each is a tagged list; the layout contains no pointers and no node is shared between parents.

| Tag | Shape |
| :--- | :--- |
| **`llvm-ir-module`** | `(llvm-ir-module (<declaration> ...) (<function> ...))` |
| **`llvm-ir-fn`** | `(llvm-ir-fn <name> (<param> ...) <return-type> (<block> ...))` |
| **`llvm-ir-block`** | `(llvm-ir-block <label> (<instruction> ...))` |
| **`llvm-ir-instr`** | `(llvm-ir-instr <opcode> <dest> <type> (<operand> ...))` |
| **`llvm-ir-val`** | `(llvm-ir-val <kind> <type> <identifier-or-literal>)` |

`<kind>` is one of `reg`, `global` or `literal`. `<dest>` is an `llvm-ir-val` node of kind `reg`, or the symbol `void` when the instruction produces no value. Each `<operand>` is an `llvm-ir-val` node. A parameter is an `llvm-ir-val` of kind `reg`.

### Why the operand list is variadic

Instruction arity is a property of the opcode, not of the node. `add` takes two operands; `ret` and `br` take one; `store` takes two and produces no value; `getelementptr` takes a base and a list of indices; `call` and `phi` take any number. A fixed-arity node needs padding symbols for the short cases and still fails on the long ones - an earlier draft used a five-slot node padded with `void` and `none`, and it could not represent four of the fifteen constructors in section 3.

One variadic slot represents all of them, and both padding symbols disappear.

### No sigils in the data

A register is named `res`, not `%res`; a global is named `koivu_fast_add`, not `@koivu_fast_add`. The `%` and `@` are notation, and notation belongs to the emitter (section 4). Keeping them out of the data also keeps every symbol a readable Koivu identifier: `@` is not a legal initial character in R6RS, so `'@koivu_fast_add` cannot be read at all.

### A worked tree

```scheme
(llvm-ir-module
  ()
  ((llvm-ir-fn koivu_fast_add
     ((llvm-ir-val reg i32 a) (llvm-ir-val reg i32 b))
     i32
     ((llvm-ir-block entry
        ((llvm-ir-instr add
           (llvm-ir-val reg i32 res)
           i32
           ((llvm-ir-val reg i32 a) (llvm-ir-val reg i32 b)))
         (llvm-ir-instr ret void i32 ((llvm-ir-val reg i32 res)))))))))
```

## 3. The `(koivu backend llvm-ir)` Library

The name follows the other production backend libraries - `(koivu backend analysis)`, `(koivu backend transforms)`, `(koivu backend codegen)`, `(koivu backend machine-code-layer)` - so the layer name is the last element. No prefix is needed to separate IR construction from other LLVM work: there is no other LLVM library for it to be confused with.

```scheme
(define-library (koivu backend llvm-ir)
  (import (scheme base) (scheme write))
  (export make-llvm-ir-module
          make-llvm-ir-declare
          make-llvm-ir-function
          make-llvm-ir-block
          make-llvm-ir-assign
          make-llvm-ir-icmp
          make-llvm-ir-cast
          make-llvm-ir-gep
          make-llvm-ir-load
          make-llvm-ir-store
          make-llvm-ir-phi
          make-llvm-ir-br
          make-llvm-ir-cbr
          make-llvm-ir-ret
          emit-llvm-ir-instruction
          emit-llvm-ir-module))
```

### Constructors

Constructors return nodes. They never emit text and never consult a target: what a pass builds is data, and the emitter is the only code that knows how LLVM IR is spelled.

| Constructor | Result |
| :--- | :--- |
| `(make-llvm-ir-module declarations functions)` | `llvm-ir-module` |
| `(make-llvm-ir-declare return-type name param-types)` | one entry in a module's declaration list |
| `(make-llvm-ir-function name params return-type body)` | `llvm-ir-fn`; `body` is a list of blocks |
| `(make-llvm-ir-block label instructions)` | `llvm-ir-block` |
| `(make-llvm-ir-assign dest opcode type op1 op2)` | `llvm-ir-instr` for a two-operand value-producing opcode (`add`, `sub`, `mul`, ...) |
| `(make-llvm-ir-icmp dest condition type op1 op2)` | `llvm-ir-instr` for `icmp` |
| `(make-llvm-ir-cast dest opcode src-type value dest-type)` | `llvm-ir-instr` for `bitcast`, `inttoptr`, `ptrtoint`, ... |
| `(make-llvm-ir-gep dest base-type base index-list)` | `llvm-ir-instr` for `getelementptr` |
| `(make-llvm-ir-load dest type src)` | `llvm-ir-instr` for `load` |
| `(make-llvm-ir-store type value dest)` | `llvm-ir-instr` for `store`; the destination slot is `void` |
| `(make-llvm-ir-phi dest type incoming)` | `llvm-ir-instr` for `phi`; `incoming` is a list of `(value block)` pairs |
| `(make-llvm-ir-br label)` | `llvm-ir-instr` for `br`; the destination slot is `void` |
| `(make-llvm-ir-cbr cond true-label false-label)` | `llvm-ir-instr` for a conditional `br`; the destination slot is `void` |
| `(make-llvm-ir-ret type value)` | `llvm-ir-instr` for `ret`; the destination slot is `void` |

`make-llvm-ir-assign` and the opcode-specific constructors overlap deliberately. `assign` covers the two-operand arithmetic and logic family, where every instruction has the same shape; the rest exist because their operand shapes differ. The boundary is the operand shape, not the number of opcodes.

### Emitters

| Function | Effect |
| :--- | :--- |
| `(emit-llvm-ir-instruction instr port)` | writes one instruction line |
| `(emit-llvm-ir-module module port)` | writes a complete `.ll` file |

The emitter is the serialisation layer and the only place where spelling exists. It adds `%` to a register, `@` to a global, `entry:` to a block label, and the type suffixes LLVM requires. Emission is deterministic: stable ordering, no timestamps, no absolute paths, because the fixpoint check compares output byte for byte ([Backend](backend.md), section 8, criterion 4).

**The emitter's output is ASCII.** A frontend compiled by Stage 3 may accept Unicode input ([Frontends](07_frontends.md)), and a non-ASCII code point that survives into the IR is written as a `\XX` byte escape, which the LLVM format provides for. So a `.ll` file is ASCII whatever the input encoding was, and the byte comparisons above stay exact.

```scheme
(call-with-output-file "output.ll"
  (lambda (port)
    (emit-llvm-ir-module math-module port)))
```

## 4. Why the Notation Lives in the Emitter

Two ways to place `%` and `@` were possible, and only one of them is a single source of truth.

* **In the data**, as `'%res` and `'@koivu_fast_add`. Rejected. The parser would have to strip the sigil on the way in and the emitter would have to trust it on the way out, so two pieces of code would be responsible for notation and could disagree. The symbol `@koivu_fast_add` is also not a legal Koivu identifier, so the IR could not be written as source at all.
* **In the emitter.** Chosen. The data carries identity, the emitter carries spelling, and there is one function to change if a spelling ever needs to differ.

The same reasoning fixes the boundary with the parser: the parser strips the sigils as it reads, the constructors never see them, and the emitter puts them back. That is the only asymmetry in the design, and it is deliberate - text is the foreign format, so text is what gets translated at the edge.

## 5. Rejected Alternatives

Recorded so they are not re-derived.

* **A second representation, with a conversion pass between the constructors and the code generator.** Rejected. It gives the compiler two shapes for one IR, and the pass between them must be kept in step with both. The constructors build the node the lowering stack traverses; there is nothing to convert. This also keeps Stage 3's own rule that its IR is ordinary Lisp structures in the arenas, with one representation to reason about rather than two ([Stage 3](06_stage3_production_core.md)).
* **IR assembled as pre-formatted text fragments.** Rejected. A pass that builds `"  %res = add i32 %a, %b\n"` has no tree to analyse, so the optimiser would have to parse its own output, and the parser would exist twice under two names.
* **`#llvm_ir{...}` as the only way to build IR.** Rejected. It is a notation for literals ([Koivu Scheme](03_language.md), Reader Macros). IR that a pass computes - anything whose operands are not known until the pass runs - cannot be written as text, and the reader literal is not available in the seed or the sapling anyway.

## 6. What This Document Does Not Cover

| Topic | Where |
| :--- | :--- |
| The `.ll` parser, and why there is exactly one | [Parsing LLVM IR](notes_on_llvm_ir_parsing.md) |
| Target descriptions and machine-code generation | [Backend](backend.md), sections 6 and 7.2 |
| `koivu-llc`, the tool that consumes `.ll` | [Backend](backend.md), section 7.3 |
| Pino IR, the bootstrap IR | [Pino IR](pino.md) |

This document says nothing about optimisation, and that is deliberate: passes in `(koivu backend analysis)` and `(koivu backend transforms)` read and rewrite these nodes, and each pass has its own specification. The layout is the only thing they share.

## 7. Decisions

| # | Decision | Resolution | Consequence |
| :--- | :--- | :--- | :--- |
| 1 | In-memory form of LLVM IR | **Tagged lists, five node kinds** | no pointers between nodes, no sharing, and the same tree serves the emitter and the lowering stack |
| 2 | Instruction arity | **Variadic operand list** | `call`, `phi`, `gep`, `store` and `add` share one node shape; no `void` or `none` padding |
| 3 | Register and global sigils | **Not in the data** | every symbol stays a readable Koivu identifier; notation has one owner, the emitter |
| 4 | Library name | **`(koivu backend llvm-ir)`** | matches the other backend layers; no prefix is needed to tell it from LLVM tooling |
| 5 | Number of representations | **One** | no conversion pass between construction and code generation |
| 6 | Stages | **Stage 3 and later only** | nothing of this appears in the seed or the sapling ([Backend](backend.md), decision 1) |
