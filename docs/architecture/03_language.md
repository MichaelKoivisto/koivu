# Koivu Structural Blueprint - Koivu Scheme

Foundational component of Koivu is a programming language called Koivu Scheme (a diallect of Scheme which in turn is a diallect of Lisp). 
Koivu Infrastructure will use it for writing compilers (and related tools) for other languages, 
and also for all three stages of bootstrapping and for all of build management. 

Koivu Scheme is not a general-purpose programming language but rather a domain-specific language. It is intentionally stripped off many capabilities 
to simplify the language and its libraries. It also features optimizations, specialized data types and memory management tools 
that make sense when writing compilers but useless in other domains. 

## Dialect Baseline: R6RS Foundation

Koivu Scheme adopts the **R6RS (Revised^6 Report on Scheme)** specification as its structural dialect baseline, strictly optimized to exclude non-compiler primitives. R6RS is selected over other specifications for four primary reasons:

* **Static Library Architecture:** The R6RS formal `(library ...)` syntax enforces explicit, compile-time separation between macro expansion and runtime code. This allows the Stage 3 Ahead-of-Time (AOT) batch compiler to statically analyze dependency graphs before code generation.
* **Native Bytevectors for DOD:** R6RS standardizes low-level bytevectors. This provides direct, language-level primitives to manipulate raw contiguous blocks of memory, matching Koivu's Data-Oriented Design (SoA) and 3-bit pointer tagging layout without pointer-graph overhead.
* **Hygienic Macro Tooling:** The R6RS macro model scales naturally from simple `syntax-rules` up to complex compile-time transformations, ensuring that the Stage 2 Bridge macro-expander smoothly upgrades to support advanced Stage 3 modular code pipelines.
* **Chez Scheme Alignment:** Basing the dialect on R6RS mirrors the architecture of Chez Scheme, allowing compiler transformations and nanopasses to be cross-verified and prototyped on industrial tools during early development.

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

