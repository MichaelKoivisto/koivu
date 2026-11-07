# Koivu Structural Blueprint - Frontends

Production frontends will be written in Koivu Scheme language, utilizing core frameworks from Koivu library: parsers, nanopasses and retargetable native code generator. 

Koivu will follow data-oriented approach to lexing, parsing and code generation similar to [Carbon compiler](https://docs.carbon-lang.dev/toolchain/docs/).

## Lexing phase

The Lexing phase transforms raw source text into a `flat-vector` of token information structs.

```lisp
;; Define our TokenizedBuffer layout
(define-data-stream token-buffer :stride 12
  (kind    s32)   ; 32-bit TokenKind enum (e.g., 1=Identifier, 2=Plus, 3=Fn)
  (pos     s32)   ; 32-bit Source Position (byte offset into raw source file string)
  (payload s32))  ; 32-bit Variant Context ID (e.g., IdentifierId, LiteralMapId, or Unused)
```

Lexer runs completely to completion over a source file before parsing begins.

Flyweight Tokens: A token handle (Lex::TokenIndex) is merely a 32-bit integer indexing into a global flat array.

TODO: What if target language has a macro preprocessor and textual token-pasting (like C/C++)?

The `pos` field tracks the exact byte offset in the file, allowing error diagnostic ranges to be calculated instantly on demand without bloating the token footprint.

### Lexer Execution Stages

When the toolchain invokes Lexer::Lex(), the processing executes via three highly cohesive sweeps:

#### Sweep A: Initial Line Mapping (`MakeLines`)

Before reading any grammatical tokens, the lexer performs a lightning-fast initial scan over the source string buffer to construct an **index table of lines** (`MakeLines`).
* This sweep heavily leverages SIMD vectorization (utilizing ARM NEON or x86 bitwise intrinsics) to identify newline boundaries, track line counts, and build line-end masks.
* By counting total lines upfront, the toolchain can make highly accurate, proportional pre-allocation memory reservations for the main token and string buffers, preventing expensive realloc/doubling overhead entirely during token accumulation.

#### Sweep B: Greedy Structural Dispatch Loops

With memory reserved, the lexer iterates over the character array via a fast dispatch loop. 
Compiler uses standard **maximal munch (greedy consumption)**—constantly extracting the longest valid sequence of characters that forms a valid lexical construct.
* Whitespaces and Comments: Stripped entirely via inline bit-character masks (`SkipWhitespace`).
* Variable-Length Literals: If the loop encounters complex data like string literals or floating-point structures, it intercepts them, parses their exact values immediately, caches the string content in a deduplicated **`IdentifierList` string pool**, and yields a compact 12-byte token tracking a 32-bit handle to that pool.

#### Sweep C: Resilient Bracket Balancing & Synthesizing

**Mismatched Bracket Recovery** is handled during the token accumulation loop.
* The lexer actively tracks matching structural delimiters: (), [], and {}.
* If it detects an unmatched delimiter (such as code with a missing closing brace), it runs a search over candidate repairs using indentation patterns and neighboring structural context.
* It then **synthesizes and inserts** virtual recovery tokens into the array buffer.

As an intentional structural invariant, the token buffer delivered by the lexer is guaranteed to have perfectly balanced brackets, even if the developer wrote invalid code.

### Concrete Example of Lexical Resolution

Consider this exceptional lexical parsing rule from [Carbon’s specification](https://docs.carbon-lang.dev/docs/design/lexical_conventions/):

> When a numeric literal immediately follows a . or -> token with no whitespace, a real/float literal is **never** formed to avoid breaking tuple index accesses.

If the lexer encounters: `tuple.1.2`
1. It extracts `tuple` as an `Identifier` token.
2. It hits the `.`. Since a number (`1`) follows with zero spaces, it isolates `.` as its own operator token.
3. It extracts `1` as an integer literal token.
4. It isolates the next `.` as an operator token.
5. It extracts `2` as an integer literal token.

This resolves cleanly to **five individual dense tokens**. Conversely, `tuple . 1.2` containing structural spaces is immediately grouped into three tokens (`tuple`, `.`, and the floating-point literal `1.2`).

By offloading layout balancing, literal interning, and token flattening entirely to a specialized, vectorized lexer block, 
the downstream Parse and Check phases can iterate through uniform memory vectors with pure linear efficiency.

## Parsing

Every frontend will store the Parse Tree as a `flat-vector` of uniform structures arranged in a strict Postorder Traversal layout.

Koivu frontends will enforce a rigid rule where every Parse Tree node corresponds exactly to one token in the lexer's token stream. 
Because the total token count is known precisely after lexing, the compiler will pre-allocate or reserve memory for the Parse Tree 
perfectly in a single allocation, completely eliminating resize/realloc overhead.

```lisp
(define-flat-vector parse-tree
  :stride 12
  (kind         u32 0)   ; A lightweight enum specifying the grammatical category of the node (e.g., FunctionDefinition, VariableDeclaration, Identifier, InfixOperator).
  (token        u32 4)   ; A 32-bit wrapper index pointing directly back into the linear token stream array. This field acts as the bridge for Token Tracking.
  (subtree-size u32 8))  ; Offset distance to leap across children. (The number of total entries in the flat SmallVector that belong to this node’s entire syntactic subtree.)
```

Postorder layout transforms tree-walking operations into linear iterations. For a given syntactic construct, the child operands 
or body components are placed before the operator or declaration node in the vector.

This layout functions like an **Indexed Reverse Polish Notation (RPN)** stack machine:

* When traversing the tree to build SemIR or perform structural analysis, the compiler loops iteratively over the array rather than calling a recursive Visit() function.
* The parser evaluates the children first, and the closing node binds the context together.
* TODO: how to ensure the parser knows exactly when a complex construct starts and ends? Some languages do not have "introducer" keywords (like fn, var, class). 

### Parse Tree Navigation without Chasing Pointers

Because it's an array layout, how do you find a node's parent or children if you don't have pointers? Flat vector Parse Tree avoids backward/forward scanning by packing relative data directly inside the fixed-size `parse-tree` node struct:
* Subtree Size / Offset: Each node records the size of its subtree (the number of array elements it spans). If the compiler is at a node and needs to skip past its entire subtree, it performs simple integer arithmetic: `current-index` - `subtree-size`.
* Token Tracking: Because of the one-to-one token mapping, a node doesn't need complex source range objects (like line/column spans). It simply tracks its own token index. The exact source code boundary is resolved by looking at the child nodes or the neighboring token array.

### Token Tracking

Parsing with `flat-vector` Parse Tree relies entirely on an explicit 1:1 mapping between Parse Tree Nodes and Lexer Tokens.

When the lexer processes source code, it registers all tokens in a singular, flat array called Lex::TokenizedBuffer. Every keyword, identifier, literal, and even structural character (like brackets {} or semicolons ;) becomes an entry in this array.

1. Flyweight Index Links: The NodeImpl::token field does not contain raw string data. It is a 32-bit number representing the index in Lex::TokenizedBuffer.
2. No String Duplication: If the parser encounters the identifier my_variable, the ParseTree node simply registers token = 412. If the semantic analyzer later needs to check the name or print an error, it queries the TokenizedBuffer using that index.
3. Zero-Cost Source Locations: When the compiler needs to throw a compilation error with line and column highlighting, it doesn't look at the parse tree. It passes the NodeImpl::token index to the TokenizedBuffer, which translates it into exact file positions via its own internal, optimized data blocks.

### Handling Compiler Errors gracefully

The 1:1 design introduces a unique challenge: What happens if the code has a syntax error and a token is missing?

To preserve the invariant that "every node corresponds to a token" and maintain a structurally valid tree, parser will inject synthetic placeholder tokens or error nodes. For example, if a developer forgets a closing parenthesis, the parser creates an error node linked to a dummy token to ensure the structural math (subtree_size jumping) remains mathematically perfect for downstream compiler optimization passes.

### Name Resolution via NameId Integer Comparisons

During the Lexing phase, every single variable name, function name, and type name will be parsed exactly once. 
The characters will be stored sequentially in a massive, flat string buffer (IdentifierList).
Each unique string will be assigned a 32-bit IdentifierId.

* IdentifierId(0) = ""
* IdentifierId(1) = "Int32"
* IdentifierId(2) = "foo"
* IdentifierId(3) = "x"

Lookup tables (NameLookup) will not use string keys. They will use integer-to-integer maps.
When the semantic analyzer (Check) processes a declaration like var x: Int32;, it maps the IdentifierId for "x" 
to the SemIR::InstId that defines it inside the current scope block's flat map.
When you reference a variable later in code:
```
foo(x);
```
* The compiler gets the IdentifierId for "x" (which is 3).
* It looks up the integer 3 in the current scope's dense flat map.
* If it matches, it immediately returns the InstId of the variable declaration.

Because integer comparison is a single CPU instruction (cmp), checking if two identifiers are identical requires zero string processing or cache-unfriendly memory lookups.

## Semantic Analisys

Semantic Intermediate Representation (SemIR) follows Data-Oriented Design (DOD) too.

During the Check phase, the compiler reads the flat Parse Tree array and creates a `flat-vector` of SemIR Instructions.
SemIR Instruction is implemented as a highly optimized Type-Erased Tagged Union containing four 32-bit (4-byte) fields.

```lisp
(define-flat-vector semantic-instructions-vector
  :stride 16
  (kind     u32 0)   ; A 32-bit enum tag defining what this instruction does (e.g., Add, Assign, FunctionDecl, IntegerLiteral).
  (type-id  u32 4)   ; A 32-bit integer indexing into a global type table. 
                     ; Because types are interned, checking if two instructions produce the exact same type is a blistering O(1) integer equality comparison.
  (op0      u32 8)   ; (Operand 0) A 32-bit slot whose meaning changes depending on the kind.
  (op1      u32 12)) ; (Operand 1) A second 32-bit slot whose meaning changes depending on the kind.
```

If an instruction needs complex payload data, the operands (op0 / op1) act as handles pointing to separate, dedicated flat arrays:

* NameId: Indexes into a flat, deduplicated string table.
* InstBlockId: Indexes into a flat array of instruction ranges. For example, a basic block is not a heap-allocated linked list of instructions; 
it is just a `start-index` and a `length` tracking a contiguous segment of the main instruction array.

### The `Lower` Phase: Converting SemIR to LLVM IR

Once semantic checking and name resolution are complete, compiler has a valid, type-safe array of 16-byte SemIR::Inst entries. 
The final step of the frontend toolchain is the `Lower` phase, which translates flat Data-Oriented SemIR into LLVM IR, 
enabling the LLVM backend to perform industrial-grade machine code optimization and binary generation.

This process is handled linearly by the compiler's LoweringLoop. 
Because both SemIR instructions and LLVM's basic blocks are designed around Static Single Assignment (SSA) form, the translation maps almost perfectly 1:1.


