# Koivu Scheme Stage 2 (Bridge) Compiler

> **Status:** Architecture Blueprint  
> **Component:** Stage 2  

The Stage 2 Bridge Compiler is a dedicated macro-expanding utility written entirely in the minimalist Stage 1 Lisp subset. Its exclusive responsibility is to ingest the high-level, macro-heavy R6RS source files of the Stage 3 Production Core and emit macro-eliminated, statically structured Scheme code that can be easily parsed by a primitive compiler backend.

---

## 1. Operational Context and Lifecycle

Stage 2 executes entirely within the execution space of the Stage 1 Seed Interpreter. Because Stage 1 lacks native macro processing, Stage 2 does not use syntax hooks or compiler macros. Instead, it operates strictly as a user-level program that processes source files as structured data pipelines:

```
[R6RS Library Source] ──► [Stage 2 Bridge (Running in Stage 1)] ──► [Core S-Expressions]
```

To preserve the ABS_MEM_LIMIT_BYTES heap ceiling and guarantee deterministic termination, Stage 2 enforces a strict memory pipeline:
* **In-Memory Tracking:** Syntax transformations, identifier tables, and macro expansion state are maintained inside Stage 1 Cons cells and vectors.
* **Wiped State Output:** Once expansion completes, the resulting macro-eliminated S-expression tree is directly serialized to a staging file on the host file system via basic `write` system calls, and the process terminates cleanly.

---

## 2. Core Architecture Subsystems

The macro expander program is split into three decoupled operational layers to ensure code maintainability and clear inspection boundaries.

### A. Environment and Binding Layer
To guarantee the strict hygiene mandated by the R6RS dialect, the bridge tracking system must isolate variable scopes using a dual-environment model:
* **Global Environment Table:** A continuous open-addressing lookup vector matching basic core keywords (`define`, `if`, `lambda`, `set!`) and newly encountered user macros to their structural transformation definitions.
* **Lexical Scope Ribs:** A sequential chain of linked local lists representing lexical depth. When an expander pass traverses a nested structural scope, it shifts a new "rib" onto the evaluation context to manage active local variable definitions.
* **Hygienic Identifier Renamer:** A monotonic integer-indexing utility that operates like a primitive `gensym`. Any identifier introduced by a macro template is systematically alpha-converted to a unique, globally non-colliding symbol name to prevent accidental local variable capture.

### B. Pattern Matcher and Structural Transformer
The core macro compiler avoids the full complexity of an R6RS compile-time infrastructure by relying on a lightweight, deterministic pattern matching matrix:
* **Rules Parser:** Converts high-level `syntax-rules` definitions found within `define-syntax` forms into an internal, flat array structure organized strictly as `(pattern . template)` pairs.
* **Structural Matcher:** A recursive, type-validated utility function that correlates an active input expression with a macro pattern pattern. It tests identifier positions, validates structural matches, and captures repeated elements bounded by ellipsis (`...`) constraints into uniform indexed vectors.
* **Template Expander:** Replaces the captured pattern tokens back into the designated target template structure. The resulting tree is re-fed back into the transformer loop to evaluate deeply nested macro definitions.

### C. Linear Expansion Pipeline

The macro-expander executes its translation sequence across three distinct processing passes:

#### Pass 1: Library Ingestion (`read`)
The program invokes Stage 1's native `read` primitive to ingest the R6RS target compiler source file. It validates the high-level `(library ...)` envelope structure, isolates the explicit `import` dependency declarations, and decouples the top-level syntax definitions from the active library body elements.

#### Pass 2: Recursive Tree-Walk Expansion (`expand`)
The expander walks through the structured S-expression tree, querying identifiers against the active environment and updating states sequentially:
1. **Core Keywords:** If an expression hits a native primitive (`lambda`, `if`, `set!`, `define`), the tag structure is skipped over, and the utility recurses directly into the nested sub-expressions.
2. **Syntax Definitions:** If it encounters a `define-syntax` block, the pattern rules are parsed, the new macro definition is bound to the Global Environment Table, and the definition block is completely removed from the pipeline.
3. **Macro Applications:** If an expression matches an active macro binding, the expression is passed to the Template Expander, and the generated target tree is recursively processed *again* to evaluate nested macros.

#### Pass 3: Core S-Expression Emission (`write`)
Once every macro identifier has been removed and all local variable conflicts are settled via alpha-conversion, the resulting data structure is pure, un-macroed, low-level Scheme code containing only foundational forms. Stage 2 invokes the basic `write` or `display` primitive to commit this clean code block to a final file, creating an optimized code asset ready for Stage 3 compilation.

---

## 3. Scope Boundaries and Simplifications

To ensure the Stage 2 Bridge source remains compact, easily maintainable, and fully auditable, several high-level language capabilities are explicitly dropped from the expander framework:
* **No `syntax-case` Expansion:** Stage 2 is built to parse only `syntax-rules` macros. Complex compile-time imperative computation inside macros is deferred to Stage 3.
* **No Local Macros (`let-syntax` / `letrec-syntax`):** The expander only supports top-level macro declarations. This limits environment lookups to a uniform, clean global table workflow.
* **Strict Monomorphic Assertions:** The expander does not manage structural dynamic types or implicit conversions; it expects structurally correct R6RS compiler source code layout and aborts via raw `(error)` traps upon encountering irregular code graphs.


