# Koivu Scheme Stage 2 (Sapling) Compiler

**Status:** Architecture Blueprint  

**Component:** Stage 2  

> Mr. Gibbs: Then, on the fourth day, he roped himself a couple of sea turtles, lashed 'em together and made a raft.<br>
> Will Turner: He roped a couple of sea turtles.<br>
> Mr. Gibbs: Aye. Sea turtles.<br>
> Will Turner: What did he use for rope?<br>
> Jack Sparrow: (from beside them) Human hair.<br>
> (pause)<br>
> Jack Sparrow: From my back.
    
The Stage 2 Sapling Compiler is a macro-expanding compiler written in the Stage 1 Lisp subset. It compiles the Stage 3 Production Core: it reads Stage 3's source, expands its hygienic macros, runs the front end over the result, and writes a `.pino` image that `koivu-vesi` lowers into the Version A executable ([Koivu Vesi](koivu-vesi.md)).

The sapling is not a second compiler implementation. It is **one source set with the seed's Scheme front end plus a macro expander**, built into a second program.

---

## 1. One Source Set, Two Programs

The seed is written in C before M2 and in Scheme afterwards ([Stage 1 (Seed)](04_stage1_seed.md), introduction). That Scheme front end - reader, interner, arena, type checker and Pino emitter - is written once, and two programs are built from it:

| Program | Sources | Built by | Job |
| :--- | :--- | :--- | :--- |
| the sapling | the Scheme front end + the macro expander | the C seed, at M0 | compiles Stage 3 source to an image |
| the seed, from M2 | the Scheme front end | a compiler produced by the chain | compiles the sapling's source to an image |

This is why the sapling exists, and why it retires: it is the vehicle by which the Scheme front end enters the chain. Between M0 and M2 the front end exists in two languages - C in the seed, Scheme in the sapling - which is the same overlap [Backend](backend.md), section 9, decision 4 already accepts for the seed, closed by the same kind of criterion. Once Version A exists, nothing needs the sapling: Stage 3 compiles Stage 3, and the sapling is retired along with the C scaffold.

Three consequences are worth stating:

* **No duplicate compiler.** The sapling does not reimplement reading, type checking or Pino emission. Those files are the seed's files, compiled into a different program.
* **The front end is written earlier, not twice.** It has to be written eventually; writing it early is what lets the sapling compile Stage 3 in the meantime.
* **The sapling is portable.** It writes an image and no machine code, so it is one program for every host, exactly as the seed is ([Koivu Vesi](koivu-vesi.md), section 1). Only Vesi is per-host.

### The Language It Accepts

The sapling compiles Stage 3's source, so its language is the subset Stage 3's source actually uses, plus hygienic macros ([Koivu Scheme](03_language.md), Purpose and Scope).

* **The wider integer types are in.** Stage 3's source uses them, so the sapling implements them ([Koivu Scheme](03_language.md), Stage 2 Data Types).
* **Its input is ASCII.** The sapling's reader is the seed's reader, so Stage 3's own source is ASCII - identifiers, literals and comments alike ([Koivu Scheme](03_language.md), Character Encoding). This is a statement about the language Stage 3 is *written in*, not about the languages it compiles: a frontend built by Stage 3 may accept Unicode in its own input, and at minimum in comments ([Frontends](07_frontends.md)).
* **`flat-vector` is not.** Stage 3's own source contains no `define-flat-vector` form, so the form never reaches the sapling and the sapling needs no support for it ([Flat Vector](flat-vector.md); [Koivu Scheme](03_language.md), Purpose and Scope).
* **`syntax-case` is not.** `syntax-rules` is the whole of the macro language ([section 4](#4-scope-boundaries-and-simplifications)).

## 2. Operational Context and Lifecycle

Stage 2 is a binary produced by Stage 1. Because Stage 1 has no native macro processing, the sapling uses no syntax hooks and no compiler macros: expansion is a user-level program over S-expressions, and the expander is ordinary Lisp code operating on ordinary data.

```
[Stage 3 source] ──► [read + include] ──► [expand] ──► [front end] ──► image (.pino) ──► Vesi ──► Version A
```

* **No staging file.** Expansion produces an in-memory tree that the front end consumes directly. Nothing is written between the two phases; the only file the sapling writes is the image.
* **Arena, no GC.** The sapling allocates from a bump arena and never frees, exactly as the seed does ([Stage 1 (Seed)](04_stage1_seed.md), section 2). Expansion state - environments, ribs, renamed identifiers - lives in the same arena as the AST it is transforming.
* **`include`, not `import`.** Multi-file Stage 3 source is assembled by the reader through `include` ([Koivu Scheme](03_language.md), Multi-File Programs). There is no library envelope, no export list and no import set, because Koivu has no separate compilation ([Backend](backend.md), decision 12).

## 3. What the Sapling Adds

Three subsystems, and nothing else. Reading, type checking and image emission belong to the shared front end ([Stage 1 (Seed)](04_stage1_seed.md), sections 4 to 7), and this section describes only what is new.

### A. Environment and Binding Layer

To guarantee the strict hygiene mandated by the R6RS dialect, the sapling tracking system must isolate variable scopes using a dual-environment model:
* **Global Environment Table:** A continuous open-addressing lookup vector matching basic core keywords (`define`, `if`, `lambda`, `set!`) and newly encountered user macros to their structural transformation definitions.
* **Lexical Scope Ribs:** A sequential chain of linked local lists representing lexical depth. When an expander pass traverses a nested structural scope, it shifts a new "rib" onto the evaluation context to manage active local variable definitions.
* **Hygienic Identifier Renamer:** A monotonic integer-indexing utility that operates like a primitive `gensym`. Any identifier introduced by a macro template is systematically alpha-converted to a unique, globally non-colliding symbol name to prevent accidental local variable capture.

### B. Pattern Matcher and Structural Transformer

The expander avoids the full complexity of an R6RS compile-time infrastructure by relying on a lightweight, deterministic pattern matching matrix:
* **Rules Parser:** Converts high-level `syntax-rules` definitions found within `define-syntax` forms into an internal, flat array structure organized strictly as `(pattern . template)` pairs.
* **Structural Matcher:** A recursive, type-validated utility function that correlates an active input expression with a macro pattern. It tests identifier positions, validates structural matches, and captures repeated elements bounded by ellipsis (`...`) constraints into uniform indexed vectors.
* **Template Expander:** Replaces the captured pattern tokens back into the designated target template structure. The resulting tree is re-fed back into the transformer loop to evaluate deeply nested macro definitions.

### C. Expansion Pipeline

Two passes. There is no third: compiling is the front end's job, not a pass of the expander.

#### Pass 1: Read (`read`)

The reader loads the root source and splices every `include` textually, so the whole program is present as one tree before expansion begins. No macro can produce an `include`, and no include path can depend on expansion ([Koivu Scheme](03_language.md), Multi-File Programs).

#### Pass 2: Recursive Tree-Walk Expansion (`expand`)

The expander walks the tree, querying identifiers against the active environment and updating state sequentially:

1. **Core Keywords:** If an expression hits a native primitive (`lambda`, `if`, `set!`, `define`), the tag structure is skipped and the utility recurses into the nested sub-expressions.
2. **Syntax Definitions:** If it encounters a `define-syntax` block, the pattern rules are parsed, the new macro definition is bound to the Global Environment Table, and the definition block is removed from the tree.
3. **Macro Applications:** If an expression matches an active macro binding, the expression is passed to the Template Expander, and the generated tree is recursively processed *again* to evaluate nested macros.

What comes out of Pass 2 is a tree with no macro identifiers and no identifier collisions. It is handed straight to the front end, which type-checks it and writes the image.

## 4. Scope Boundaries and Simplifications

To keep the Stage 2 Sapling source compact, maintainable and fully auditable, several high-level language capabilities are explicitly dropped from the expander:
* **No `syntax-case` Expansion:** Stage 2 parses only `syntax-rules` macros. Complex compile-time imperative computation inside macros is deferred to Stage 3.
* **No Local Macros (`let-syntax` / `letrec-syntax`):** The expander supports top-level macro declarations only. This limits environment lookups to a uniform global table workflow.
* **No Library System:** There is no `(library ...)` envelope, no `export` list and no `import` set. A program is one root source plus its `include`d files ([Koivu Scheme](03_language.md), Multi-File Programs).
* **Strict Monomorphic Assertions:** The expander does not manage structural dynamic types or implicit conversions; it expects structurally correct Stage 3 source layout and aborts via raw `(error)` traps upon encountering irregular code graphs.
