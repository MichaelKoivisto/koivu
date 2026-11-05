; Target glue for Windows
declare i8* @GetStdHandle(i32) dllimport
declare i32 @WriteFile(i8*, i8*, i32, i32*, i8*) dllimport
declare i32 @ReadFile(i8*, i8*, i32, i32*, i8*) dllimport
declare i8* @HeapAlloc(i8*, i32, i64) dllimport
declare i8* @GetProcessHeap() dllimport
declare void @ExitProcess(i32) dllimport

define i32 @sys_write(i32 %fd, i8* %buf, i32 %count) {
    ; Map POSIX fd 1 to Windows STD_OUTPUT_HANDLE (-11)
    ; Map POSIX fd 2 to Windows STD_ERROR_HANDLE (-12)
    ; Map POSIX fd 0 to Windows STD_INPUT_HANDLE (-10)
    %is_stdout = icmp eq i32 %fd, 1
    %win_fd = select i1 %is_stdout, i32 -11, i32 -12
    %is_stdin = icmp eq i32 %fd, 0
    %target_handle_id = select i1 %is_stdin, i32 -10, i32 %win_fd

    %handle = call i8* @GetStdHandle(i32 %target_handle_id)

    ; Allocate space on stack for written bytes tracking
    %bytes_written = alloca i32
    ; WriteFile returns non-zero on success
    %status = call i32 @WriteFile(i8* %handle, i8* %buf, i32 %count, i32* %bytes_written, i8* null)

    %written = load i32, i32* %bytes_written
    ret i32 %written
}

define i32 @sys_read(i32 %fd, i8* %buf, i32 %count) {
    %handle = call i8* @GetStdHandle(i32 -10) ; Assumed stdin for simplicity
    %bytes_read = alloca i32
    %status = call i32 @ReadFile(i8* %handle, i8* %buf, i32 %count, i32* %bytes_read, i8* null)
    %read = load i32, i32* %bytes_read
    ret i32 %read
}

define i8* @sys_alloc(i64 %size) {
    %heap = call i8* @GetProcessHeap()
    ; 8 = HEAP_ZERO_MEMORY
    %ptr = call i8* @HeapAlloc(i8* %heap, i32 8, i64 %size)
    ret i8* %ptr
}

define void @sys_exit(i32 %status) {
    call void @ExitProcess(i32 %status)
    unreachable
}
