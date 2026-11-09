# Koivu S-Expression LLVM (S-LLVM) Architecture Blueprint

**Status:** Architecture Blueprint  

**Component:** Koivu Backend  

## Design Purpose
To fulfill the core constraint of **Stage 1 Simplicity & Auditability**, the Stage 2 compiler source code completely avoids parsing raw text-based LLVM IR string blocks via reader macros. Instead, LLVM IR statements are modeled natively as structured Lisp data layouts using a strict variant called **Koivu S-Expression LLVM (S-LLVM)**. 

Because Stage 1 lacks a macro engine, S-LLVM code is written as standard Scheme lists. This ensures the Stage 1 seed compiler only needs a basic, minimalist S-expression `READ` loop. The mapping of S-LLVM structures down to human-readable `.ll` text format is handled entirely by explicit, deterministic formatting printers.

---

## Grammar Blueprint & Structure

An S-LLVM compilation unit is a flat sequence of function definitions, global declarations, and metadata lists. All identifiers mapped to registers (`%`) or global symbols (`@`) are represented directly as Lisp symbols.

### 1. Function Declarations
Functions define an explicit return type, a symbol name, a parameter type-signature list, and a linear body of basic blocks.
```scheme
(define-llvm-function @symbol-name ((type %param-symbol) ...) return-type
  body-statement
  ...)
```

### 2. Control Flow & Basic Blocks
Basic blocks are defined explicitly via label statements. The instruction stream inside a function body must be strictly linear, conforming to standard LLVM Static Single Assignment (SSA) boundaries.
```scheme
(label label-symbol)
```

### 3. Assignments & Instruction Layouts
Value-producing operations utilize a uniform nesting layout where the destination register symbol is bound to the execution instruction list.
```scheme
(assign %dest-register (instruction-opcode type operand1 operand2 ...))
```

---

## Concrete Blueprint Example: High-Level Lowering Pass

The following code illustrates how a Stage 2 compiler pass lowers a high-level math operation directly into S-LLVM primitives. It requires zero text parsing and uses only basic list constructors compatible with the Stage 1 binary:

```scheme
;; Example: Lowering an integer subtraction operation down to S-LLVM structures
(define (lower-subtraction-pass target-reg left-op right-op)
  (list 'assign target-reg 
        (list 'sub 'i32 left-op right-op)))

;; Example: A complete S-LLVM function module layout inside Stage 2 source
(define (generate-add-module)
  (list
   'define-llvm-function '@koivu_runtime_add '((i32 %a) (i32 %b)) 'i32
   '(label entry)
   '(assign %res (add i32 %a %b))
   '(ret i32 %res)))
```

---

## The Emission Pipeline (The String Printer)

Because S-LLVM matches standard Lisp syntax, writing code generation tools is highly efficient. The Stage 2 compiler translates the structured list blocks into text using standard, loop-driven stream emitters. A human auditor can easily verify the correctness of the layout logic by inspecting this linear translation function:

```scheme
;; Minimalist Stage 2 printer mapping S-LLVM structures directly to file text
(define (emit-s-llvm-instruction instr stream)
  (cond
    ((eq? (car instr) 'label)
     (display (cadr instr) stream)
     (display ":" stream)
     (newline stream))
    
    ((eq? (car instr) 'assign)
     (let ((target (cadr instr))
           (expr   (caddr instr)))
       (display "    " stream)
       (display target stream)
       (display " = " stream)
       (display (car expr) stream)    ; e.g., add, sub
       (display " " stream)
       (display (cadr expr) stream)   ; e.g., i32
       (display " " stream)
       (display (caddr expr) stream)  ; operand 1
       (display ", " stream)
       (display (cadddr expr) stream) ; operand 2
       (newline stream)))
       
    ((eq? (car instr) 'ret)
     (display "    ret " stream)
     (display (cadr instr) stream)
     (display " " stream)
     (display (caddr instr) stream)
     (newline stream))))
```
