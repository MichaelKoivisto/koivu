# Parsing LLVM IR in Koivu Scheme

**Status:** Developer Notes  
**Component:** Koivu Backend  

Koivu needs an LLVM IR parser, exactly one, and it lives in the production stack. This note records why the parser is expensive, what it produces, and why no bootstrap stage contains one.

## 1. Is LLVM IR Easy to Parse in Lisp?

No. LLVM IR looks clean and is not: it has a monolithic, context-sensitive grammar.

* **The problem.** Understanding one line can require information defined elsewhere. A `phi` node (`%x = phi i32 [ %a, %block1 ], [ %b, %block2 ]`) names forward-declared basic blocks. Knowing how many bytes an instruction operates on requires a type table that has already been built. Function signatures, structure layouts and named types all have to be tracked before the instruction that uses them can be read.
* **The Lisp contrast.** Lisp parsers excel at nested, tree-shaped input. LLVM IR is a flat control-flow graph with strict linear SSA invariants: the structure that makes it easy to read is the structure a Lisp reader has no use for.
* **The cost.** A robust, error-resilient `.ll` parser is a substantial piece of code - the largest single component in the production front end that is not a pass. That cost is acceptable in Stage 3 and unacceptable anywhere in the bootstrap chain.

## 2. Why Koivu Has a Parser At All

Two consumers need one, and they need the *same* one:

| Consumer | Why it needs to read `.ll` |
| :--- | :--- |
| `koivu-llc` | it is a drop-in replacement for LLVM's `llc`, so it must accept what `llc` accepts ([Backend](backend.md), section 7.3) |
| `#llvm_ir{...}` | a Stage 3 program writes a fixed IR fragment as text and the reader literal hands it to the parser ([Koivu Scheme](03_language.md), Reader Macros) |

The second consumer is why the parser cannot be optional. A single parser is also the reason the reader literal is admissible at all: the alternative to `#llvm_ir{...}` is not S-expressions, it is an escaped string literal, because LLVM IR is dense with `%`, `@`, `{`, `}`, `[`, `]` and `"` ([Reader Macros](notes_on_reader_macros.md), section 4).

**One parser, not two.** A reduced parser for source embedding would be a dialect of its own: frontend authors would have to learn which LLVM IR Koivu accepts, and the two paths would drift apart. There is one parser, and both consumers call it.

## 3. What the Parser Produces

The parser's output is the in-memory representation described in [In-Memory LLVM IR](s-llvm-ir.md): the same `llvm-ir-module`, `llvm-ir-fn`, `llvm-ir-block`, `llvm-ir-instr` and `llvm-ir-val` nodes the constructors build. That is the point of having one representation - an embedded literal and a computed instruction are indistinguishable to every pass downstream.

Two rules follow from the parser being a producer of those nodes rather than of text:

* **Sigils are stripped on the way in.** `%res` becomes `res`, `@koivu_fast_add` becomes `koivu_fast_add`; the emitter puts them back ([In-Memory LLVM IR](s-llvm-ir.md), section 4).
* **Diagnostics point inside the block.** A malformed `#llvm_ir{...}` reports the line and column of the offending text, not the line of the dispatch character, and the location carries the identity of the file the block was read from ([Koivu Scheme](03_language.md), Reader Macros).

## 4. Why the Bootstrap Chain Has No Parser

Because the bootstrap chain never sees LLVM IR. Stage 1 and Stage 2 build Pino IR and write a `.pino` image, which `koivu-vesi` lowers ([Pino IR](pino.md); [Backend](backend.md), decision 1). Neither stage reads or writes `.ll`, and neither carries a type table, a function signature table or a forward-reference resolver for one.

This is a size decision as much as an architectural one. A `.ll` parser in the sapling would be a parser for a language the sapling does not emit, in the compiler that everything else depends on - the narrow waist the chain rests on. The parser is never part of the seed, and it is never part of the sapling.

The reader is one implementation shared by the whole chain, so `#llvm_ir{...}` is in the reader's vocabulary everywhere. Where the parser is absent - in the seed and in the sapling - the dispatch reports by name that the form needs the production stack, rather than failing as an unknown character.

## 5. What This Means in Practice

| Question | Answer |
| :--- | :--- |
| Does a front end have to write text to produce IR? | No. It builds nodes with the constructors ([In-Memory LLVM IR](s-llvm-ir.md), section 3). |
| Does a front end have to build nodes to embed a fixed fragment? | No. It writes `#llvm_ir{...}`, which produces the same nodes. |
| Can the two be mixed? | Yes, and nothing downstream can tell the difference. |
| Is the parser on any bootstrap path? | No. Stages 1 and 2 never call it. |
| Is the parser's cost bounded? | No, and that is accepted: it is production-stack code, where capability outranks size ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2). |
