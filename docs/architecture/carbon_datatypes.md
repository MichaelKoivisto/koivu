# Data Type Examples

> **Status:** [Developer Notes]  
> **Component:** [Global]  

Here are examples of domain-specific data structures, taken from Carbon documentation (examples are in LLVM IR):

#### Token Entry

```llvm
; --- Lex::TokenizedBuffer (Token Entry) ---
; Total Size: 12 bytes.
; Every single token in a source file maps directly to this uniform 12-byte layout.
%Lex.TokenLineInfo = type {
    i32,    ; 0: token_kind - Lex::TokenKind enum (e.g., Identifier, Plus, Fn Keyword)
    i32,    ; 1: source_pos - Byte offset into the raw source code text buffer
    i32     ; 2: payload    - Context-dependent 32-bit slot:
            ;                 If Identifier: Stores IdentifierId index
            ;                 If IntegerLiteral: Stores IntegerLiteralId index
}
```

#### String Pool Entry

```llvm
; --- IdentifierList (String Pool Blueprint) ---
; Carbon keeps text data unified to avoid internal string allocations and pointer-chasing.
%IdentifierList.Entry = type {
    i32,    ; 0: string_offset - Index tracking where the text begins in the global char array
    i32     ; 1: string_length - The byte length of the identifier string
}
```

#### Parse Tree Node

```llvm
; --- Parse::Tree::NodeImpl ---
; Total Size: 12 bytes. Aligned to 4 bytes.
; Layout: [ 4 bytes NodeKind ] [ 4 bytes TokenIndex ] [ 4 bytes SubtreeSize ]
%Parse.Tree.NodeImpl = type {
    i32,    ; 0: kind          - Parse::NodeKind enum (underlying type int32_t)
    i32,    ; 1: token         - Lex::Token index wrapper
    i32     ; 2: subtree_size  - Offset distance to leap across children
}
```

#### Semantic IR Instruction

```llvm
; --- SemIR::Inst ---
; Total Size: 16 bytes. Aligned to 4 or 16 bytes.
; Layout: [ 4 bytes InstKind ] [ 4 bytes TypeId ] [ 4 bytes Op0 ] [ 4 bytes Op1 ]
; Note: In the compiler, this operates as a type-erased tagged union.
%SemIR.Inst = type {
    i32,    ; 0: kind          - SemIR::InstKind enum (underlying type int32_t)
    i32,    ; 1: type_id       - SemIR::TypeId index tracking the interned type
    i32,    ; 2: op0           - Operand 0 (e.g., lhs_id, integer payload index)
    i32     ; 3: op1           - Operand 1 (e.g., rhs_id, element layout index)
}
```

#### Semantic IR Side Table Reference

```llvm
; --- SemIR::InstBlock (Side Table Reference) ---
; Total Size: 8 bytes.
; Used by 16-byte SemIR instructions when they need to reference an arbitrary list of child instructions.
%SemIR.InstBlock = type {
    i32,    ; 0: start_index - Index pointing into a global flat vector of 32-bit integers (llvm::SmallVector<InstId>)
    i32     ; 1: size        - The number of sequential instructions belonging to this block
}
```
