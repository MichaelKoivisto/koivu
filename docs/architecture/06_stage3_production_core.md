# Koivu Scheme Stage 3 (Production Core) Compiler

**Status:** Architecture Blueprint

**Component:** Stage 3  

> (Jack shows up alive after leaving him on the island a second time)<br>
> Barbossa: Its not possible!<br>
> Jack Sparrow: Not **probable**

The Stage 3 Compiler is a lean Domain-Specific Language (DSL) for compiler engineering, built on a nanopass architecture inspired by Chez Scheme. It is itself a traditional Lisp compiler - cons cells, records, arenas and pools - and its own construction is not data-oriented. Data-oriented layout is a facility it provides to the frontends it hosts ([Data-Oriented Design](data_oriented_design.md)).

---

## Memory Allocation Strategies and Performance Optimizations for Stage 3 

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


### What Stage 3 Does Not Do to Itself

The data-oriented layouts of [Data-Oriented Design](data_oriented_design.md) - `flat-vector` token buffers, postorder parse trees, struct-of-arrays semantic instructions - are what Stage 3 offers the frontends it compiles. Stage 3's own AST and IR are ordinary Lisp structures living in the arenas and pools above.

This is a scope statement rather than a performance claim in either direction, and it follows from the rule in [Koivu Scheme](03_language.md), Purpose and Scope: a feature belongs to the stage whose source needs it. Stage 3's own source contains no `define-flat-vector` form, so it does not use the layout machinery it implements, and the sapling that compiles Stage 3 needs no `flat-vector` either ([Flat Vector](flat-vector.md)).

### Stage 3 memory Allocation Summary: 

By blending these disciplines, Stage 3 Lisp compiler achieves deterministic performance without a general-purpose collector:
* Temporary pass data uses Pass-Based Arenas (allocated instantly, wiped instantly).
* Long-lived compiler state (like the global symbol table) lives in Fixed-Size Object Pools (never fragmented, O(1) access).
* Intermediate representations are ordinary Lisp structures allocated from those same arenas and pools, so there is one representation to reason about rather than two.
This completely bypasses the need for a complex, generic runtime garbage collector, improving production compiler infrastructure performance.

## Stage 3 Library

The Stage 3 Koivu Scheme compiler may need additional system calls for high-precision profiling of itself when running and for system clock reads. 
This is the subject of ongoing research. 



