# Koivu S-Expression LLVM IR (S-LLVM IR) Library

**Status:** Architecture Blueprint  

**Component:** Koivu Backend  

## Design Purpose
To fulfill the core constraint of **Stage 1 Simplicity & Auditability**, the Stage 2 compiler source code completely avoids parsing raw text-based LLVM IR string blocks via reader macros. Instead, LLVM IR statements are modeled natively as structured Lisp data layouts using a strict variant called **Koivu S-Expression LLVM IR (S-LLVM IR)**. 

Because Stage 1 lacks a macro engine, S-LLVM IR code is written as standard Scheme lists. This ensures the Stage 1 seed compiler only needs a basic, minimalist S-expression `READ` loop. The mapping of S-LLVM IR structures down to human-readable `.ll` text format is handled entirely by explicit, deterministic formatting printers.

---
### Library Namespace & API Naming Conventions

The S-LLVM IR layer is implemented as an explicit, structured library located under the project's native backend namespace. To differentiate this code generator from future LLVM binary utilities, hardware analysis passes, or API abstractions, all identifiers within the module must explicitly contain the `llvm-ir` descriptor.

#### Library Declaration Syntax
The module conforms to standard hierarchical Scheme library declarations:
```scheme
(define-library (koivu backend s-llvm-ir)
  (import (scheme base) (scheme write))
  (export make-llvm-ir-assign
          make-llvm-ir-ret
          make-llvm-ir-function
          emit-llvm-ir-instruction
          emit-llvm-ir-module)
  ;; Library body implementation...
  )
```

#### API Signature Rules

1. **AST Data Constructors (`make-llvm-ir-*`)**
   Constructors must return well-formed list structures mapping to exact LLVM assembly statements. They never emit strings directly.
   * `(make-llvm-ir-assign %dest opcode type op1 op2)` $\rightarrow$ Generates an assignment node.
   * `(make-llvm-ir-ret type value)` $\rightarrow$ Generates a return node.
   * `(make-llvm-ir-function @name params ret-type body)` $\rightarrow$ Combines labels and instructions into a structured function container block.

2. **Stream Emitters (`emit-llvm-ir-*`)**
   Emitters act as the serialization layer, taking arrays or lists produced by the constructors and printing them directly into a file or text stream.
   * `(emit-llvm-ir-instruction instr-node stream)` $\rightarrow$ Validates and prints a single linear instruction sequence.
   * `(emit-llvm-ir-module module-node stream)` $\rightarrow$ Iterates through basic blocks and prints a valid, human-readable `.ll` file.

---

### The `(koivu backend s-llvm-ir)` Surface API Blueprint

The `s-llvm-ir` library provides a rigid, functional interface for building and serializing textual LLVM IR statements. 
By standardizing on `llvm-ir` in all module exports, the API strictly differentiates intermediate representation generation from other LLVM-centric tools.

---

#### 1. Surface API Function Inventory

##### Data Constructors (AST Graph Building)
* `(make-llvm-ir-module declarations functions)`  
  *Combines global scope entities into a single compilation unit node.*
* `(make-llvm-ir-function @name parameters return-type body-statements)`  
  *Generates a structured function definition container.*
* `(make-llvm-ir-assign %dest opcode type op1 op2)`  
  *Constructs a value-producing instruction bound to a destination register (e.g., `add`, `sub`).*
* `(make-llvm-ir-phi %dest type incoming-list)`  
  *Constructs a Static Single Assignment (SSA) $\phi$ node targeting incoming basic blocks.*
* `(make-llvm-ir-br label-symbol)`  
  *Constructs an unconditional branch terminator to a basic block.*
* `(make-llvm-ir-cbr %cond-reg true-label-symbol false-label-symbol)`  
  *Constructs a conditional branch terminator.*
* `(make-llvm-ir-ret type value)`  
  *Constructs a function return statement node.*
* `(make-llvm-ir-label label-symbol)`  
  *Constructs a distinct basic block label boundary definition node.*

##### Data Constructors (Advanced Memory & Execution Additions)

* `(make-llvm-ir-gep %dest base-type %base-ptr index-list)`  
  *Constructs a `getelementptr` node to calculate structural memory offsets within flat-vector arrays.*
* `(make-llvm-ir-load %dest type %src-ptr)`  
  *Constructs an explicit memory read operation, transferring data from a pointer into a destination SSA register.*
* `(make-llvm-ir-store type value-operand %dest-ptr)`  
  *Constructs an explicit memory write operation. This operates as a side-effect terminator and does not bind a destination register.*
* `(make-llvm-ir-call %dest-or-void return-type @func-name arg-list)`  
  *Constructs a foreign function invocation node. The destination parameter accepts a symbol or a `void` constant indicator.*
* `(make-llvm-ir-declare return-type @func-name param-types-list)`  
  *Constructs an external function signature registration node within the compilation module framework.*
* `(make-llvm-ir-icmp %dest condition-symbol type op1 op2)`  
  *Constructs an integer comparison node mapping to relational constraints (e.g., `eq`, `ne`, `slt`).*
* `(make-llvm-ir-cast %dest cast-opcode src-type value-operand dest-type)`  
  *Constructs a bitwise value conversion or layout reinterpretation node (e.g., `bitcast`, `inttoptr`, `ptrtoint`).*

##### Stream Emitters (Text Serialization)
* `(emit-llvm-ir-module module-node output-stream)`  
  *Iterates through the AST module node, validating and printing a complete `.ll` source file.*
* `(emit-llvm-ir-instruction statement-node output-stream)`  
  *Iterates over an internal instruction variant, applying target string formatting rules.*

---

#### 2. Conceptual Usage Example

The following code illustrates how a lowering pass within the Stage 2 compiler leverages the constructors to construct a typed addition module, followed by serialization via the library emitter.

```scheme
(import (koivu backend s-llvm-ir))

;; 1. Construct the internal S-LLVM IR graph structure
(define my-addition-func
  (make-llvm-ir-function 
    '@koivu_fast_add               ; Function symbol
    '((i32 %a) (i32 %b))           ; Parameter signatures
    'i32                           ; Return type
    (list
      (make-llvm-ir-label 'entry)  ; Basic block entry point
      (make-llvm-ir-assign '%res 'add 'i32 '%a '%b)
      (make-llvm-ir-ret 'i32 '%res))))

(define math-module 
  (make-llvm-ir-module '() (list my-addition-func)))

;; 2. Serialize the module to a file stream
(call-with-output-file "output.ll"
  (lambda (port)
    (emit-llvm-ir-module math-module port)))
```

##### Resulting `.ll` File Text (Produced by Emitters):
```llvm
define i32 @koivu_fast_add(i32 %a, i32 %b) {
entry:
    %res = add i32 %a, %b
    ret i32 %res
}
```
