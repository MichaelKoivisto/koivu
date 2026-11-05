# Koivu Structural Blueprint - Stage 3 (Production Core)

Stage 3 Compiler is a highly specialized, ultra-lean Domain-Specific Language (DSL) for writing compilers. 
Koivu will use a nanopass approach inspired by the design of Chez Scheme compiler:

```
[Compiler Source Code] ➔ [AST Parser] ➔ [Nanopass Transform Pipeline (LLVM IR)] ➔ [Retargetable LLVM-style Code Generator] ➔ [Machine Code Binary]
```

## Data Types

Stage 3 Koivu Scheme needs exactly six core data structures (subject to further research):

1. Fixnums (Machine-Sized Integers)

* What it is: A raw 64-bit integer mapped directly to a hardware register.
* Why the compiler needs it: For tracking array indices, byte offsets in binary generation, memory allocation sizes, and immediate values in code emission.
* Simplification: No bignums (arbitrary-precision integers) or floating-point numbers (floats). Compilers do not need to do calculus or high-precision financial math.

2. Symbols (Unique Names)

* What it is: An immutable string pointer backed by an internal global table (an interned string).
* Why the compiler needs it: Symbols are the backbone of Lisp's symbolic processing. Intermediate Representation (IR) will represent variable names and CPU instructions as pure symbols (e.g., 'v1, 'rax, 'if, 'primitive-+). Comparing symbols is blazing fast because the compiler only compares their memory addresses (eq?), never the character strings themselves.

3. Cons Cells (The Core Pair)

* What it is: A simple structural record containing exactly two pointers: a CAR (Contents of Address Register) and a CDR (Contents of Decrement Register).
* Why the compiler needs it: Cons cells naturally build singly linked lists and binary trees. Since source code, Abstract Syntax Trees (ASTs), and nested Intermediate Representations are structurally just trees, Cons cells allow to represent code natively without manual tree-node allocation logic.

4. Records / Structs (Heterogeneous Objects)

* What it is: A fixed-size contiguous block of memory containing typed fields.
* Why the compiler needs it: While Cons cells are great for trees, Koivu Scheme language needs explicit records to cleanly represent structured compiler metadata without writing messy, unreadable chains of car and cdr. Koivu may use records to define structures like (struct interval (vreg start end phys-reg)) or (struct function-metadata (name args stack-size)).

5. Vectors (Homogeneous Fixed-Size Arrays)

* What it is: A contiguous indexable block of memory pointers.
* Why the compiler needs it: For highly performance-sensitive indexing tasks where linked lists are too slow. Register allocator's live range arrays, block instruction listings, and symbol hash tables will be backed by raw vectors to ensure O(1) lookups.

6. Core Closures (Lexical Blocks)

* What it is: A pair containing a pointer to compiled machine code instructions and a pointer to the environment frame holding captured variables.
* Why the compiler needs it: Closures enable functional programming, passing pass-behaviors dynamically, and handling lexical scoping cleanly throughout compiler infrastructure pipeline.


## Low-Level Tagging Layout

To keep memory management minimal and maximize execution performance, Stage 3 may use a simple 3-bit low-tagging scheme hidden directly inside the lower bits of every 64-bit pointer. Since memory addresses on modern architectures are aligned to 8 bytes, the lowest 3 bits of a pointer are always 000. Kiovu Scheme may use these bits to store the type tag:

```
[61 Bits: Memory Pointer or Immediate Value] [3 Bits: Type Tag]
```

| Tag Bits (Binary) | Type | Representation |
| --- | --- | --- |
| 000 | Fixnum | The upper 61 bits hold the raw integer shifted left by 3. No allocation needed.|
| 001 | Cons Cell | Points directly to a 16-byte block on the heap (CAR + CDR).|
| 010 | Symbol | Points to an immutable string object in the global symbol table.|
| 011 | Vector | Points to a heap memory block. The first word is the raw size; subsequent words are data.|
| 100 | Record / Struct | Points to a structured block. The first word is a symbol indicating the struct type.|
| 101 | Closure | Points to a block containing the executable code address and environment pointer.|

By limiting the scope of Stage 3 to this ultra-lean set of data structures, we completely avoid writing:
* Hash-table collision resolution layers (use basic open-addressing vectors instead).
* String-manipulation libraries (symbols are enough for text processing inside a compiler frontend).
* Dynamic type-coercion matrices (e.g., adding an integer to a float — Stage 3 only calculates integers).

## Memory Allocation Strategies for Stage 3 

Why Traditional Compiler Designs Fail: Traditional compilers (like traditional C++ frontends) rely heavily on Abstract Syntax Trees (ASTs) built out of scattered, heap-allocated node objects with heavy pointer indirection. This structure is cache-hostile, causing frequent CPU cache misses and wasting precious memory bandwidth.

Stage 3 will completely reject general-purpose garbage collection and adopt the hyper-optimized memory strategies used in AAA game engines and embedded systems.

### Pass-Based Arenas for Stage 3:

```
[Source Code] ──> [Parser Arena] ──> [Optimize Arena] ──> [Codegen Arena] ──> [Binary Emit]
                     (Reset)            (Reset)            (Reset)
```

* The Strategy: Assign a dedicated, contiguous memory arena to every single compiler pass (e.g., Parsing, Type Checking, Register Allocation).
* The Performance Win: When a pass executes, it bump-allocates everything it needs (new AST nodes, variable intervals) with zero tracking overhead. Once the pass finishes and hands its output to the next stage, Stage 3 Koivu Scheme instantly resets the entire arena's bump pointer to zero.
* Deallocation Speed: Absolute zero. Reclaims gigabytes of memory in a single CPU instruction (mov heap_ptr, arena_start).

### Fixed-Size Object Pools for Stage 3:

Embedded systems require deterministic runtime performance with zero memory fragmentation. They achieve this using Fixed-Size Storage Pools (sometimes called Object Pools or Slab Allocators).
Stage 3 Lisp only deals with a few highly predictable, core structures (like Cons cells and fixed Record shapes).

```
Cons Pool:   [ Cell 1 ] ➔ [ Cell 2 ] ➔ [ Cell 3 ] ➔ [ Cell 4 ]  (All exactly 16 bytes)
```

```
Struct Pool: [ Node 1 ] ➔ [ Node 2 ] ➔ [ Node 3 ] ➔ [ Node 4 ]  (All exactly 32 bytes)
```

* The Strategy: At compiler startup, pre-allocate massive arrays dedicated strictly to individual object types—one giant block exclusively for 16-byte Cons cells, and separate blocks for  specific AST Record sizes. Maintain a simple Free List (a linked chain of empty slots) for each pool.
* The Performance Win: Allocation and deallocation become basic pointer-swapping arithmetic. If you delete a Cons cell, you simply prepend it to the Cons Free List.
* Cache Friendliness: Because every object in a pool is identical in size and packed contiguously, the CPU’s hardware prefetcher can load data into the L1/L2 caches with maximum efficiency. This eliminates memory fragmentation.

Components like identifier tables and cycle-detection routines (which traditionally lean heavily on dynamic hash tables or depth-first searches with frequent collisions) will be redesigned around predictable, linear memory insertions and batch processing.


### Data-Oriented Design (DOD) - Struct of Arrays (SoA) for Stage3:

Both high-performance gamedev (ECS architectures) and embedded systems favor Data-Oriented Design, which organizes data based on how the CPU cache reads it, rather than how humans conceptualize it.

Instead of representing IR or AST as pointer-linked tree nodes or an array of objects (Array of Structures - AoS):

```lisp
;; Traditional Array of Structures (Bad for CPU Cache)
(struct ast-node (type-tag line-number variable-symbol value-pointer))
```

Stage 3 compiler will break the nodes apart into separate, flat vectors organized by attribute (Struct of Arrays - SoA), paired with parallel side arrays for secondary attributes via compressed indices:

```lisp
;; Data-Oriented Structure (Excellent for CPU Cache)
(struct ast-pool (
  [type-tags (make-s64vector 100000 0)]
  [line-nums (make-s64vector 100000 0)]
  [symbols   (make-vector 100000 'empty)]
  [values    (make-vector 100000 #f)]))
```

Why this works: When a compiler pass runs to check types or look for dead code, it usually only needs to look at the type-tags or symbols fields. In a traditional structure, the CPU cache is wasted loading unrelated data like line-number columns. In an SoA layout, a single CPU cache line can hold dozens of sequential type-tags at once, accelerating tree-walking and scanning passes by orders of magnitude.

### Stage 3 memory Allocation Summary: 

By blending these disciplines, Stage 3 Lisp compiler achieves maximum performance through architectural specialization:
* Temporary pass data uses Pass-Based Arenas (allocated instantly, wiped instantly).
* Long-lived compiler state (like the global symbol table) lives in Fixed-Size Object Pools (never fragmented, O(1) access).
* Heavy Intermediate Representations (IR) are mapped to Flat Vectors (SoA) to keep the CPU cache completely saturated with useful instructions.
This completely bypasses the need for a complex, generic runtime garbage collector, improving production compiler infrastructure performance.

Additional source of information on Data-Oriented Design for compilers: Chandler Carruth’s talks on the Carbon programming language at CppNow and NDC.

## Stage 3 Library

The Stage 3 Koivu Scheme compiler may need additional system calls for high-precision profiling of itself when running and for detecting system date/time. 
This is the subject of ongoing reseach. 



