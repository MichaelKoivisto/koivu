; Target glue for POSIX (Linux and macOS)
declare i64 @write(i32, i8*, i64)
declare i64 @read(i32, i8*, i64)
declare i8* @malloc(i64)
declare void @exit(i32)

define i32 @sys_write(i32 %fd, i8* %buf, i32 %count) {
    %c_count = zext i32 %count to i64
    %res = call i64 @write(i32 %fd, i8* %buf, i64 %c_count)
    %trunc_res = trunc i64 %res to i32
    ret i32 %trunc_res
}

define i32 @sys_read(i32 %fd, i8* %buf, i32 %count) {
    %c_count = zext i32 %count to i64
    %res = call i64 @read(i32 %fd, i8* %buf, i64 %c_count)
    %trunc_res = trunc i64 %res to i32
    ret i32 %trunc_res
}

define i8* @sys_alloc(i64 %size) {
    %ptr = call i8* @malloc(i64 %size)
    ret i8* %ptr
}

define void @sys_exit(i32 %status) {
    call void @exit(i32 %status)
    unreachable
}
