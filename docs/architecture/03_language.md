# Koivu Structural Blueprint - Koivu Scheme

Foundational component of Koivu is a programming language called Koivu Scheme (a dialect of Scheme which in turn is a dialect of Lisp). 
Koivu Infrastructure will use it for writing compilers (and related tools) for other languages, 
and also for all three stages of bootstrapping and for all of build management. 

Koivu Scheme is not a general-purpose programming language but rather a domain-specific language. It is intentionally stripped off many capabilities 
to simplify the language and its libraries. It also features optimizations, specialized data types and memory management tools 
that make sense when writing compilers but useless in other domains. 

## Dialect Baseline: R6RS Foundation

Koivu Scheme adopts the **R6RS (Revised^6 Report on Scheme)** specification as its structural dialect baseline, strictly optimized to exclude non-compiler primitives. 
R6RS is selected over other specifications for three primary reasons:

* **Static Library Architecture:** The R6RS formal `(library ...)` syntax enforces explicit, compile-time separation between macro expansion and runtime code. This allows the Stage 3 Ahead-of-Time (AOT) batch compiler to statically analyze dependency graphs before code generation.
* **Hygienic Macro Tooling:** The R6RS macro model scales naturally from simple `syntax-rules` up to complex compile-time transformations, ensuring that the Stage 2 Bridge macro-expander smoothly upgrades to support advanced Stage 3 modular code pipelines.
* **Chez Scheme Alignment:** Basing the dialect on R6RS mirrors the architecture of Chez Scheme, allowing some compiler transformations and nanopasses to be prototyped on industrial tools during early development.

## Domain-Specific Data Types 

Koivu compilers will implement lexing, parsing and code emiting data-oriented algorithms similar to Carbon compiler, 
and will use similar data structures and data types, built-in into the Koivu Scheme dialect. 

Custom datatypes will follow the spirit of Scheme (minimalism, expressive macros, and pattern matching) 
while generating high-performance, linear LLVM IR under the hood.

### Data Type Examples

Here are examples of domain-specific data structures, taken from Carbon documentation (examples are in LLVM IR):

#### Token Entry

```llvm
; --- Lex::TokenizedBuffer (Token Entry) ---
; Total Size: 12 bytes.
; Every single token in a source file maps directly to this uniform 12-byte layout.
%Lex.TokenLineInfo = type {
    i32,    ; 0: token_kind - Lex::TokenKind enum (e.g., Identifier, Plus, Fn Keyword)
    i32,    ; 1: source_pos - Byte offset into the raw source code text buffer
    i32     ; 2: payload    - Context-dependent 32-bit slot:
            ;                 If Identifier: Stores IdentifierId index
            ;                 If IntegerLiteral: Stores IntegerLiteralId index
}
```

#### String Pool Entry

```llvm
; --- IdentifierList (String Pool Blueprint) ---
; Carbon keeps text data unified to avoid internal string allocations and pointer-chasing.
%IdentifierList.Entry = type {
    i32,    ; 0: string_offset - Index tracking where the text begins in the global char array
    i32     ; 1: string_length - The byte length of the identifier string
}
```

#### Parse Tree Node

```llvm
; --- Parse::Tree::NodeImpl ---
; Total Size: 12 bytes. Aligned to 4 bytes.
; Layout: [ 4 bytes NodeKind ] [ 4 bytes TokenIndex ] [ 4 bytes SubtreeSize ]
%Parse.Tree.NodeImpl = type {
    i32,    ; 0: kind          - Parse::NodeKind enum (underlying type int32_t)
    i32,    ; 1: token         - Lex::Token index wrapper
    i32     ; 2: subtree_size  - Offset distance to leap across children
}
```

#### Semantic IR Instruction

```llvm
; --- SemIR::Inst ---
; Total Size: 16 bytes. Aligned to 4 or 16 bytes.
; Layout: [ 4 bytes InstKind ] [ 4 bytes TypeId ] [ 4 bytes Op0 ] [ 4 bytes Op1 ]
; Note: In the compiler, this operates as a type-erased tagged union.
%SemIR.Inst = type {
    i32,    ; 0: kind          - SemIR::InstKind enum (underlying type int32_t)
    i32,    ; 1: type_id       - SemIR::TypeId index tracking the interned type
    i32,    ; 2: op0           - Operand 0 (e.g., lhs_id, integer payload index)
    i32     ; 3: op1           - Operand 1 (e.g., rhs_id, element layout index)
}
```

#### Semantic IR Side Table Reference

```llvm
; --- SemIR::InstBlock (Side Table Reference) ---
; Total Size: 8 bytes.
; Used by 16-byte SemIR instructions when they need to reference an arbitrary list of child instructions.
%SemIR.InstBlock = type {
    i32,    ; 0: start_index - Index pointing into a global flat vector of 32-bit integers (llvm::SmallVector<InstId>)
    i32     ; 1: size        - The number of sequential instructions belonging to this block
}
```

### Syntax Design for Domain-Specific Data Types

Koivu Scheme adds a built-in data type called `flat-vector` and intoduces new macros:

1. **`define-flat-vector:`** Declares the layout of an indexable, growable, dense, flat array.
2. **`flat-vector-for-each:`** Combines a high-speed iterative loop, pointer/offset folding, and pattern matching into a single construct. It automatically binds field variables to the current item in the array without manual index math or offsets.

API and implementation details for `flat-vector`: [flat-vector.md](flat-vector.md).

The `define-flat-vector` macro allows the following declaration as an example:

```lisp
;; Define our TokenizedBuffer layout
(define-flat-vector token-buffer
  :stride 12
  (kind    u32 0)
  (pos     u32 4)
  (payload u32 8))
```

Koivu compiler will registers the `token-buffer`'s name and layout into compile-time environment 
and will use the following data structures in LLVM IR for working with stream data:

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

```llvm
; --- Koivu flat-vector Container ---
; Structure tracking: [ Data Array Pointer, Active Count Element, Max Storage Capacity ]
%struct.KoivuFlatVector = type { 
    ptr,    ; 0: raw_data_ptr        - Opaque pointer to the start of the dense memory buffer
    i32,    ; 1: current_length      - The exact length of active records currently used
    i32     ; 2: current_capacity    - Max element allocation threshold before reallocation
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
%field_ptr = getelementptr %token_buffer.Entry, ptr %raw_bytes, i32 14, i32 0
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

Before compiling to LLVM IR, the macro system expands the declarative loops into an optimized tail-recursive index iterator operating on the raw underlying memory buffer:

```lisp
(define (validate-all-identifiers buffer)
  (let ((raw-ptr (growable-table-raw-ptr buffer))
        (max-idx (growable-table-count buffer))) ; total number of tokens inside
    (let loop ((index 0))
      (when (< index max-idx)
        (let* ((base-offset (* index 12))
               (kind        (raw-mem-read-u32 raw-ptr base-offset))
               (pos         (raw-mem-read-u32 raw-ptr (+ base-offset 4)))
               (payload     (raw-mem-read-u32 raw-ptr (+ base-offset 8))))
          (cond
            ((= kind 42) (verify-identifier-id! payload pos))
            ((= kind 99) (log-lex-error! pos)))
          (loop (+ index 1)))))))
```

Koivu Scheme compiler maps the the expanded for-each-node macro block straight into highly structured LLVM IR blocks.
Because the stride is fixed (12 bytes) and fields are mapped directly to struct offsets, LLVM can utilize hardware registers 
to carry the values of kind, pos, and payload inside a hot loop without memory fragmentation:

```llvm
; ==============================================================================
; LOWERED IDENTIFIER VERIFICATION LOOP (MODERN LLVM IR WITH 'ptr')
; ==============================================================================

define void @validate_all_identifiers(ptr %buffer_obj) {
entry:
    ; 1. Extract tracking metadata from the GrowableTable structure wrapper
    ; Calculate address of raw_data_ptr field (index 0, field 0)
    %raw_ptr_loc = getelementptr %struct.GrowableTable, ptr %buffer_obj, i32 0, i32 0
    %raw_bytes = load ptr, ptr %raw_ptr_loc, align 8

    ; Calculate address of total_active_tokens field (index 0, field 1)
    %count_ptr = getelementptr %struct.GrowableTable, ptr %buffer_obj, i32 0, i32 1
    %total_tokens = load i32, i32* %count_ptr, align 4

    ; 2. Guard against an empty token vector block early
    %is_empty = icmp eq i32 %total_tokens, 0
    br i1 %is_empty, label %loop_exit, label %loop_body

loop_body:
    ; PHI loop node tracking our absolute sequence iterator index
    %index = phi i32 [ 0, %entry ], [ %next_index, %loop_continue ]

    ; 3. Compute absolute element address at index using structural type layouts
    ;    LLVM calculates: raw_bytes pointer + (%index * 12 bytes)
    %entry_ptr = getelementptr %token_buffer.Entry, ptr %raw_bytes, i32 %index

    ; Extract and stream individual 4-byte primitive components out of the block
    %kind_ptr = getelementptr %token_buffer.Entry, ptr %entry_ptr, i32 0, i32 0
    %kind = load i32, ptr %kind_ptr, align 4

    %pos_ptr = getelementptr %token_buffer.Entry, ptr %entry_ptr, i32 0, i32 1
    %pos = load i32, ptr %pos_ptr, align 4

    %payload_ptr = getelementptr %token_buffer.Entry, ptr %entry_ptr, i32 0, i32 2
    %payload = load i32, ptr %payload_ptr, align 4

    ; 4. Direct structural matching branching using a fast switch layout table
    switch i32 %kind, label %loop_continue [
        i32 42, label %case_identifier
        i32 99, label %case_error
    ]

case_identifier:
    ; Call the verified compiler token consumer: (verify-identifier-id! payload pos)
    call void @verify_identifier_id(i32 %payload, i32 %pos)
    br label %loop_continue

case_error:
    ; Forward direct file offset mapping to error handler: (log-lex-error! pos)
    call void @log_lex_error(i32 %pos)
    br label %loop_continue

loop_continue:
    ; Increment tracking indices and confirm loop conditions are bound
    %next_index = add i32 %index, 1
    %loop_done = icmp eq i32 %next_index, %total_tokens
    br i1 %loop_done, label %loop_exit, label %loop_body

loop_exit:
    ret void
}

; Scheme Toolchain Native Functions API Signatures
declare void @verify_identifier_id(i32, i32)
declare void @log_lex_error(i32)
```


## Other considerations

Koivu Scheme comes in two major flavours: a simple interpreter written in portable low-level LLVM IR for use in bootstrapping, 
and an ahead-of-time (AOT) batch compiler. Both flavours will be compatible in terms of language syntax and data types, but may differ in some capabilities. 

To minimize dependancy on legacy tools and simplify the build process, Koivu build system will use only Koivu Scheme for all of build management. 

Koivu Scheme must use an absolute minimum amount of system calls. Its libraries also must be minimalistic: only the code required for compiler work. 

Koivu library will have at least the following components:

* Framework for writing parsers 
* Framework for writing Nanopasses and a collection of useful Nanopasses
* Framework for lowering generic LLVM IR to target machine code
* Utilities for various transformations to and from LLVM IR
* Functions for build management

