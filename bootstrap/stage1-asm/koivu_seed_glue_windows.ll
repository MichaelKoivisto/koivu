; Target glue for Windows
target datalayout = "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-windows-msvc"

; --- External Win32 API Declarations ---
declare dllimport ptr @GetStdHandle(i32)
declare dllimport i32 @WriteFile(ptr, ptr, i32, ptr, ptr)
declare dllimport i32 @ReadFile(ptr, ptr, i32, ptr, ptr)
declare dllimport ptr @GetProcessHeap()
declare dllimport ptr @HeapAlloc(ptr, i32, i64)
declare dllimport void @ExitProcess(i32)

; --- 1. sys_write ---
; Maps fd (1=stdout, 2=stderr) to Windows handles and writes bytes
define i32 @sys_write(i32 %fd, ptr %buf, i32 %count) {
entry:
    ; Local variable to store number of bytes written
    %bytesWritten = alloca i32, align 4

    ; Determine standard device ID (-11 for stdout, -12 for stderr)
    ; Simple check: if fd == 2, use -12, else use -11
    %is_stderr = icmp eq i32 %fd, 2
    %std_id = select i1 %is_stderr, i32 -12, i32 -11

    ; Get the raw OS handle
    %handle = call ptr @GetStdHandle(i32 %std_id)
    %handle_valid = icmp eq ptr %handle, null
    br i1 %handle_valid, label %error, label %do_write

do_write:
    ; WriteFile(handle, buf, count, &bytesWritten, NULL)
    %status = call i32 @WriteFile(ptr %handle, ptr %buf, i32 %count, ptr %bytesWritten, ptr null)
    %success = icmp ne i32 %status, 0
    br i1 %success, label %ret_bytes, label %error

ret_bytes:
    %result = load i32, ptr %bytesWritten, align 4
    ret i32 %result

error:
    ret i32 -1
}

; --- 2. sys_read ---
; Maps fd (0=stdin) to Windows handle and reads bytes
define i32 @sys_read(i32 %fd, ptr %buf, i32 %count) {
entry:
    %bytesRead = alloca i32, align 4

    ; Get standard input handle (-10)
    %handle = call ptr @GetStdHandle(i32 -10)
    %handle_valid = icmp eq ptr %handle, null
    br i1 %handle_valid, label %error, label %do_read

do_read:
    ; ReadFile(handle, buf, count, &bytesRead, NULL)
    %status = call i32 @ReadFile(ptr %handle, ptr %buf, i32 %count, ptr %bytesRead, ptr null)
    %success = icmp ne i32 %status, 0
    br i1 %success, label %ret_bytes, label %error

ret_bytes:
    %result = load i32, ptr %bytesRead, align 4
    ret i32 %result

error:
    ret i32 -1
}

; --- 3. sys_alloc ---
; Gets the default process heap and allocates zeroed memory
define ptr @sys_alloc(i64 %size) {
entry:
    %heap = call ptr @GetProcessHeap()
    ; Flag 8 = HEAP_ZERO_MEMORY
    %mem = call ptr @HeapAlloc(ptr %heap, i32 8, i64 %size)
    ret ptr %mem
}

; --- 4. sys_exit ---
; Safely terminates the process
define void @sys_exit(i32 %status) {
entry:
    call void @ExitProcess(i32 %status)
    unreachable
}
