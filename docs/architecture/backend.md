# Koivu Backend - Code Generation and Platform Definitions

**Status:** Architecture Blueprint  

**Component:** Koivu Backend  

> Anamaria: You stole my boat!<br>
> Jack Sparrow: ...Borrowed! Borrowed without permission. With every intention of bringing it back to you.

Koivu backend is closely aligned with LLVM backend architecture: follows the same approach, uses the same or similar formats and similar algorithms. 

## Generic LLVM IR Emiter

An absolute minimum backend emits generic LLVM IR from Lisp code via `koivu-llvm-ir-emiter` Scheme library. 
The library creates a generic LLVM IR abstract syntax tree (AST) rather then printing LLVM IR directly. 

At the early stages of Koivu project development, backend uses resulting LLVM IR AST to print a pretty-formatted LLVM IR source code to a `.ll` file. 
Developers use standard `llc` static compiler from LLVM project to lower `.ll` files to target machine codes.

At the later development stages, Koivu will provide additional Scheme libraries for analysis and transformation of LLVM IR and for lowering IR to target machine codes.

The rational for emiting LLVM IR AST is simplicity of interaction with later backend stages: later stages do not need to parse LLVM IR files. 


## Simple Code Generator

The `koivu-simple-codegen` library does naive lowering of LLVM IR to target machine code. 
It is designed for use in Stage 1 Seed Compiler and does not do any transformations of LLVM IR or any target-aware optimizations. 
The only capability of `koivu-simple-codegen` is correct lowering to target machine code. 

### Simple Target Descriptions

`koivu-simple-codegen` uses simplified target descriptions stored as Scheme files. 
Simplified target descriptions only support instructions required by Stage 1 Seed Compiler. 


## Production Code Generator

Later-stage Koivu libraries provide maximum capabilities for code generation:

* `koivu-backend-analysis`: Computes program information (like dominance trees, scalar evolution, and alias analysis) without altering the IR.

* `koivu-backend-ransforms`: Contains sub-libraries like Scalar, Vectorize, IPO (Interprocedural Optimizations), and Utils that execute the actual transform passes (e.g., Dead Code Elimination, Loop Unrolling, Inlining).

* `koivu-codegen`:  Bridges the gap between target-independent code generation and the final target emission. Contains CodeGenPrepare, a critical IR-to-IR transform pass that runs right before code generation to mutate the IR specifically to benefit the target machine.

* `koivu-machine-code-layer`: Definitive library for code emission. The Machine Code Layer handles assembly-level constructs entirely divorced from LLVM IR (e.g., labels, sections, raw target instructions).

### Target Descriptions

Koivu backend will store target descriptions as Scheme source files. 

## Target Description Converter

Koivu will provide a tool written in Scheme for parsing LLVM Target Descriptions and converting them to Scheme-format Koivu Target Descriptions. 








