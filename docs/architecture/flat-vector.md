# Koivu Scheme - Data Stream

`flat-vector` is a built-in data type designed for use in lexing, parsing and code emiting data-oriented algorithms. 

## Built-in Data Stream API Surface Area


### Stream Declaration (Compile-Time)

`define-flat-vector` is a macro. It registers stream layout properties with compiler type-checker and lowers directly to native engine structures.

```lisp
;; Syntax: (define-flat-vector name :stride size (field-name hardware-type) ...)
(define-flat-vector token-buffer :stride 12
  (kind    s32)   ; Hardware type 32-bit signed int
  (pos     s32)   ; Hardware type 32-bit signed int
  (payload s32))  ; Hardware type 32-bit signed int
```

### Allocation & Lifecycle

These built-in operators construct the opaque stream objects and manage capacity sizing:

```lisp
;; Instantiates a raw data stream.
;; Returns a unique native descriptor of type #<flat-vector:token-buffer>.
(make-flat-vector token-buffer :capacity 16)

;; Returns the exact count of logically written elements (O(1)).
(flat-vector-length stream)

;; Returns the actual physical allocated capacity in elements (O(1)).
(flat-vector-capacity stream)

;; Forces an explicit memory pre-allocation resize to prevent runtime doubling gaps.
(flat-vector-reserve! stream 100000)

;; Safely truncates the logical element length or completely resets the cursor to 0 
;; without losing the underlying allocated block of memory.
(flat-vector-clear! stream)
```

### Mutation & Appending (The Insertion API)

For appending records, pass values positionally to match the declared sequence layout. 
For targeting existing array indexes during secondary optimization passes, use index-based mutators.

```lisp
;; Appends a new item block onto the trailing edge of the data stream.
;; Automatically triggers an O(1) amortized capacity doubling phase if full.
(flat-vector-append! stream kind-val pos-val payload-val)

;; Replaces a specific field value inside an existing element slot.
;; Syntax: (flat-vector-set! stream index 'field-name new-value)
(flat-vector-set! stream 45 'payload updated-identifier-id)
```

### Extraction & Random Access

These functions provide direct pointer-style reads of data properties via 32-bit integer indexes:

```lisp
;; Extracts a single field from an element slot at a specific index.
;; Syntax: (flat-vector-ref stream index 'field-name)
(flat-vector-ref stream 14 'kind)
```

### High-Speed Structural Traversals (The Iteration API)

Optimized primitives that map to sequential vector processing operations:

```lisp
;; Type A: Complete Linear Forward Loop
;; The compiler maps this to a tight pointer-increment step loop.
(flat-vector-for-each stream token-buffer
  (lambda (kind pos payload)
    (when (= kind 99) (handle-error pos))))

;; Type B: Index-Aware Linear Reverse Loop
;; Crucial for Carbon's Postorder ParseTree skipping optimizations!
(flat-vector-for-each-reverse stream token-buffer
  (lambda (idx kind pos payload)
    ;; 'idx' represents the absolute index integer in the stream array
    (cond 
      ((= kind 22) ;; Say 22 = CodeBlock Node
       ;; Jump backward over child branches via index manipulation
       (skip-ahead-by-payload! payload))
      (else #t))))

;; Type C: High-Level Stream Pattern Matching
;; Bakes matching, value extraction, and skipping directly into a unified construct.
(flat-vector-match-each stream token-buffer
  ((42 pos payload) (verify-identifier! payload pos))
  ((99 pos _)       (log-error! pos))
  (else             #t))
```
