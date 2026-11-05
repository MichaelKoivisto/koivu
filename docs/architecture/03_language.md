# Koivu Structural Blueprint - Koivu Scheme

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

Koivu library will have at least the following components:

* Framework for writing parsers 
* Framework for writing Nanopasses and a collection of useful Nanopasses
* Framework for lowering generic LLVM IR to target machine code
* Utilities for various transformations to and from LLVM IR
* Functions for build management

