
# Koivu Structural Blueprint - Stage 1 (Seed) Interpreter

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

Since target operating systems are somewhat different (Windows vs. Linux and MacOS), interpreter's source code (in generic LLVM IR) 
needs to abstract system calls via platform-specific glue code. 

## Capabilities Stage 1 must support:

### 1. Fundamental Special Forms

The core `EVAL` loop of Stage 1 requires basic execution flow and definition capabilities:
* `quote` – To handle literal data structures and symbols.
* `if` – The fundamental primitive conditional node.
* `set!` – Mandatory for tracking mutable bindings during variable mapping.
* `define` – To register global definitions and functions.
* `lambda` – Essential to create lexical closures. Stage 1 must support basic lexically scoped variable capture to allow the Stage 2 expander to manage scope layers.

### 2. Primitive Data Type Predicates & Manipulators

To let Stage 2 break down expressions and manipulate syntax structures:
* **Symbol Operations:** `symbol?` and `eq?`. Fast identifier validation is critical since comparing macro symbols down to memory pointer addresses (eq?) is the core engine of a compiler.
* **Cons Cell Navigation:** `cons`, `car`, `cdr`, `pair?`, `null?`, `set-car!`, and `set-cdr!`. Stage 2 will read code as nested S-expressions; it must be able to destructure lists and dynamically mutate AST graphs.
* **Fixnum Arithmetic:** Basic operators (`+`, `-`, `<`, `=`) and `integer?`. Required to validate syntax list lengths, handle error tracking bounds, and index lookup tables.

### 3. Basic I/O Primitives

To feed the source text through the bootstrapping pipeline:
* `read` – A simple recursive-descent S-expression parser written into the Stage 1 seed to ingest Stage 2's source files.
* `write` / `display` – To emit the expanded code text to stdout or a temporary staging file.

### 4. Tail-Call Optimization (TCO)

* **Execution Invariant:** TCO must be natively baked into the Stage 1 `EVAL` loop. Because macro expansion of large codebases involves extensive deep recursion through nested expressions, an interpreter without TCO will quickly trigger a hardware stack overflow long before finishing the Stage 2 bridge compilation pass.

## What Stage 1 will completely ignore:

* **No `syntax-rules` or `syntax-case` primitives inside Stage 1:** Stage 1 does not need to understand macros natively. It runs a macro-expander written as a collection of raw Stage 1 functions and pattern matchers. Stage 1 evaluates this expander program, which reads R6RS text and spits out pure, macro-eliminated Scheme code.
* **No multiple return values (`values`, `call-with-values`):** Pass records or cons pairs instead.
* **No complex error systems:** A simple structural primitive like `(error)` that prints a message and calls the host OS `Exit` system call is sufficient.

