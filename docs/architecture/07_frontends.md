# Koivu Frontends

**Status:** Architecture Blueprint  

**Component:** Production Compilers  

> Elizabeth: And you'll be positively the most fearsome pirates in the Spanish Main.<br>
> Jack Sparrow: Not just the Spanish Main, love. The entire ocean. The entire wo'ld. Wherever we want to go, we'll go. That's what a ship is, you know. 
It's not just a keel and a hull and a deck and sails, that's what a ship needs but what a ship is... what the Black Pearl really is... is freedom.

Production compilers will be written in pure Koivu Scheme Stage 3 language, utilizing its core frameworks: parsers, nanopasses and retargetable native code generator. 

Koivu production compilers will follow [data-oriented approach](data_oriented_design.md) to lexing, parsing, semantic analysis and code generation similar to [Carbon compiler](https://docs.carbon-lang.dev/toolchain/docs/). This involves heavy utilization of [`flat-vector` datatype](flat-vector.md).

## Character Encoding

A frontend decides the encoding of the language it compiles. Koivu does not decide it for them, and the bootstrap chain's ASCII rule does not reach here ([Koivu Scheme](03_language.md), Character Encoding).

* **Unicode is allowed in compiled code.** Every language these frontends are planned for - C++, Swift, Hylo, Rust, Jai ([Vision](../vision.md)) - permits non-ASCII in comments at minimum, and usually in string literals and identifiers as well. A frontend that could not accept it could not compile the languages it exists for.
* **The rule is the target language's, not Koivu's.** Where a language restricts comments or literals to a subset, the frontend's lexer enforces it, because the restriction comes from that language's specification. Koivu has no opinion beyond this: a frontend that accepts UTF-8 and one that accepts only ASCII are both conforming.
* **Decoding belongs to the frontend.** The lexer reads bytes and produces whatever the target language's character model requires; there is no shared Koivu decoding layer to inherit, and the seed's byte reader is not one ([Stage 1 (Seed)](04_stage1_seed.md), section 3).
* **The output stays ASCII.** A non-ASCII code point that survives into emitted LLVM IR is written as a `\XX` byte escape, so a `.ll` file is ASCII whatever the input encoding was ([In-Memory LLVM IR](s-llvm-ir.md), section 3).
* **Koivu's own text is unaffected.** The frontend's *source* is Stage 3 source, which the sapling reads, so the frontend's source is ASCII even though the input it accepts is not ([Stage 2](05_stage2_sapling.md), section 1).

| Text | Character set | Decided by |
| :--- | :--- | :--- |
| The frontend's source | ASCII | the sapling's reader |
| The frontend's input | whatever the target language allows | the frontend's lexer |
| The emitted `.ll` | ASCII, with `\XX` escapes | the emitter | 
