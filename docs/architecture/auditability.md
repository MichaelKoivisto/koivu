# Developer Note: Industry Standards & Common Practices for Bootstrap Auditability

> **Status:** Developer Note
> **Component:** Security, Bootstrapping & Seed Verification

> "The only rules that really matter are these: what a man can do and what a man can't do."<br>
> *— Captain Jack Sparrow*

This developer note documents industry standards and established conventions in the **Bootstrappable Builds** and **Reproducible Builds** ecosystems, mapping them directly onto Koivu's four-tier bootstrap chain (`koivu-vesi` $\rightarrow$ `koivu-seed.pino` $\rightarrow$ `koivu-sapling.scm` $\rightarrow$ `Stage 3`).

---

## 1. The Minimal Binary Root Tradition (`Hex0` / `Stage0`)

In modern bootstrap engineering (pioneered by the **Stage0** and **GNU Mes** projects), the initial binary seed—the **Trusted Computing Base (TCB)** root—must be small enough for a single security engineer to audit byte-by-byte without automated decompilers.

* **Industry Standard:** Keep the opaque binary root under **10 KiB** (ideally 512 bytes to 8 KiB) and ship **commented assembly source** (`.s` / `.hex0`) alongside the executable so every machine instruction maps 1-to-1 to a documented line of source.
* **Koivu Application:**
  * `koivu-vesi` is the **sole binary root** of the Koivu bootstrap chain (~6.5–8.5 KiB on `x86_64` and `arm64`).
  * Because `koivu-vesi` is a passive 26-opcode template stamper with zero semantic analysis, optimizer reordering, or macro expansion, its disassembled instructions (`objdump -d`) correspond linearly to its source specification.
  * Every distributed binary seed (`koivu-vesi.exe` on Windows) must be accompanied by its matching commented assembly source (`koivu-vesi.s`) so auditors can verify exact byte equivalence.

---

## 2. Diverse Double-Compiling (DDC)

First formalized by David A. Wheeler (2005/2009) as a practical defense against Ken Thompson's *"Reflections on Trusting Trust"* attack, **Diverse Double-Compiling (DDC)** proves that a self-hosting compiler binary was faithfully compiled from its published source code without relying on trust in the seed binary.

* **Industry Standard:** Compile the compiler's source code through **two completely independent compiler chains** (Chain A: the project's own bootstrap seed; Chain B: an unrelated, trusted third-party compiler/interpreter) and verify that the resulting compiler binaries are **bit-for-bit identical**.
* **Koivu Application:**
  * Because `koivu-seed.pino`, `koivu-sapling.scm`, and `Stage 3` are distributed purely as **plain-text S-expressions**, an independent R6RS/Chez Scheme host runtime can execute or lower them directly without touching `koivu-vesi`.
  * **Koivu DDC Verification Procedure:**
    1. Build `Stage 3` (Version B) via the native Koivu chain (`koivu-vesi` $\rightarrow$ `koivu-seed.pino` $\rightarrow$ `koivu-sapling.scm` $\rightarrow$ `Stage 3`).
    2. Build `Stage 3` (Version B') by running `koivu-sapling.scm` and `Stage 3` under an independent host Scheme implementation (e.g., Chez Scheme) emitting the exact same Pino IR / machine code templates.
    3. Assert `sha256sum(Version B) == sha256sum(Version B')`. Any discrepancy immediately exposes either a non-determinism bug or a hidden backdoor in `koivu-vesi`.

---

## 3. Deterministic & Reproducible Builds (SLSA / Reproducible Builds)

Both the **B == C fixpoint check** (`02_bootstrapping_and_trust.md`, Section 6) and **DDC** fail if the compiler embeds environment-specific metadata or relies on non-deterministic traversal order.

* **Industry Standard:** Strip all timestamps, build directory paths, hostname strings, randomized hash seeds, and pointer-address-dependent iteration orders (`SOURCE_DATE_EPOCH` compliance).
* **Koivu Application:**
  * **Deterministic Arena Offsets:** Koivu's Pass-Based Bump Arena allocates objects sequentially from a fixed base address (`0x400000` on Linux `x86_64`), eliminating OS ASLR pointer-hash variation during symbol interning or label resolution.
  * **Insertion-Ordered Tables:** Symbol pools (`(symbols ...)`) and label fixup lists must maintain strict insertion order rather than memory-address hash order.
  * **Zero Metadata Embedding:** ELF64, Mach-O, and PE32+ headers emitted by `koivu-vesi` must hardcode `TimeDateStamp = 0` and omit `.comment` or build-ID sections.

---

## 4. Seed Binary Audit Checklist

Before releasing or updating any checked-in `koivu-vesi` seed artifact, maintainers must verify four security invariants against the disassembled binary:

| Audit Check | Verification Command / Method | Pass Criterion |
| :--- | :--- | :--- |
| **1. Strict Syscall Whitelist** | `objdump -d koivu-vesi` (inspect `syscall` / `svc #0` call sites) | Invokes **only** the 6 approved OS primitives (`mmap`, `open`, `fstat`, `read`, `write`, `exit`). Zero network (`socket`) or process-spawn (`execve`) syscalls. |
| **2. Zero Pattern-Matching Trojan Logic** | Inspect all string literals and immediate constants (`strings` / disassembly) | Contains **only** Pino opcode names, error diagnostics, and OS header constants—no target-specific strings (e.g., `"stage3"`, `"login"`, `"password"`). |
| **3. No Self-Modifying Code** | Inspect branch targets (`jmp`, `call`, `br`, `blr`) | Control flow jumps strictly within the `.text` code segment; never branches into `SourceBuffer` or dynamically allocated arena heap memory. |
| **4. Byte-Exact Source Match** | Assemble `koivu-vesi.s` and compare `sha256sum` against binary | `sha256sum(assembled) == sha256sum(distributed_binary)`. |

---

## 5. Summary of Trust Guarantees Across Koivu Artifacts

| Artifact | Distributed Form | Primary Audit Mechanism |
| :--- | :--- | :--- |
| **`koivu-vesi`** | Machine binary / `.s` (~7 KiB) | Manual disassembly audit + Syscall whitelist + DDC cross-check |
| **`koivu-seed.pino`** | Textual Pino IR (`.pino`) | Static stack-depth verification (`pino-verify`) + linear S-expression inspection |
| **`koivu-sapling.scm`** | Stage 1 Scheme source (`.scm`) | High-level source code review |
| **`Stage 3`** | Full Koivu Scheme source (`.scm`) | High-level source review + `Version B == Version C` fixpoint check |
