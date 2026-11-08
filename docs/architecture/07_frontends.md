# Koivu Frontends

**Status:** Architecture Blueprint  

**Component:** Production Compilers  

> Elizabeth: And you'll be positively the most fearsome pirates in the Spanish Main.<br>
> Jack Sparrow: Not just the Spanish Main, love. The entire ocean. The entire wo'ld. Wherever we want to go, we'll go. That's what a ship is, you know. 
It's not just a keel and a hull and a deck and sails, that's what a ship needs but what a ship is... what the Black Pearl really is... is freedom.

Production compilers will be written in pure Koivu Scheme Stage 3 language, utilizing its core frameworks: parsers, nanopasses and retargetable native code generator. 

Koivu production compilers will follow [data-oriented approach](data_oriented_design.md) to lexing, parsing, semantic analysis and code generation similar to [Carbon compiler](https://docs.carbon-lang.dev/toolchain/docs/). This involves heavy utilization of [`flat-vector` datatype](flat-vector.md). 
