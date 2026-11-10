## LLVM IR AST Representation in Stage 1 Compiler Memory

**Status:** Architecture Blueprint  

**Component:** Koivu Backend  

### Architectural Invariant
When the Koivu compiler infrastructure transitions from textual `.ll` file pretty-printing to native machine-code emission, the compiler must build a formal, structured **Abstract Syntax Tree (AST)** directly within the memory space of the Stage 1 binary. 

To satisfy the **Stage 1 Simplicity & Auditability** priority, this representation avoids complex, pointer-heavy graph models or dynamic objects. Instead, the formal internal AST uses explicit, tag-indexed, fixed-length structural lists. This allows the compiler's code-generation backends to utilize transparent, predictable position-based pattern matching when translating the intermediate tree into target machine code.

---

### Standalone Memory Schema: `(koivu backend s-llvm-ir)` Internal AST Tags

Every node in the formal LLVM IR AST is explicitly typed via a distinct semantic prefix tag. This design separates types, registers, and operations into uniform fields.

To enforce absolute namespace isolation between intermediate expression parsing and low-level binary backend modules, 
all in-memory data descriptors inside the compiler core must use the explicit `ast-s-llvm-ir-` structural prefix convention.

#### In-Memory Node Tag Definitions
*   `(ast-s-llvm-ir-block <label-sym> (<instruction-nodes-list>))`  
    *Aggregates a sequence of linear instructions within a named basic block boundary.*
*   `(ast-s-llvm-ir-instr <opcode> <dest-val> <type> <op1-val> <op2-val>)`  
    *Represents a strict, fixed-length five-slot primitive instruction node layer.*
*   `(ast-s-llvm-ir-val <kind-sym> <type-sym> <identifier-or-literal>)`  
    *Represents an explicitly typed value descriptor node targeting operands or constants.*

#### Complete Code Graph In-Memory Specimen

The following code block provides the precise conceptual trace of a complete, unvalidated two-instruction basic block (performing an explicit index field addition and returning the result) as it sits inside the Stage 1 compiler's memory right before the machine code generator is executed.


The following blueprint demonstrates how a data-flow sequence resides inside the Stage 1 host memory environment prior to native machine serialization passes:

```scheme
;; Mental Model: Formal LLVM IR AST Structure inside Stage 1 Memory
'(ast-s-llvm-ir-block mathematical_entry
   ((ast-s-llvm-ir-instr add
                       (ast-s-llvm-ir-val reg i32 %res)
                       i32
                       (ast-s-llvm-ir-val reg i32 %a)
                       (ast-s-llvm-ir-val reg i32 %b))
    
    (ast-s-llvm-ir-instr ret
                       void
                       i32
                       (ast-s-llvm-ir-val reg i32 %res)
                       none)))
```

---

### Node Specifications & Layout Grammars

#### 1. Instruction Node (`ast-s-llvm-ir-instr`)
Instruction nodes have a rigid five-slot layout containing the opcode, the single static assignment (SSA) destination value node, the operational data type, and exactly two operand slots.
```scheme
(ast-s-llvm-ir-instr <opcode-sym> <dest-val-node> <type-sym> <op1-val-node> <op2-val-node>)
```
*   *Opcode Bounds:* Must be a valid operational symbol matching LLVM primitive invariants (e.g., `add`, `sub`, `getelementptr`, `load`).
*   *Void Operations:* Terminators or side-effect instructions that do not produce an assignment register (e.g., `ret`, `store`) bind a constant symbol `'void` into the `<dest-val-node>` slot.
*   *Operand Padding:* Unary or parameter-less operations fill vacant operand fields with a terminal symbol `'none`.

#### 2. Value Descriptor Node (`ast-s-llvm-ir-val`)
Every literal constant, global reference, or register tracking operand is normalized into a strict three-slot layout.
```scheme
(ast-s-llvm-ir-val <kind-sym> <type-sym> <identifier-or-literal>)
```
*   *Kind Boundaries:* The `<kind-sym>` must be one of three explicit structural variations: `'reg` (local SSA register), `'global` (global address label), or `'literal` (immediate value constant).

#### 3. Basic Block Container Node (`ast-s-llvm-ir-block`)
Basic blocks aggregate a distinct, linear sequence of instruction nodes bound within a local control-flow boundary.
```scheme
(ast-s-llvm-ir-block <label-sym> (<instruction-nodes-list>))
```

---

### Design Anti-Patterns
To preserve maximum visibility for human code auditors and protect parsing simplicity, the following features are strictly prohibited inside the Stage 1 AST architecture:
*   **Cyclic Native Graph Pointers:** Nodes must never contain circular, cross-linked heap references to parent or neighboring basic blocks. The graph remains a strictly nested, forward-traversable list.
*   **Implicit Typings:** Instruction nodes cannot omit explicit type descriptors (`i32`, `i64`, `ptr`), ensuring the downstream backend can calculate target instruction data sizes directly from standardized field offsets.

