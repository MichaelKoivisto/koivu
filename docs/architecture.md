Koivu Compiler Infrastructure Structural Blueprint

Minimum OS platforms for Koivu project are 64-bit Windows, Linus and macOS, in that order of priority. Initial set of target architectures are x86_64 and arm64. 

At some point in the future Koivu must support cross-compilation by a compiler running on a 64-bit operating system to popular 32-bit targets like arm32.
Please note that this is different from compiler itself running on a 32-bit OS.  

Support for bootstrapping and compilation on 32-bit architectures and corresponding operating systems is still under question. 
This may be possible as project matures if it does not complicate things too much. 

Main Language: Koivu Scheme

Foundational component of Koivu is a programming language called Koivu Scheme (a diallect of Scheme which in turn is a diallect of Lisp). 
Koivu Infrastructure will use it for writing compilers (and related tools) for other languages, 
and also for all three stages of bootstrapping and for all of build management. 

Koivu Scheme is not a general-purpose programming language but rather a domain-specific language. It is intentionally stripped off many capabilities 
to simplify the language and its libraries. It also features optimizations, specialized data types and memory management tools 
that make sense when writing compilers but useless in other domains. 

Koivu Scheme comes in two major flavours: a simple interpreter written in portable low-level LLVM IR for use in bootstrapping, 
and an ahead-of-time (AOT) batch compiler. Both flavours will be compatible in terms of language syntax and data types, but may differ in some capabilities. 

To minimize dependancy on legacy tools and simplify the build process, Koivu build system will use only Koivu Scheme for all of build management. 

Koivu Scheme must use an absolute minimum amount of system calls. Its libraries also must be minimalistic: only the code required for compiler work. 

Bootstrapping Strategy

Bootstrapping will work in three stages:

Stage 1 (Seed): A target-independent Lisp-1 interpreter written in pure, generic LLVM IR. 
Stage 2 (Bridge): A core macro-expanding compiler written in Stage 1 Lisp, executing entirely in memory to resolve hygienic macros (syntax-rules), vectors, and lexical closures.
Stage 3 (Production Core): A statically typed, AOT-compiled Scheme dialect executing a highly modular pipeline of ~50 distinct Nanopass transformations.

Stage 1 Design

Bootstrapping will start from a simple Lisp interpreter written in pure, generic LLVM IR. 
Koivu project will also keep (as part of its source code) target-dependent machine assembly files for popular platforms (x64, arm64 and possibly others) for seed lisp interpreter. 
Those target-dependant assemby files will be obtained by translating generic IR implementation of seed interpreter. At early stages of the project, we will use LLVM tools 
to translate LLVM IR to target assembly. Later, as Koivu project grows, this step will become self-hosted in a sense that we will use a Koivu tool (written in Scheme) for translation. 

The goal of portable Lisp interpreter seed implementation in generic IR is to simplify the maintanance of Koivu project. Target-specific assembly seeds will still have 
one important common property with generic IR seed: they all will be human-readable and human-inspectable, due to relatively small size. 

Bootstrapping Paths and Trust

There will be two major paths for bootstrapping:

Simple Path: bootstrap from assembly of seed interpreter on some consumer-grade operating system. 
Secure Path: bootstrap from machine binary of seed interpreter in a secure bootstrapping environment, similar to GNU Bootstrapping Project. 

Simple Path is merely a convinience for majority of developers and users. As part of Simple Bootstrapping Path, Linux/MacOS users will have to translate 
the seed assembly code to an executable, using their platform assembler tool.
For Windows users Koivu may provide a binary executable seed of Lisp interpreter as part of Koivu download, again, just for convinience 
(since a bare Windows OS does not have an assembler tool). Please note that a small binary is still suitable to human inspection, at least in theory: 
you can open it in some text editor with hex display capability and verify that machine code corresponds to the assembly code. 
Of course, there are more practical ways to inspect the binary: scan it with antivirus, verify a digital signature, automatically compare it 
to the source assembly code using some custom automated tool etc. The smaller the binary, the easier it is to inspect. 

Simple Path is not truly secure/trustable. It is only as secure as the operating system where you build your compiler infrastructure. In practice, 
a particular instance of consumer-grade operating system may have various kinds of malicious code waiting to attack the compiler infrastructure: from random viruses to elaborate 
malicious code engineered by OS provider/seller. However, most people trust their OS provider/seller and use antivirus software to guard against viruses. 
So this bootstrapping path is good enough for majority of users. 

Secure Path is useful when full trust in compiler chain is an absolute requirement. (See Ken Thompson’s 1984 ACM Turing Award lecture, "Reflections on Trusting Trust.")
In that case, Koivu compiler infrastructure may serve as a drop-in replacement for the compiler seeding steps of GNU Bootstrapping Project. 
Or you may design an even more elaborate simultaneous OS and compiler bootstrapping procedure. Particular details of such a bootstrapping procedure 
are beyond the scope of Koivu project; Koivu's goal is to cover the compiler bootstrapping part only.

Stage 1 (Seed) Interpreter

Koivu bootstrapping is designed to run on computers with at least 2 GB of RAM, which is a reasonably small amount of memory by modern standards. 
There is nothing to be gained by requiring compiler bootstrapping to fit in smaller amount of memory: major modern platforms have plenty of memory, 
while embedded systems and retro platforms do not really need a full compiler chain because they can happily live on cross-compiling from more powerfull systems. 

For the sake of simplicity, given the bootstrapping goal (compiling the next stage and then exiting), 
Stage 1 Interpreted will not use a garbage collector at all, using a simple bump allocator instead. 
It will have an upper limit of memory to use (ABS_MEM_LIMIT_BYTES in MiB) hard-coded into its IR source code (and therefore into its binary). 
The default value for ABS_MEM_LIMIT_BYTES will be 2048 MiB. Stage 1 Interpreted will allocate a fixed chunk of memory of ABS_MEM_LIMIT_BYTES at the start. 
When memory is requested, the allocator will check if there is enough remaining space in the buffer. If valid, it will return a pointer to the current offset
and "bump" (increment) the pointer forward by the size of the request (plus any alignment padding). 

If Stage 2 source accidentally has an infinite loop (a bug) and bump allocator crosses that ABS_MEM_LIMIT_BYTES boundary, assembly code should 
instantly pull the emergency brake, report an "out of memory" error, panic and exit. 

An infinite loop in Lisp often happens via infinite recursion (a function calling itself forever). In a primitive assembly interpreter, 
each nested function evaluation pushes a new frame onto the physical CPU execution stack. Long before interpreter runs out of heap memory, 
the CPU stack pointer will crash into its boundary. Stage 1 interpreter will let the operating system naturally handle this via a standard 
Stack Overflow segmentation fault, which cleanly terminates the process before it can harm the host system.

To ensure that legitimate loops don't accidentally look like infinite memory hogs, Stage 1 interpreter must implement Tail-Call Optimization directly in EVAL loop.

To bootstrap Stage 2 (a simple macro-expanding compiler), Stage 1 interpreter will likely read and parse a few tens of thousands of lines of Lisp code.
On a 64-bit machine, a single Cons cell (CAR + CDR) takes 16 bytes. Even if Stage 1 interpreter allocates 
an incredibly wasteful 20 million Cons cells during the compilation of Stage 2, the total memory consumed is: 20 000 000 times 16 bytes = 320 MB.
Against the ABS_MEM_LIMIT_BYTES (2048 MiB default), 320 MB is a drop in the bucket.

Koivu Scheme Interpreter, being a simple internal tool for bootstrapping the infrastructure, will support only one command-line argument: the name of the Scheme file to read and execute. 
When run without command-line arguments, the interpreter will print its own full name and version (for example, "Koivu Scheme Interpreter v.1.0") and exit with success code. It also may report ABS_MEM_LIMIT_BYTES. 

Current understanding is that the Stage 1 interpreter needs just 4 system calls: 
* File/Stream Write (Print)
* File/Stream Read
* Memory Allocation
* Process Exit

Since target operating systems are somewhat different (Windows vs. Linux and MacOS), 
interpreter's source code (in generic LLVM IR) needs to abstract system calls via platform-specific glue code. 


Stage 2 (Bridge)

Details of Stage 2 are being researched. 


Stage 3 (Production Core)

Stage 3 Compiler is a highly specialized, ultra-lean Domain-Specific Language (DSL) for writing compilers. 
Koivu will use a nanopass approach inspired by the design of Chez Scheme compiler:

[Compiler Source Code] ➔ [AST Parser] ➔ [Nanopass Transform Pipeline (LLVM IR)] ➔ [Retargetable LLVM-style Code Generator] ➔ [Machine Code Binary]

Stage 3 Koivu Scheme needs exactly six core data structures (subject to further research):

Fixnums (Machine-Sized Integers)

• What it is: A raw 64-bit integer mapped directly to a hardware register.
• Why the compiler needs it: For tracking array indices, byte offsets in binary generation, memory allocation sizes, and immediate values in code emission.
• Simplification: No bignums (arbitrary-precision integers) or floating-point numbers (floats). Compilers do not need to do calculus or high-precision financial math.

Symbols (Unique Names)

• What it is: An immutable string pointer backed by an internal global table (an interned string).
• Why the compiler needs it: Symbols are the backbone of Lisp's symbolic processing. Intermediate Representation (IR) will represent variable names and CPU instructions as pure symbols (e.g., 'v1, 'rax, 'if, 'primitive-+). Comparing symbols is blazing fast because the compiler only compares their memory addresses (eq?), never the character strings themselves.

Cons Cells (The Core Pair)

• What it is: A simple structural record containing exactly two pointers: a CAR (Contents of Address Register) and a CDR (Contents of Decrement Register).
• Why the compiler needs it: Cons cells naturally build singly linked lists and binary trees. Since source code, Abstract Syntax Trees (ASTs), and nested Intermediate Representations are structurally just trees, Cons cells allow to represent code natively without manual tree-node allocation logic.

Records / Structs (Heterogeneous Objects)

• What it is: A fixed-size contiguous block of memory containing typed fields.
• Why the compiler needs it: While Cons cells are great for trees, Koivu Scheme language needs explicit records to cleanly represent structured compiler metadata without writing messy, unreadable chains of car and cdr. Koivu may use records to define structures like (struct interval (vreg start end phys-reg)) or (struct function-metadata (name args stack-size)).

Vectors (Homogeneous Fixed-Size Arrays)

• What it is: A contiguous indexable block of memory pointers.
• Why the compiler needs it: For highly performance-sensitive indexing tasks where linked lists are too slow. Register allocator's live range arrays, block instruction listings, and symbol hash tables will be backed by raw vectors to ensure O(1) lookups.

Core Closures (Lexical Blocks)

• What it is: A pair containing a pointer to compiled machine code instructions and a pointer to the environment frame holding captured variables.
• Why the compiler needs it: Closures enable functional programming, passing pass-behaviors dynamically, and handling lexical scoping cleanly throughout compiler infrastructure pipeline.


Low-Level Tagging Layout

To keep memory management minimal and maximize execution performance, Stage 3 may use a simple 3-bit low-tagging scheme hidden directly inside the lower bits of every 64-bit pointer. Since memory addresses on modern architectures are aligned to 8 bytes, the lowest 3 bits of a pointer are always 000. Kiovu Scheme may use these bits to store the type tag:

[61 Bits: Memory Pointer or Immediate Value] [3 Bits: Type Tag]


Tag Bits (Binary)	Type	Representation
000	Fixnum	The upper 61 bits hold the raw integer shifted left by 3. No allocation needed.
001	Cons Cell	Points directly to a 16-byte block on the heap (CAR + CDR).
010	Symbol	Points to an immutable string object in the global symbol table.
011	Vector	Points to a heap memory block. The first word is the raw size; subsequent words are data.
100	Record / Struct	Points to a structured block. The first word is a symbol indicating the struct type.
101	Closure	Points to a block containing the executable code address and environment pointer.

By limiting the scope of Stage 3 to this ultra-lean set of data structures, we may completely avoid writing:
• Hash-table collision resolution layers (use basic open-addressing vectors instead).
• String-manipulation libraries (symbols are enough for text processing inside a compiler frontend).
• Dynamic type-coercion matrices (e.g., adding an integer to a float — Stage 3 only calculates integers).

Memory Allocation Strategies for Stage 3 

Why Traditional Compiler Designs Fail: Traditional compilers (like traditional C++ frontends) rely heavily on Abstract Syntax Trees (ASTs) built out of scattered, heap-allocated node objects with heavy pointer indirection. This structure is cache-hostile, causing frequent CPU cache misses and wasting precious memory bandwidth.

Stage 3 will completely reject general-purpose garbage collection and adopt the hyper-optimized memory strategies used in AAA game engines and embedded systems.

Pass-Based Arenas for Stage 3:

[Source Code] ──> [Parser Arena] ──> [Optimize Arena] ──> [Codegen Arena] ──> [Binary Emit]
                     (Reset)            (Reset)            (Reset)

• The Strategy: Assign a dedicated, contiguous memory arena to every single compiler pass (e.g., Parsing, Type Checking, Register Allocation).
• The Performance Win: When a pass executes, it bump-allocates everything it needs (new AST nodes, variable intervals) with zero tracking overhead. Once the pass finishes and hands its output to the next stage, Stage 3 Koivu Scheme instantly resets the entire arena's bump pointer to zero.
• Deallocation Speed: Absolute zero. Reclaims gigabytes of memory in a single CPU instruction (mov heap_ptr, arena_start).

Fixed-Size Object Pools for Stage 3:

Embedded systems require deterministic runtime performance with zero memory fragmentation. They achieve this using Fixed-Size Storage Pools (sometimes called Object Pools or Slab Allocators).
Stage 3 Lisp only deals with a few highly predictable, core structures (like Cons cells and fixed Record shapes).

Cons Pool:   [ Cell 1 ] ➔ [ Cell 2 ] ➔ [ Cell 3 ] ➔ [ Cell 4 ]  (All exactly 16 bytes)

Struct Pool: [ Node 1 ] ➔ [ Node 2 ] ➔ [ Node 3 ] ➔ [ Node 4 ]  (All exactly 32 bytes)

• The Strategy: At compiler startup, pre-allocate massive arrays dedicated strictly to individual object types—one giant block exclusively for 16-byte Cons cells, and separate blocks for  specific AST Record sizes. Maintain a simple Free List (a linked chain of empty slots) for each pool.
• The Performance Win: Allocation and deallocation become basic pointer-swapping arithmetic. If you delete a Cons cell, you simply prepend it to the Cons Free List.
• Cache Friendliness: Because every object in a pool is identical in size and packed contiguously, the CPU’s hardware prefetcher can load data into the L1/L2 caches with maximum efficiency. This eliminates memory fragmentation.

Components like identifier tables and cycle-detection routines (which traditionally lean heavily on dynamic hash tables or depth-first searches with frequent collisions) will be redesigned around predictable, linear memory insertions and batch processing.


Data-Oriented Design (DOD) - Struct of Arrays (SoA) for Stage3:

Both high-performance gamedev (ECS architectures) and embedded systems favor Data-Oriented Design, which organizes data based on how the CPU cache reads it, rather than how humans conceptualize it.

Instead of representing IR or AST as an array of objects (Array of Structures - AoS):

;; Traditional Array of Structures (Bad for CPU Cache)
(struct ast-node (type-tag line-number variable-symbol value-pointer))

Instead of pointer-linked tree nodes, Stage 3 compiler will break the nodes apart into separate, flat vectors organized by attribute (Struct of Arrays - SoA), paired with parallel side arrays for secondary attributes via compressed indices:

;; Data-Oriented Structure (Excellent for CPU Cache)
(defstruct ast-pool
  (type-tags   (make-array 100000 :element-type 'fixnum))
  (line-nums   (make-array 100000 :element-type 'fixnum))
  (symbols     (make-array 100000 :element-type 'symbol))
  (values      (make-array 100000 :element-type 'pointer)))
  
Why this works: When a compiler pass runs to check types or look for dead code, it usually only needs to look at the type-tags or symbols fields. In a traditional structure, the CPU cache is wasted loading unrelated data like line-number columns. In an SoA layout, a single CPU cache line can hold dozens of sequential type-tags at once, accelerating tree-walking and scanning passes by orders of magnitude.

Stage 3 memory Allocation Summary: 

By blending these disciplines, Stage 3 Lisp compiler achieves maximum performance through architectural specialization:
1. Temporary pass data uses Pass-Based Arenas (allocated instantly, wiped instantly).
2. Long-lived compiler state (like the global symbol table) lives in Fixed-Size Object Pools (never fragmented, O(1) access).
3. Heavy Intermediate Representations (IR) are mapped to Flat Vectors (SoA) to keep the CPU cache completely saturated with useful instructions.
This completely bypasses the need for a complex, generic runtime garbage collector, improving production compiler infrastructure performance.

Additional source of information on Data-Oriented Design for compilers: Chandler Carruth’s talks on the Carbon programming language at CppNow and NDC.

The Stage 3 Koivu Scheme compiler may need additional system calls for high-precision profiling of itself when running and for detecting system date/time. 
This is the subject of ongoing reseach. 



