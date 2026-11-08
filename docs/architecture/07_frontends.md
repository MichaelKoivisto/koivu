# Koivu Frontends

> **Status:** [Architecture Blueprint]  
> **Component:** [Production Compilers]  

Production compilers will be written in pure Koivu Scheme Stage 3 language, utilizing its core frameworks: parsers, nanopasses and retargetable native code generator. 

Koivu production compilers will follow [data-oriented approach](data_oriented_design.md) to lexing, parsing, semantic analysis and code generation similar to [Carbon compiler](https://docs.carbon-lang.dev/toolchain/docs/). This involves heavy utilization of [`flat-vector` datatype](flat-vector.md). 
