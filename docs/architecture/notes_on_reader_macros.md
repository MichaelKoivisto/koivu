# Reader Macros in Koivu Scheme Stage 3

**Status:** Developer Notes  

**Component:** Koivu Scheme  

This note records why Koivu's reader is as small as it is. The specification - which forms exist and which are illegal - is in [Koivu Scheme](03_language.md), *Reader Macros & Syntactic Extensions*. What is here is the argument behind it, so that the question is not reopened from scratch every time somebody wants to embed a language in a source file.

---

## 1. The constraint everything follows from

The sapling is what reads Stage 3's source. Whatever reader macro Stage 3's source may contain therefore has to be implemented by the compiler that reads it - and the sapling is the narrow waist: the seed compiles the sapling, so the sapling's size is what keeps the first step of the chain feasible.

That inverts the usual intuition about reader macros. In a Common Lisp system the reader belongs to the language, and extending it is cheap because nothing above it has to be rebuilt. Here the reader is a component of the chain, and every extension is paid for twice: once in the reader's source, once in what the seed has to compile.

## 2. The test

**A reader macro is admissible only if it is lexical** - if its payload becomes a node without a parser for some other language.

| Form | Payload | What it would put in the reader | Verdict |
| :--- | :--- | :--- | :--- |
| `42_u32` | a number | nothing | allowed |
| `#+` / `#-` | a form, kept or skipped | nothing | allowed |
| `#llvm_ir{...}` | LLVM IR text | a call into the production LLVM IR parser, which exists already | allowed, Stage 3 and above |
| `#c{...}` | C source | a C lexer and parser | refused |
| `#asm[...]` | target instructions | an instruction parser per target | refused |
| `#llvm_bc[...]` | bitcode | a bitcode reader | refused |
| `#llvm_target{...}` | a data-layout string | nothing, but nothing needs it either | refused |
| `#embed-json` and relatives | an external file | file access during the scan | refused |

The last two rows are refused on usefulness rather than on the lexical test, and both are worth stating explicitly, because "it would be cheap" is the argument that will be made for them.

## 3. Why embedded C and target assembly are refused

Two arguments, and they agree.

**The chain contains no C and no hand-written target instructions.** Stage 3 emits portable LLVM IR, the production backend lowers that IR, Vesi lowers Pino. A compiler written in Koivu never produces C and never produces machine code by hand, so a form for writing C or assembly in its own source has nothing to feed.

**They put a parser into the sapling.** `#c{...}` would require a C lexer and parser, written in Scheme, inside the narrow waist - beside the front end and the expander that [Stage 2 (Sapling)](05_stage2_sapling.md), section 1 says the sapling consists of. `#asm[...]` would require one instruction parser per supported target. Neither is a convenience worth a component.

`#c{...}` is, in addition, a leftover. It belongs to a draft in which the chain was C-shaped; with LLVM IR as the production output there is no C AST to construct.

## 4. Why `#llvm_ir{...}` survives

Because it passes the test cheaply. The production stack already contains a textual LLVM IR parser - `koivu-llc` takes `.ll` as a true drop-in ([Backend](backend.md), section 7.3) - so the form costs a dispatch entry into code that Stage 3 has anyway.

It earns that entry three times over:

* **Readability against the specification.** A fixed fragment of IR written as IR can be checked by eye against LLVM's own documentation, and reviewed in a diff. A constructed tree cannot be read that way.
* **No escaping.** LLVM IR is dense with `%`, `@`, `{`, `}`, `[`, `]` and `"`. As a Koivu string literal it would need escaping throughout, and the readability that justified putting it in the source would be gone. The block exists because the alternative is not S-expressions - it is escaped strings.
* **It is sugar, not a second semantics.** The text is parsed by the same parser that reads `.ll`, into the same AST the constructors build. There is no second representation to audit, which is the objection [Seed Artifacts](08_seed_artifacts.md), section 3 makes to an assembly printer.

Two limits keep it from spreading:

* **Literals only.** IR that a program builds at run time is built with constructors. The block is for fixed fragments - a prologue, a bounds check, a test case - not for generated code.
* **Stage 3 and above, permanently.** The sapling reads Stage 3's source, and the bootstrap goes through the sapling every time, so the restriction is not lifted when Stage 3 self-hosts. The reader is one implementation shared by the whole chain, so the form is in its vocabulary everywhere; in the seed and in the sapling, where the parser is absent, the dispatch says so by name.

One consequence to plan for: **Stage 3's own tests cannot use the form**, for the same reason. Tests of the parser read `.ll` from files, or live outside Stage 3's compiled source.

## 5. Why external data ingestion is refused

`#embed-json` and its relatives promise to read a specification file during the scan and bake it into a structure. The promise is real; the problem is not. Data of that kind - Unicode classes, case mappings, keyword tables - is generated once and then fixed.

Commit the output instead: one `define` per table, in an ordinary source file. Then:

* **One format.** The reader already parses it. No second syntax, no separate escaping rules, no separate error messages.
* **The table is in the reviewed text.** It diffs, it can be quoted in review, and it cannot drift away from the source unnoticed.
* **The image stays a function of the source set.** This is the decisive one. The determinism check in [Stage 1 (Seed)](04_stage1_seed.md), section 8 regenerates a committed golden image and compares; an embedded external file would make the image depend on something outside the source set, and the check would stop meaning what it says.
* **Nothing is saved in the artifact.** The table is compiled into the binary either way, so ingestion buys no bytes where the budget applies. It only moves text out of the source set.

The cost is one conversion step, run once, and a large source file. Neither complicates a frontend: writing its tables as S-expressions is the format it wants anyway.

## 6. The anti-patterns, and why each is refused

* **Global table mutation.** Reading must be a function of the text. If line 50 changes how line 100 parses, a syntax bug can only be found by replaying the parser's history, which is what makes such a bug expensive.
* **`#.` and read-time evaluation.** It turns the parser into an execution engine: a bug in the evaluated code surfaces before any syntax error can be reported, and the reader stops being a parser at all.
* **Blind read-time text ingestion.** Text spliced without validation poisons the tree, and because the splice happens during the scan, error locations point at the including file. This is not an objection to `include`, which is a reader directive resolved before expansion, with cycle and duplicate-definition checks - and a location carries the identity of the file it came from ([Koivu Scheme](03_language.md), *Multi-File Programs*).
* **Infix and precedence shifters.** A pass should look like the tree it manipulates. Notation that reads as mathematics makes the reader translate twice.

## 7. What this costs

* A frontend that wants a fixed IR sequence writes a `#llvm_ir{...}` block or uses constructors. It does not write C or assembly.
* A frontend that needs a specification table commits it as source, and keeps the generator out of the build.
* The reader stays small enough that the seed can compile it, which is the property all of this is for.
