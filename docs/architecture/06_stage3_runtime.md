# Koivu Structural Blueprint - Stage 3 (Production Core)

**Status:** Architecture Specification  
**Component:** Stage 3 Production Core  

The Stage 3 Compiler is a lean Domain-Specific Language (DSL) for compiler engineering, utilizing a nanopass architecture inspired by Chez Scheme.

---

## Data Types

Stage 3 Koivu Scheme implements six core data structures: 

1. Fixnums (Machine-Sized Integers)

   A raw 64-bit integer mapped directly to a hardware register, for tracking array indices, byte offsets in binary generation, memory allocation sizes, and immediate values in code emission.

2. Symbols (Unique Names)

   An immutable string pointer backed by an internal global table (an interned string). Intermediate Representation (IR) will represent variable names and CPU instructions as pure symbols. Comparing symbols is fast because the compiler only compares their memory addresses (eq?), never the character strings themselves.

3. Cons Cells (The Core Pair)

   A simple structural record containing exactly two pointers: a CAR (Contents of Address Register) and a CDR (Contents of Decrement Register).

4. Records / Structs (Heterogeneous Objects)

   A fixed-size contiguous block of memory containing typed fields. While Cons cells are great for trees, Koivu Scheme language needs explicit records 
   to cleanly represent structured compiler metadata without writing messy, unreadable chains of car and cdr. Koivu may use records 
   to define structures like (struct interval (vreg start end phys-reg)) or (struct function-metadata (name args stack-size)).

5. Vectors (Homogeneous Fixed-Size Arrays)

   A contiguous indexable block of memory pointers, useful for highly performance-sensitive indexing tasks where linked lists are too slow. 
   Register allocator's live range arrays, block instruction listings, and symbol hash tables will be backed by raw vectors to ensure O(1) lookups.

6. Core Closures (Lexical Blocks)

   A pair containing a pointer to compiled machine code instructions and a pointer to the environment frame holding captured variables. 
   Closures enable functional programming, passing pass-behaviors dynamically, and handling lexical scoping cleanly throughout compiler infrastructure pipeline.


## Low-Level Tagging Layout

Stage 3 uses a 3-bit low-tagging scheme embedded in the lower bits of 64-bit words, where `000` is reserved for Fixnums and non-zero tags (`001` through `101`) represent Cons cells, symbols, vectors, records, and closures.

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

By limiting the scope of Stage 3 to this lean set of data structures, we completely avoid writing:
* Hash-table collision resolution layers (use basic open-addressing vectors instead).
* String-manipulation libraries (symbols are enough for text processing inside a compiler frontend).
* Dynamic type-coercion matrices (e.g., adding an integer to a float — Stage 3 only calculates integers).

## Memory Allocation Strategies for Stage 3 

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

The Stage 3 Koivu Scheme compiler may need additional system calls for high-precision profiling of itself when running and for system clock reads. 
This is the subject of ongoing research. 



