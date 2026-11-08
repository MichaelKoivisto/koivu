# Koivu Scheme - Flat Vector

> **Status:** [Architecture Blueprint]  
> **Component:** [Koivu Scheme]  

`flat-vector` is a built-in data type designed for use in lexing, parsing and code emiting [data-oriented algorithms](data_oriented_design.md). 
Koivu Scheme Stage 3 compiler supports `flat-vector`. Stages 1 and 2 do not. 

## Flat Vector API Surface Area

### Declaring a `flat-vector` (Compile-Time)

`define-flat-vector` is a macro. It registers `flat-vector` layout properties with compiler type-checker and lowers directly to native engine structures.

```lisp
;; Syntax: (define-flat-vector name :stride size (field-name hardware-type) ...)
(define-flat-vector token-buffer :stride 12
  (kind    s32)   ; Hardware type 32-bit signed int
  (pos     s32)   ; Hardware type 32-bit signed int
  (payload s32))  ; Hardware type 32-bit signed int
```

### Allocation & Lifecycle

These built-in operators construct the opaque `flat-vector` objects and manage capacity sizing:

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

Example usage of a `flat-vector-for-each` macro:

```lisp
(flat-vector-for-each token-stream token-buffer
  (lambda (kind pos payload)
    (when (= kind 99) 
      (log-error! pos))))
```

The macro strips away the `lambda` abstraction entirely and expands the block into a low-level, tail-recursive loop that reads memory offsets directly:

```lisp
(let ((flat-vec token-stream))
  ;; 1. Extract the raw pointer and element count from the native flat-vector object
  (let ((ptr   (%flat-vector-raw-ptr flat-vec))
        (count (%flat-vector-count flat-vec)))
    
    ;; 2. Execute a high-speed, tail-recursive index loop
    (let loop ((idx 0))
      (when (< idx count)
        ;; 3. Calculate the absolute base byte offset for array[idx]
        (let ((base-offset (* idx 12))) ; 12 is the stride fetched at compile-time
          
          ;; 4. Read raw unboxed primitives directly from the native pointer
          ;;    No variable binding allocations, no Lisp boxing.
          (let ((kind    (%raw-mem-read-s32 ptr (+ base-offset 0)))
                (pos     (%raw-mem-read-s32 ptr (+ base-offset 4)))
                (payload (%raw-mem-read-s32 ptr (+ base-offset 8))))
            
            ;; 5. Inline the developer's original lambda body directly here
            (when (= kind 99)
              (log-error! pos))))
        
        ;; 6. Advance the index
        (loop (+ idx 1))))))
```

`%raw-mem-read-s32` and similar intrinsics map to LLVM IR instructions:

```lisp
; How %raw-mem-read-s32 looks when compiled by Koivo compiler backend
%field_ptr = getelementptr i8, ptr %ptr, i32 %computed_offset
%val = load i32, ptr %field_ptr, align 4
```

## Mandatory Intrinsics for a Functional `flat-vector`

These intrinsics bridge the gap between Scheme handles and raw virtual memory addresses (`ptr`).
They can be categorized into three critical execution vectors:

### Container Inspector Intrinsics (Header Unpacking)

These O(1) routines unpack the structural metadata from native `flat-vector` type descriptor header.

* **`%flat-vector-raw-ptr`**
	- **Input:** `flat-vector` handle
	- **Output:** Raw `ptr` (Opaque memory address)
	- **Purpose:** Locates the physical starting boundary of the data block.
* **`%flat-vector-count`**
	- **Input:** `flat-vector` handle
	- **Output:** `s32` integer
	- **Purpose:** Returns the logical number of elements currently stored (used to bind loop iterations).
* **`%flat-vector-set-count!`**
	- **Input:** `flat-vector` handle, `s32` new-count
	- **Output:** Void
	- **Purpose:** Updates the logical count cursor (critical for actions like truncation, reset, or advancing sizes during appends).

### Bare-Metal Memory I/O Intrinsics

These intrinsics map 1:1 to single CPU read/write assembly operations. They accept a raw pointer and a pre-calculated byte offset.

* **`%raw-mem-read-s32`** / **`%raw-mem-write-s32!`**
	- **Purpose:** Reads/writes signed 32-bit fields (used for IDs, tokens, kind enums, and `subtree_size` values).
* **`%raw-mem-read-s16`** / **`%raw-mem-write-s16!`**
	- **Purpose:** Reads/writes signed 16-bit fields (excellent for highly compressed modifier masks or smaller type configurations).
* **`%raw-mem-read-u8`** / **`%raw-mem-write-u8!`**
	- **Purpose:** Reads/writes unsigned 8-bit bytes (used for boolean flags, ASCII character iterations, or compact token variant properties).

### Memory Lifecycle & Relocation Intrinsics

When a `flat-vector` expands or initializes, it must bypass the standard Scheme heap and talk directly to the OS or C-level virtual memory manager.

* **`%flat-vector-alloc-raw`**
	- **Input:** `s32` byte-capacity
	- **Output:** Raw `ptr`
	- **Purpose:** Invokes a platform allocation (like a raw system `malloc`) to lease a brand-new contiguous block of physical RAM.
* **`%flat-vector-realloc-raw!`**
	- **Input:** `flat-vector` handle, `s32` new-byte-capacity
	- **Output:** Void
	- **Purpose:** Triggers a platform `realloc`. The system finds a larger memory block, automatically shifts the active data block, updates the internal memory descriptor pointers, and clears the old allocation safely—handling the entire *Carbon-style amortized growth footprint* inside a single intrinsic boundary.
* **`%flat-vector-free-raw!`**
	- **Input:** `flat-vector` handle
	- **Output:** Void
	- **Purpose:** Directly returns the array block to the operating system when a compiler pass clears or deallocates a module's file buffer, completely shielding the core Scheme garbage collector from tracking millions of dead array indexes.

