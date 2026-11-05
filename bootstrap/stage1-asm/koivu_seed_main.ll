; ============================================================================
; Part of the Koivu Project, under the Apache License v2.0 with LLVM Exceptions.
; See LICENSE for license information.
; SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
; ============================================================================

; Cannot rely on the syscall assembly instruction because Windows will break between builds and macOS deprecates direct syscalls entirely.
; Therefore using these glue functions.
declare i32 @sys_write(i32 %fd, i8* %buf, i32 %count)
declare i32 @sys_read(i32 %fd, i8* %buf, i32 %count)
declare i8* @sys_alloc(i64 %size)
declare void @sys_exit(i32 %status)

; Define generic, opaque pointers for all Koivu Lisp Objects
%LispObject = type opaque
%LispCell   = type { %LispObject*, %LispObject* }

; ============================================================================
; Core Program Entry Point
; ============================================================================

define i32 @main() {
entry:
    ; 1. Initialize the Page-Based Arena Allocator
    call void @init_arena_allocator()

    ; 2. Boot into the Read-Eval-Print / Bootstrap loop
    call void @koivu_repl()

    ; 3. Clean exit code 0
    ret i32 0
}

; ============================================================================
; Core Eval-Apply Loop
; ============================================================================

define void @koivu_repl() {
entry:
    ; TODO: Implement tokenizing read loop
    ; %form = call %LispObject* @koivu_read()
    ; %result = call %LispObject* @koivu_eval(%LispObject* %form, %LispObject* null)
    ret void
}

define %LispObject* @koivu_eval(%LispObject* %expr, %LispObject* %env) {
entry:
    ; Evaluates expression in a given lexical environment frame
    ret %LispObject* %expr
}

define %LispObject* @koivu_apply(%LispObject* %proc, %LispObject* %args) {
entry:
    ; Applies a primitive code label or closure to structural arguments
    ret %LispObject* null
}

; ============================================================================
; Lisp Core Primitives (CAR, CDR, CONS, READ)
; ============================================================================

define %LispObject* @koivu_read() {
entry:
    ; Parses characters into S-expressions
    ret %LispObject* null
}

define %LispObject* @koivu_cons(%LispObject* %car, %LispObject* %cdr) {
entry:
    ; Takes CAR and CDR, requests a 16-byte block from the Arena Allocator,
    ; applies the 3-bit low-level type tags, and returns the tagged pointer.
    ret %LispObject* null
}

define %LispObject* @koivu_car(%LispObject* %cell_ptr) {
entry:
    ; Masks the type tag bits from the pointer and extracts the first slot
    ret %LispObject* null
}

define %LispObject* @koivu_cdr(%LispObject* %cell_ptr) {
entry:
    ; Masks the type tag bits from the pointer and extracts the second slot
    ret %LispObject* null
}

; ============================================================================
; Memory Runtime (Page-Based Arena Allocator Stub)
; ============================================================================

define void @init_arena_allocator() {
entry:
    ; Issues virtual page allocations to the underlying operating system kernel
    ret void
}
