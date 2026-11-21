
# Koivu Scheme Stage 1 (Seed) Compiler

**Status:** Architecture Blueprint  

**Component:** Stage 1  

> Barbossa: Jack... Jack! Did you not notice? That be the same island we made you the governor of on our last little trip.<br>
> Jack Sparrow: I did notice.<br>
> Barbossa: Perhaps you'll conjure up another miraculous escape, but I doubt it. Off you go.<br>
> Jack Sparrow: The last time you left me a pistol with one shot.<br>
> Barbossa: By the powers, you're right. Where be Jack's pistol? Bring it forward.<br>
> Jack Sparrow: Seeing as there's two of us, a gentleman would give us a pair of pistols.<br>
> Barbossa: It'll be one pistol as before, and you can be the gentleman and shoot the lady; and starve yourself to death.

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
needs to abstract system calls via glue code. 

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

## Compiler Intrinsics

Stage 1 compiler must supply intrinsics to allow implementation of all of Stage 1 functionality. 

Naming convention for intrinsics must follow Scheme traditions as reasonable. 

## Executable Name

Stage 1 compiler executable will be named `koivu-seed` on Linux and MacOS, and `koivu-seed.exe` on windows. 

## Versioning

Stage 1 compiler will use a simplified versioning scheme. Compiler version will be an unsigned integer 
formatted as 4 digits (padding with `0`s). Version will be included into the name string of the compiler, 
like this: `Koivu Seed v. 0001`. Developers will bump version number manually. 

## Command Line Interface

Stage 1 compiler will support just one command line argument: the name of Scheme file to compile. 
The purpose of this command line argument is to allow running automated tests during development. 

Production Stage 1 compiler implementation may drop support for any command line arguments 
if this significantly shortens assembly code or machine code of Stage 1 (and improves auditability). 

If provided with no source code name as command line argument, Stage 1 compiler will take the file 
named `koivu-bridge.scm` in the same folder as compiler and compile it. This is how actual bootstrapping will function. 

If Stage 1 compiler finds no `koivu-bridge.scm` source code file, it will print compiler's name and version and exit.

## Error Handling

Stage 1 compiler will print a message to `stderr` if compilation of `.scm` source code was successfull. 

Development version of Stage 1 compiler must have an ability to detect these types of errors and act accordingly: 

* Endless loop in source code being compiled. Compiler should exit with a meaningfull error message. 

* Inability to create output file (for example, lacking permissions to create output file). 

* Mismatched types in Lisp source code being compiled. This capability may be turned off in production version 
to reduce the size of seed compiler assembly/machine code to improve auditability. 

## Source Code Structure

Source code of Stage 1 compiler must be written in LLVM IR and stored in several `.ll` files,
one file per function. 

Source code must reside in `bootstrap/stage1-ll` folder.

### Main

`koivu_seed_main.ll`

### Glue Code for System Calls

`koivu_seed_glue_windows.ll`, `kernel32.def` for Windows version.

`koivu_seed_glue_posix.ll` for Linux/MacOS version.


## Development Build Scripts

`koivu_seed_build_windows.cmd` builds Stage 1 compiler (and nothing else) for Windows. 

`koivu_seed_build_posix.sh` builds Stage 1 compiler (and nothing else) for Linux/MacOS.

## Production Build Process

Production Stage 1 seed compiler for Windows will be distributed as a binary for x86_64 Windows. 
Running it will start build process for the entire Koivu infrastructure. 

Production Stage 1 seed compiler for Linux/MacOS will be distributed as target assembler file. 
Compiling it and then running it will start build process for the entire Koivu infrastructure. 

## Testing Strategy

A test suite for Stage 1 must include at least the following tests:

* Tests to check basic compiler functionality like error handling

* Unit tests in Lisp

* Integration tests in Lisp

* A simple self-test to execute in production mode before compiling any code. 
  TODO: What is reasonable for self-test? Maybe just print out compiler name to `stderr`?
  



