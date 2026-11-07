# Koivu Structural Blueprint - Frontends

Production frontends will be written in Koivu Scheme language, utilizing core frameworks from Koivu library: parsers, nanopasses and retargetable native code generator. 

Koivu will follow data-oriented approach to lexing, parsing and code generation similar to [Carbon compiler](https://docs.carbon-lang.dev/toolchain/docs/).

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


