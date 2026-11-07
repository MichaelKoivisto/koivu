@echo off
set "LLVM_BIN=C:\llvm-release\bin"
"%LLVM_BIN%\llvm-objdump.exe" -d -s -D --source --print-imm-hex koivu_seed.exe
