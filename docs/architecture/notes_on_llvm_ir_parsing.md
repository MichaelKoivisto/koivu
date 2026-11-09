# Parsing LLVM IR in Koivu Scheme

**Status:** Developer Notes  

**Component:** Koivu Scheme  

## 1. Is LLVM IR Easy to Parse in Lisp?

No, LLVM IR is notoriously tedious to parse. While it looks clean, it has a complex, monolithic context-sensitive grammar.
* The Problem: LLVM IR requires looking at definitions elsewhere to understand individual lines. For example, to parse 
a simple phi node (`%x = phi i32 [ %a, %block1 ], [ %b, %block2 ]`), or to know how many bytes an instruction operates on, the parser must actively track previously declared types, structure alignments, forward-declared basic blocks, and function signatures.
* The Lisp Contrast: Lisp parsers excel at nested, tree-like structures. LLVM IR is a flat, explicit control-flow graph (CFG) with strict linear SSA (Static Single Assignment) invariants.
* The Implementation Penalty: Writing a robust, error-resilient `#llvm_ir{ ... }` parser inside the minimalist Stage 2 compiler will result in massive code bloat. It will easily double or triple the size of your Stage 2 `READ` engine, severely violating your Simplicity & Auditability priority.

## 2. The Solution: S-Expression Driven LLVM IR Emission (No Macros)

Because Stage 1 lacks macros and Stage 2 must remain simple, you should **completely bypass text-parsing of raw LLVM IR statements**. Instead, represent the LLVM IR instructions natively as plain Lisp data structures (**S-Expressions**).

Instead of writing a parser that turns raw LLVM string blocks into trees, write a simple compiler-pass function that maps clean Scheme S-expressions directly to flat LLVM string text.

### The Recommended Syntax: S-Expression IR (S-IR)

Model your LLVM instructions as simple lists where the first element is the instruction token, followed by explicit type and register parameters.

Here is a side-by-side comparison of the raw string layout vs. the **Koivu S-Expression layout** for a basic addition function:

Raw LLVM IR String Syntax (Hard to Parse):

```llvm
define i32 @add_two(i32 %a, i32 %b) {
entry:
    %res = add i32 %a, %b
    ret i32 %res
}
```

Koivu Stage 2 S-Expression Syntax (Easiest to Process & Emit):

```scheme
(define-llvm-function add-two ((i32 %a) (i32 %b)) i32
  (label entry)
  (assign %res (add i32 %a %b))
  (ret i32 %res))
```

## 3. How to Emit the IR Using Only Stage 1 Primitives

Since you have no macros in Stage 1 to transform this code, `define-llvm-function`, `assign`, and `add` are not macros—they are **standard constructor functions**
or **lists** that your Stage 2 compiler processes using basic recursive functions.

To emit the code into an output `.ll` file, you write a straightforward printer pass using basic Lisp string primitives (`display`, `write`, `format` equivalents):

```scheme
;; A minimalist Stage 2 function that prints an assignment list to a file stream
(define (emit-assignment instruction-list stream)
  (let ((target-reg (cadr instruction-list))   ; %res
        (operation  (caddr instruction-list))) ; (add i32 %a %b)
    (display "    " stream)
    (display target-reg stream)
    (display " = " stream)
    (display (car operation) stream)           ; add
    (display " " stream)
    (display (cadr operation) stream)          ; i32
    (display " " stream)
    (display (caddr operation) stream)         ; %a
    (display ", " stream)
    (display (cadddr operation) stream)        ; %b
    (newline stream)))
```

## Why This Approach Protects Koivu's Priorities

1. Zero Text-Parsing Overhead: Your Stage 2 reader only uses its standard, basic S-expression parser. It doesn't need to know anything about LLVM rules; it just reads normal Lisp lists.
2. Maintains Auditability: The code that maps these lists to raw LLVM string statements is written as standard, linear functional logic. A human auditor can easily verify that the list components match the text outputs.
3. Clean Path to Stage 3: Once you bootstrap into Stage 3, you can use your new hygienic macro system to wrap these raw list constructors 
into the beautiful `#llvm_ir{ ... }` syntax you designed for the final compiler blueprint.

