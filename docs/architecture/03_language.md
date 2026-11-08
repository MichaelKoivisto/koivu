# Koivu Scheme Language

> **Status:** [Architecture Blueprint]  
> **Component:** [Koivu Scheme]  

Foundational component of Koivu is a domain-specific programming language called Koivu Scheme (a dialect of Scheme which in turn is a dialect of Lisp). 
Koivu Compiler Infrastructure will use it for writing compilers (and related tools), 
and also for all three stages of bootstrapping and for all of build management. 

Koivu Scheme is not a general-purpose programming language. It is intentionally stripped off many capabilities 
to simplify the language and its libraries. It also features optimizations, specialized data types and memory management tools 
that make sense when writing compilers but useless in other domains. 

Custom datatypes (`flat-vector`) in Koivu Scheme follow the spirit of Scheme (minimalism, expressive macros, and pattern matching) 
while generating high-performance, linear LLVM IR under the hood.

## Dialect Baseline: R6RS Foundation

Koivu Scheme adopts the [**R6RS (Revised^6 Report on Scheme)** specification](https://r6rs.org/) as its structural dialect baseline, strictly optimized to exclude non-compiler primitives. 
R6RS is selected over other specifications for three primary reasons:

* **Static Library Architecture:** The R6RS formal `(library ...)` syntax enforces explicit, compile-time separation between macro expansion and runtime code. This allows the Stage 3 Ahead-of-Time (AOT) batch compiler to statically analyze dependency graphs before code generation.
* **Hygienic Macro Tooling:** The R6RS macro model scales naturally from simple `syntax-rules` up to complex compile-time transformations, ensuring that the Stage 2 Bridge macro-expander smoothly upgrades to support advanced Stage 3 modular code pipelines.
* **Chez Scheme Alignment:** Basing the dialect on R6RS mirrors the architecture of Chez Scheme, allowing compiler logic, transformations and nanopasses to be prototyped on industrial tools during early development.


## Data Types

All Koivu stages are statically typed. 

### Basic Data Types

All Koivu stages support three basic data types:

* Signed 32-bit Integers (Fixnums)

   A raw signed 32-bit integer mapped directly to a hardware register, for tracking array indices, byte offsets in binary generation, 
   memory allocation sizes, and immediate values in code emission.

* Symbols (Unique Names)

   An immutable string pointer backed by an internal global table (an interned string). Intermediate Representation (IR) will represent 
   variable names and CPU instructions as pure symbols. Comparing symbols is fast because the compiler only compares their memory addresses (eq?), 
   never the character strings themselves.

* Cons Cells

   A simple structural record containing exactly two pointers: a CAR (Contents of Address Register) and a CDR (Contents of Decrement Register).

Cons Cells do not use value tagging, compiler must do type-checking and issue correct instuctions.


### Stage 2 Data Types
   
Koivu Scheme Stage 2 and up compilers add following data types:
   
* Core Closures

   A pair containing a pointer to compiled machine code instructions and a pointer to the environment frame holding captured variables. 
   Closures enable functional programming, passing pass-behaviors dynamically, and handling lexical scoping cleanly throughout compiler infrastructure pipeline.

* Unsigned 8-bit Integers
* Unsigned 16-bit Integers
* Signed 16-bit Integers
* Unsigned 32-bit Integers
* Signed 64-bit Integers
* Unsigned 64-bit Integers

  When used for stand-alone variables, integer data types are implemented just like traditional Fixnums. 
  Compiler makes a distinction between signed/unsigned integers of different sizes in the following cases:
  - Type checking. 
  - Creation of `flat-vector`s with binary buffers of proper size, stride and alignment.
  
* `flat-vector`

#### `flat-vector`

Koivu production-level compilers will implement lexing, parsing and code emiting [data-oriented algorithms](data_oriented_design.md)
similar to [Carbon compiler](https://docs.carbon-lang.dev/toolchain/docs/), 
and will use similar data structures, built-in into the Koivu Stage 3 Scheme dialect. 

For this purpose Koivu Scheme Stage 2 adds a built-in data type called `flat-vector` and intoduces new macros:

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


## Other considerations

To minimize dependancy on legacy tools and simplify the build process, Koivu build system will use only Koivu Scheme for all of build management. 

Koivu Scheme must use an absolute minimum amount of system calls. Its libraries also must be minimalistic: only the code required for compiler work. 

Koivu library will have at least the following components:

* Framework for writing parsers 
* Framework for writing Nanopasses and a collection of useful Nanopasses
* Framework for lowering generic LLVM IR to target machine code
* Utilities for various transformations to and from LLVM IR
* Functions for build management

