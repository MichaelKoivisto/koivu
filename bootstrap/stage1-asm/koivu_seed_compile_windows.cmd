@echo off
set "LLVM_BIN=C:\llvm-release\bin"

:: Point this to the x64 Windows SDK library directory on your machine:
:: set "WIN_SDK_LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64"

echo [1/2] Compiling LLVM IR...
"%LLVM_BIN%\llc.exe" -filetype=obj -mtriple=x86_64-pc-windows-msvc koivu_seed_main.ll -o koivu_seed_main.obj
if %errorlevel% neq 0 goto :error

"%LLVM_BIN%\llc.exe" -filetype=obj -mtriple=x86_64-pc-windows-msvc koivu_seed_glue_windows.ll -o koivu_seed_glue_windows.obj
if %errorlevel% neq 0 goto :error

echo [2/2] Linking without MSVC Libraries...
"%LLVM_BIN%\lld-link.exe" /lib /def:kernel32.def /machine:x64 /out:kernel32.lib
::"%LLVM_BIN%\lld-link.exe" koivu_seed_main.obj koivu_seed_glue_windows.obj /subsystem:console /nodefaultlib /entry:main /machine:x64 /libpath:"%WIN_SDK_LIB%" kernel32.lib /out:koivu_seed.exe
"%LLVM_BIN%\lld-link.exe" koivu_seed_main.obj koivu_seed_glue_windows.obj /subsystem:console /nodefaultlib /entry:main /machine:x64 kernel32.lib /out:koivu_seed.exe
if %errorlevel% neq 0 goto :error

echo [SUCCESS] Built koivu_seed.exe using purely absolute paths!
goto :end

:error
echo [FAIL] Compilation or Linking failed.

:end
pause
