# Koivu Scheme Language

**Status:** Architecture Blueprint  

**Component:** Koivu Scheme  

> Jack Sparrow: You seem somewhat familiar. Have I threatened you before?

Foundational component of Koivu is a domain-specific programming language called Koivu Scheme (a dialect of Scheme which in turn is a dialect of Lisp). 
Koivu Compiler Infrastructure will use it for writing compilers (and related tools), 
and also for all three stages of bootstrapping and for all of build management. 

Koivu Scheme is not a general-purpose programming language. It exists to write compilers, and that purpose decides what it contains; the rule is stated in Purpose and Scope below. 

Custom datatypes (`flat-vector`) in Koivu Scheme follow the spirit of Scheme (minimalism, expressive macros, and pattern matching) 
while generating high-performance, linear LLVM IR under the hood.

## Purpose and Scope

Koivu Scheme exists to write compilers. Its users are the three bootstrap stages, the build system, and the frontends and backends for whatever languages Koivu is asked to compile. It is not a language for applications, and no part of its design is justified by application code.

That purpose decides what the language contains, in both directions:

* **What compilers need is in:** symbols, cons cells, closures, byte buffers, machine-width integers, `flat-vector`, and a macro system strong enough for a nanopass pipeline - together with the memory-management tools that make those cheap and that are useless in other domains.
* **What compilers do not need is out**, however ordinary it is elsewhere in Scheme: no general-purpose library, no general garbage collector ([Stage 3](06_stage3_production_core.md)), no dynamic `eval` ([Stage 1](04_stage1_seed.md), section 4), no continuations in the bootstrap stages, and a deliberately small set of host system calls. Each of those is a recorded decision rather than an omission.

### A Feature Belongs to the Stage That Needs It

Koivu Scheme is not one language with one fixed feature set; it grows stage by stage. Each stage compiles a **subset** of the next stage's language, and the subset is fixed by what that next stage's source actually uses. The seed compiles the sapling's source, so the seed's language is what the sapling needs; the sapling compiles Stage 3's source, so the sapling's language is what Stage 3 needs.

A feature's stage therefore follows from that rule rather than from taste. `flat-vector` is the case that matters: it exists so that frontends for C-family languages can lex, parse and emit over large codebases with data-oriented layouts ([Data-Oriented Design](data_oriented_design.md)), and Stage 3's own source does not use it. Stage 3 supports `flat-vector` for the frontends it hosts, and no earlier stage has to implement it - not because that would be hard, but because nothing that runs before Stage 3 would ever contain the form.

For the same reason, a stage lacking a feature its successor has is not a defect. The seed is not an unfinished Stage 3; it is exactly as large as compiling the sapling requires.

## Dialect Baseline: R6RS Foundation

Koivu Scheme adopts the [**R6RS (Revised^6 Report on Scheme)** specification](https://r6rs.org/) as its structural dialect baseline, strictly optimized to exclude non-compiler primitives. 
R6RS is selected over other specifications for three primary reasons:

* **Static Phasing:** R6RS enforces explicit separation between macro expansion and run-time code, which lets the Stage 3 Ahead-of-Time (AOT) batch compiler resolve a program before code generation. Koivu keeps that phasing discipline but not the library system that carries it in R6RS: a library is a separately compilable unit, and Koivu has no separate compilation (see the Multi-File Programs section below; [Backend](backend.md), decision 12).
* **Hygienic Macro Tooling:** The R6RS macro model scales naturally from simple `syntax-rules` up to complex compile-time transformations, ensuring that the Stage 2 Sapling macro-expander smoothly upgrades to support advanced Stage 3 modular code pipelines.
* **Chez Scheme Alignment:** Basing the dialect on R6RS mirrors the architecture of Chez Scheme, allowing compiler logic, transformations and nanopasses to be prototyped on industrial tools during early development.


## Character Encoding

Every source that a bootstrap reader reads is **ASCII**, and nothing in the bootstrap chain decodes anything.

The rule is one sentence: **a compiler's source must be in the character set its reader accepts, and the bootstrap readers accept ASCII only.** Its scope follows from the chain rather than from a list:

| Text | Read by | Character set |
| :--- | :--- | :--- |
| The seed's source | a C compiler before M2, a Koivu reader after | ASCII |
| The sapling's source | the seed | ASCII |
| Stage 3's source | the sapling | ASCII |
| `.pino` images, comments included | `koivu-vesi` | ASCII |
| Vesi's source, target descriptions, `build.koivu` | the seed and Vesi | ASCII |

Stage 3's own source is in that table for a reason that is easy to miss: the sapling is what reads it ([Stage 2](05_stage2_sapling.md), section 1), so a non-ASCII character anywhere in Stage 3's source is a character the seed's reader has to classify. What Stage 3 *compiles* is a different question, and it is answered by the frontend's own language ([Frontends](07_frontends.md)).

### Why ASCII and not UTF-8

* **There is no character type to decode into.** Stage 1's data types are fixnums, symbols, cons cells and byte buffers ([Stage 1](04_stage1_seed.md), section 4). A reader that accepts UTF-8 must validate it - rejecting overlong encodings, surrogate halves and truncated sequences - and that validation would be a security-relevant decision taken in the narrow waist of the chain.
* **Bytes stay comparable.** The determinism test, the golden-image test and the "reassemble the committed `.s` and compare" recipe all compare bytes ([Stage 1](04_stage1_seed.md), section 8; [Seed Artifacts](08_seed_artifacts.md), section 6). With one byte per character, "the same text" and "the same bytes" cannot come apart, and Unicode normalisation never enters the picture.
* **No locale, no code page.** Reading cannot depend on `LANG`, and the Windows source path is already the ANSI API (`CreateFileA`, [Stage 1](04_stage1_seed.md), section 3).
* **It is checkable by a tool.** Any byte above `0x7F` in a covered file is a build failure. A rule a script can enforce beats a rule a reviewer has to remember.

### What the restriction does not cover

It governs *text that a Koivu reader reads*, not the bytes a program handles. A path the OS hands back, the contents of a byte buffer, and the data a compiled program reads or writes are all outside it and may be any bytes at all. A diagnostic that quotes a file name may therefore contain non-ASCII bytes; a diagnostic that quotes source text cannot.

### Deviation from R6RS

R6RS's identifier syntax is Unicode-aware: `<letter>` includes non-ASCII letters. Koivu restricts identifiers, comments and literals to ASCII, which narrows the checked subset described above by one more step. The restriction belongs to the bootstrap chain's readers, not to the production stack: a frontend compiled by Stage 3 decides its own input encoding ([Frontends](07_frontends.md)).

### Rejected alternatives

* **UTF-8 everywhere, including the seed.** Rejected: it puts a decoder and a validator in the narrow waist, for sources that contain no non-ASCII text.
* **A single-byte legacy encoding such as Latin-1.** Rejected: still an encoding decision, and the byte-to-character mapping would rest on a table nobody would maintain.
* **ASCII for identifiers but not for comments.** Rejected as *more* complex rather than less: the reader would still have to accept a high byte inside a comment, so the check would have to distinguish positions instead of testing one property.
* **No rule, leaving it to each stage.** Rejected: the seed and the sapling share one reader, so an unwritten rule is a rule that differs between the C and the Scheme implementation.

## Data Types

All Koivu stages are statically typed. Koivu Scheme is therefore a **checked subset of R6RS** rather than a different type discipline: R6RS is a dynamically typed specification, and Koivu keeps its syntax, its macro model and its phasing while requiring every value's representation to be fixed at compile time. A program that would need run-time type dispatch - a tagged value whose representation is known only once it is inspected - does not compile. That is the whole of the restriction, and it is why the dialect baseline above can be R6RS while this section can open with a claim R6RS does not make.

### Basic Data Types

All Koivu stages support the following basic data types:

* Signed 32-bit Integers (Fixnums)

   A raw signed 32-bit integer mapped directly to a hardware register, for tracking array indices, byte offsets in binary generation, 
   memory allocation sizes, and immediate values in code emission.

* Symbols (Unique Names)

   An immutable string pointer backed by an internal global table (an interned string). Intermediate Representation (IR) will represent 
   variable names and CPU instructions as pure symbols. Comparing symbols is fast because the compiler only compares their memory addresses (eq?), 
   never the character strings themselves.

* Cons Cells

   A simple structural record containing exactly two pointers: a CAR (Contents of Address Register) and a CDR (Contents of Decrement Register).
   
* Byte buffer

  A simple flat vector of bytes for input and output from files. 

* Closures

   A pair containing a pointer to compiled machine code instructions and a pointer to the environment frame holding captured variables. 
   Closures enable functional programming, passing pass-behaviors dynamically, and handling lexical scoping cleanly throughout compiler infrastructure pipeline.

   Closures are a Stage 1 data type, not a Stage 2 addition: the Stage 2 sapling compiler is written in closures and is compiled by the seed. The Stage 1 model is deliberately simplified - `{ code_ptr, env_ptr }`, frames `{ parent_env_ptr, slot0, ... }` linked to their parent rather than copied, variable access compiled to a `(depth, index)` pair, `set!` permitted on captured variables, fixed arity only, and no `call/cc`. It is specified in [Stage 1 (Seed)](04_stage1_seed.md), section 4, and recorded as resolved decision 11 in [Backend](backend.md).

Cons Cells do not use value tagging, compiler must do type-checking and issue correct instuctions.


### Stage 2 Data Types
   
Koivu Scheme Stage 2 and up compilers add following data types:
   
* Unsigned 8-bit Integers
* Unsigned 16-bit Integers
* Signed 16-bit Integers
* Unsigned 32-bit Integers
* Signed 64-bit Integers
* Unsigned 64-bit Integers

  When used for stand-alone variables, integer data types are implemented just like traditional Fixnums. 
  Compiler makes a distinction between signed/unsigned integers of different sizes in the following cases:
  - Type checking. 
  - Creation of binary buffers with the proper size, stride and alignment (Stage 3's `flat-vector`, below).

### Stage 3 Data Types

Koivu production-level compilers will implement lexing, parsing and code emiting [data-oriented algorithms](data_oriented_design.md)
similar to [Carbon compiler](https://docs.carbon-lang.dev/toolchain/docs/), and will use similar data structures. 

Stages 1 and 2 do not have `flat-vector`. The sapling compiles Stage 3's source, Stage 3's own source uses no `define-flat-vector` form, so the form never reaches it ([Purpose and Scope](#purpose-and-scope)).

#### `flat-vector`

For this purpose Koivu Scheme Stage 3 adds a built-in data type called `flat-vector` and intoduces new macros:

1. **`define-flat-vector:`** Declares the layout of an indexable, growable, dense, flat array.
2. **`flat-vector-for-each:`** Combines a high-speed iterative loop, pointer/offset folding, and pattern matching into a single construct. It automatically binds field variables to the current item in the array without manual index math or offsets.

Full API and implementation details for `flat-vector`: [flat-vector.md](flat-vector.md).

The `define-flat-vector` macro allows the following declaration as an example:

```lisp
;; Define our TokenizedBuffer layout
(define-flat-vector token-buffer
  :stride 12
  (kind    u32 0)   ; field offset is 0 bytes
  (pos     u32 4)   ; field offset is 4 bytes
  (payload u32 8))  ; field offset is 8 bytes
```

Koivu compiler will register the `token-buffer`'s name and layout into compile-time environment 
and will use the following data structures in LLVM IR for working with `token-buffer` binary data:

```llvm
; --- Lex::TokenizedBuffer (Token Buffer Entry) ---
; Total Size: 12 bytes.
; Every single token in a source file maps directly to this uniform 12-byte layout.
%struct.TokenBufferEntry = type {
    i32,    ; 0: kind       - Lex::TokenKind enum (e.g., Identifier, Plus, Fn Keyword)
    i32,    ; 1: pos        - Byte offset into the raw source code text buffer
    i32     ; 2: payload    - Context-dependent 32-bit slot:
            ;                 If Identifier: Stores IdentifierId index
            ;                 If IntegerLiteral: Stores IntegerLiteralId index
}
```

Access to the example stream will use the following syntax:

```lisp
;; Extracts a single field from an element slot at a specific index.
;; Syntax: (flat-vector-ref stream index 'field-name)
(flat-vector-ref token-buffer 14 'kind)
```

Compiler will map this to the following `getelementptr` calculation in LLVM IR:

```llvm
; The macro replaces abstract fields with static struct indexes at compile-time
%field_ptr = getelementptr %token_buffer.TokenBufferEntry, ptr %raw_bytes, i32 14, i32 0
```


#### Example: An Identity Validation Pass

Let's write a realistic front-end compiler algorithm: An Identifier Verification Pass.
The pass loops over the entire token-buffer linearly. If it encounters a token of kind 42 (representing an Identifier), 
it grabs the payload (the IdentifierId) and fires a validation function. If it hits an error token (99), it terminates early or logs it.

```lisp
(define (validate-all-identifiers buffer)
  (flat-vector-for-each buffer token-buffer
    ;; Automatic loop state variables: 'index' is the current loop index
    ((42 pos payload)
     ;; Kind 42 = Identifier. Extract payload and pass it to validation
     (verify-identifier-id! payload pos))
    
    ((99 pos _)
     ;; Kind 99 = Syntax Error. Log error at source pos.
     (log-lex-error! pos))
    
    (else 
     ;; Every other token (operators, keywords) is skipped instantly
     #t)))
```

Before compiling to LLVM IR, the macro system expands the declarative loops into an optimized tail-recursive index iterator operating on the raw underlying memory buffer.

Koivu Scheme compiler maps the the expanded `flat-vector-for-each` macro block straight into highly structured LLVM IR blocks.
Because the stride is fixed (12 bytes) and fields are mapped directly to struct offsets, LLVM can utilize hardware registers 
to carry the values of kind, pos, and payload inside a hot loop without memory fragmentation.

## Reader Macros & Syntactic Extensions

### Design Invariant
The lexical `READ` phase stays a pure, static, order-independent translation from text to nodes. Koivu prohibits arbitrary execution of host-language code at read time (Common Lisp's `#.`), forbids mutation of the reader table during a source scan, and requires every reader extension to map text onto nodes without consulting anything but the text.

The reason is structural. **The sapling is what reads Stage 3's source**, so a reader macro that Stage 3's source may contain has to be implemented by the compiler that reads it - and the sapling is the narrow waist the chain rests on, with the seed behind it. An embedded foreign language therefore ends up as a parser inside the sapling.

The rule that follows: **a reader macro is admissible only if it is lexical** - if its payload becomes a node without a parser for some other language. Fixed-width literals and feature filtering qualify. Embedded C, embedded target assembly, embedded bitcode and read-time data ingestion do not.

### R6RS Interoperability & Adaptations
Koivu's base reader syntax derives from the **R6RS Lexical Structure (Chapter 4)**, extending the standard dispatch character (`#`) for specialized compiler pipelines. 

1. **Primitive Fixed-Width Numeric Literals (Extending R6RS 4.2.1):**
   To support strict machine-type representations without dynamic type allocation, numbers can be suffixed with explicit bit-widths. The reader parses these directly into target integer constants.
   * `42_u32` $\rightarrow$ Instantiates a 32-bit unsigned integer literal node.
   * `-1024_s64` $\rightarrow$ Instantiates a 64-bit signed integer literal node.

2. **Conditional Compilation Feature Flags:**
   Koivu adopts standard Lisp structural filtering via `#+` and `#-` directly inside the recursive-descent character stream.
   * `#+feature expression` $\rightarrow$ Evaluates the global compile-time symbol list. If the feature flag is absent, the reader completely skips the expression block at character level without allocating heap cells or pairs.

3. **LLVM IR Literals (Stage 3 and above):**
   To let a compiler write a fixed IR fragment as the text LLVM itself accepts, the reader accepts a raw IR block:

   ```scheme
   ;; Inside a Stage 3 pass:
   (define (lower-native-addition x y)
     #llvm_ir{
       %res = add i32 %x, %y
       ret i32 %res
     })
   ```

   The block is handed to the production LLVM IR parser and becomes a structural LLVM IR AST node in the surrounding tree. It is a notation for *literals*: IR that a program builds at run time is built with the ordinary constructors, not written as text.

   Three rules bound it:

   * **One parser, not two.** The block calls the same parser `koivu-llc` uses ([Backend](backend.md), section 7.3). A reduced parser for source embedding would be a dialect of its own: frontend authors would have to learn which LLVM IR Koivu accepts, and the two paths would drift.
   * **Stage 3 and above, permanently.** The form is usable by Stage 3 and by the programs Stage 3 compiles, never by Stage 3's own source, because the sapling is what reads that source and the bootstrap goes through the sapling every time. The reader is one implementation shared by the whole chain, so the form is in its vocabulary everywhere; where the parser is absent - in the seed and in the sapling - the dispatch reports by name that the form needs the production stack, rather than failing as an unknown character.
   * **Diagnostics point inside the block.** A malformed block reports the line and column of the offending text, not the line of the dispatch character, and the location carries the identity of the file the block was read from.

### Constraints & Anti-Patterns

The following are strictly illegal in the Koivu codebase:

* **Global table mutation** - code that re-binds dispatch characters mid-file. Reading must stay order-independent; otherwise a syntax bug can only be found by replaying the parser's history.
* **Infix and precedence shifters** - sugar that turns prefix Lisp structure into infix mathematical notation. A pass should look like the tree it manipulates.
* **Embedded foreign languages** - `#c{...}`, `#asm[...]`, `#llvm_bc[...]` and `#llvm_target{...}`. Each would put a parser for another language into the sapling, and none is needed: Koivu emits portable LLVM IR and lowers it afterwards, so a compiler never writes C or target instructions in its own source. Target data layouts are data, read by Vesi at run time ([Koivu Vesi](koivu-vesi.md), section 4).
* **Read-time data ingestion** - `#embed-json` and equivalents. A table a compiler needs - Unicode classes, keyword lists - is committed as source: one `define` per table, produced by a generator that runs once and is not part of the build. The build then reads one format, and the image stays a function of the source set, which is what the determinism check in [Stage 1 (Seed)](04_stage1_seed.md), section 8 depends on.

## Multi-File Programs

Koivu has no separate compilation: a program is compiled as one unit and nothing is linked ([Backend](backend.md), decision 12). Multi-file programs are therefore assembled textually, at read time.

### `include`

```scheme
(include "path/to/file.scm")
```

`include` is a **reader directive**, not a form that the front end or the macro expander ever sees. When the reader meets it, it opens the named file and continues reading from it, splicing those forms into the enclosing read exactly as if they had been written at that point.

* **Textual, not modular.** There is no export list, no import set, no namespace and no unit boundary. An included file contributes top-level definitions to the same program as the file that included it.
* **Resolved before macro expansion.** Because the reader splices, no macro can produce an `include`, and no include path can depend on expansion. The read phase stays a pure function of the file set, so the full text of the program is knowable before any pass runs.
* **Top level only.** `include` is legal only where a top-level form is legal. R7RS also permits it in a body; Koivu does not, because splicing into an expression context buys nothing and complicates the reader.
* **Paths are relative to the including file**, never to the working directory, so a program reads the same wherever it is invoked from.
* **Cycles are an error.** An include that is already on the open-include stack is a diagnostic, not infinite recursion.
* **A location carries its file.** Every node the reader produces remembers the file it came from, so a diagnostic raised inside an included file names that file and a line within it, never a line of the file that included it. Without this, textual inclusion would make error messages useless as soon as a program had more than one file.

### Duplicate Definitions

Because inclusion is textual, the whole program shares one namespace. **Two top-level definitions of the same name are an error**, whether they come from one file or from several. There is no shadowing rule, no "last one wins" and no warn-then-continue: a duplicate is a build failure.

That rule is what makes textual inclusion safe to use. With separate compilation the question is "which definition does this unit see"; with `include` it is "does this program define anything twice", and that question can be answered by reading the source.

### Program Entry Point

A Koivu program is not a sequence of top-level forms to be evaluated in order: Koivu has no evaluator, and nothing runs at the top level. A program is a set of definitions plus one procedure named `main`, and the startup stub emitted into the executable calls it.

```scheme
(define (main)
  ...)
```

* **Arity 0.** Stage 1 has fixed arity only, so the Gambit convention of `(define (main . args))` cannot be used. Zero is the simplest fixed arity that works.
* **The return value is the exit status.** The startup stub passes it to the OS exit primitive, so `0` is success and any other value is a failure code.
* **Every program has exactly one `main`.** There are no library programs, because there are no libraries and no separate compilation. A program with no `main` is a build error, and a program with two is the duplicate-definition error above.

`main` is an ordinary top-level definition. It can live in any file of the program, including an included one, and it is not a reserved word outside this rule.

### Command-Line Arguments

`main` takes no parameters, so arguments are read through two primitives:

```scheme
(command-line-count)   ; → fixnum: number of arguments, counting the program name
(command-line-ref i)   ; → byte buffer for argument i
```

Passing a list of strings to `main` would be the Guile and Gambit shape, and it is rejected for a Koivu-specific reason: the startup stub would have to build string objects and cons cells before `main` runs, which means emitting allocation code into every executable the seed produces. That is a run-time library by stealth. Instead the stub stores the OS argument vector in two globals, and a descriptor is allocated only for the arguments a program actually asks for. An index outside the range aborts the program with a diagnostic, the same way exceeding the arena limit does. A program that wants the whole list builds it in three lines of its own source, where a reviewer can see it.

### Rejected Alternatives

* **`import` and the R6RS library system.** A library is a separately compilable unit with explicit exports, which is precisely the separate compilation that [Backend](backend.md), decision 12 excludes. Using `import` for program composition would reintroduce object files, symbol export and a linker under different names.
* **`load`.** `load` evaluates a file at run time, which requires an evaluator. Koivu has none: the seed is a compiler and nothing else ([Backend](backend.md), decision 5).
* **A list of file names on the command line.** The composition of a program would then live in an invocation rather than in the source, where a reviewer can read it. With `include`, a program has exactly one root source file.

## Other considerations

To minimize dependancy on legacy tools and simplify the build process, Koivu build system will use only Koivu Scheme for all of build management. 

Koivu Scheme must use an absolute minimum amount of system calls. Its libraries also must be minimalistic: only the code required for compiler work. 

Koivu library will have at least the following components:

* Framework for writing parsers 
* Framework for writing Nanopasses and a collection of useful Nanopasses
* Framework for lowering generic LLVM IR to target machine code
* Utilities for various transformations to and from LLVM IR
* Functions for build management

