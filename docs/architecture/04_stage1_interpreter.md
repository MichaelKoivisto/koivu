
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

Since target operating systems are somewhat different (Windows vs. Linux and MacOS), 
interpreter's source code (in generic LLVM IR) needs to abstract system calls via platform-specific glue code. 


