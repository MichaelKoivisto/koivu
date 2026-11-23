# Koivu Platforms and Targets

**Status:** Architecture Blueprint  

**Component:** Global  

> Scarlet: Jack!<br>
> Jack: Scarlet!<br>
> (Scarlet promptly delivers a hard slap to Jack's face and walks away angrily.)<br>
> Jack: I'm not sure I deserved that.<br>
> (Immediately, another woman named Giselle steps up to him.)<br>
> Giselle: Who are you?!<br>
> (Giselle slaps Jack hard across the opposite cheek and storms off.)<br>
> Jack: I may have deserved that.

---

## 1. Terms and Scope

Two terms are used consistently throughout the blueprints:

* **Host** - the platform where a Koivu program runs. The Stage 1 seed is a host program; so is every compiler built from it.
* **Target** - the platform a compiler emits code for. A host may target itself (native) or another platform (cross-compilation).

Minimum host platforms for the Koivu project are 64-bit Windows, Linux and macOS. The initial set of target architectures is `x86_64` and `arm64`.

## 2. Host Platforms

| Host platform | Architecture | Seed artifact form | Priority |
| :--- | :--- | :--- | :--- |
| Linux | `x86_64` | published `koivu-seed` binary; committed `.s` for reading | **1 - highest** |
| Windows | `x86_64` | published `koivu-seed.exe`, optionally signed; committed `.s` for reading | **2** |
| macOS | `arm64` | published binary - unsigned Mach-O, ad-hoc signed by the user; committed `.s` | **3 - lowest of the three** |

These three are the only host platforms. Other host architectures are not rejected, but they are very low priority: it is simply unlikely that anyone would want them.

### Why the Order Is What It Is

The order is a deliberate judgement, not a side effect of technical convenience. It is recorded here because it drives several other decisions: which platform reaches the bootstrap goal first, which platform is the reference for the seed size budget, and where experimentation with trust is expected to happen.

* **Linux is first.** It combines a high number of advanced users with the technical and organizational freedom to experiment with bootstrapping and trust. Those are exactly the users who will read the seed source, compare it against the committed assembly and try the Secure Path.
* **Windows is second.** It has a large user base, but it is a closed platform, and its vendor is unlikely to experiment with bootstrapping. Koivu's role there is therefore narrower: a dependency-free compiler chain option for ordinary users, not a platform for trust experiments.
* **macOS is third.** It has fewer users than Windows, it is an even more closed platform, and signing of executable files adds complexity that the other two platforms do not have (see section 6).

The artifact forms and their trust levels are defined in [Seed Artifacts](08_seed_artifacts.md), section 2. **Every host receives a published binary**, because a released binary is what actually enables bootstrapping; committed `.s` files are a convenience for readers and never a build input ([Seed Artifacts](08_seed_artifacts.md), section 3). A bare Windows OS has no assembler, so local assembly is not an option there at all. POSIX hosts can assemble locally, which is what makes their `.s` file useful to read alongside the binary.

## 3. Target Architectures

| Target architecture | Status | Notes |
| :--- | :--- | :--- |
| `x86_64` | first-class target | initial supported set |
| `arm64` | first-class target | initial supported set |
| 32-bit targets, for example `arm32` | future, cross-compilation only | see section 5 |
| any other architecture | reachable through a new target description | see section 4 |

A target is supported when a production target description exists for it (see [Backend](backend.md), section 6). A target becomes a *host* only when a seed artifact exists for it as well.

## 4. Porting to a New Platform

Two different goals are often confused, and they require different work.

### Goal A: a Koivu compiler that targets the new platform

This is what makes Koivu useful for producing code for that platform.

1. Write a full **production target description** for the new target.
2. Cross-compile Stage 3 on an existing host using the production backend.

Result: a native Koivu compiler that emits code for the new platform. This goal does **not** by itself produce a seed for that platform.

### Goal B: a seed that runs on the new platform

This is what makes the chain bootstrappable locally, without an existing host of that platform.

1. Write a **Pino target description** for the new target. Its scope is fixed by the ISA invariant in [Backend](backend.md), section 4: a byte template for every instruction in the declared Pino ISA, plus the OS glue.
2. Cross-compile the Stage 1 seed on an existing host.
3. Add the resulting artifact to the published set for that platform (see [Seed Artifacts](08_seed_artifacts.md), section 2).
4. Verify in order: Stage 1 test suite, bridge build, Stage 3 build.

Result: the platform can bootstrap Koivu locally. This goal does **not** by itself make the platform a useful compilation target.

Neither goal implies the other. Goal B is the prerequisite for local bootstrapping; Goal A is the prerequisite for emitting code for the platform.

This workflow is the reason the seed source is kept and published: a porter needs the source, not only a binary ([Seed Artifacts](08_seed_artifacts.md), sections 2 and 3). The seed source is Scheme. The C seed that precedes it is a development scaffold and is never released.

## 5. Cross-Compilation Scope

* **Between 64-bit hosts:** required by the porting workflow in section 4 and therefore in scope.
* **To 32-bit targets** such as `arm32`: planned for the future, cross-compilation only. This is different from a compiler *running* on a 32-bit OS.
* **Running on a 32-bit host:** still under question. It may become possible as the project matures, if it does not complicate things too much.

## 6. Platform Notes: Linux and macOS

Linux and macOS share one glue source set and differ in their container format and in signing. macOS is also the platform with the largest gap between "supported" and "as simple as Linux". Both facts are worth stating before any code is written.

### 6.1 Glue Layer

Linux and macOS share **one POSIX source set**, `bootstrap/stage1/os/posix`. The seven host primitives of [Stage 1 (Seed)](04_stage1_seed.md), section 3 are the only thing that differs between the two, and the difference is confined to how a primitive is issued: on Linux it is a syscall instruction, on macOS a call into `libSystem`, because syscall numbers are not a stable ABI there and `libSystem` is the supported interface.

That boundary is the one the seed is already built around - the primitives are exactly where host-specific code is allowed to exist - so sharing everything above it costs nothing, and it keeps two POSIX hosts as one source set instead of two that must be kept in step. Windows keeps its own set, because its primitives are different functions over different handle types rather than the same functions reached a different way.

Two consequences follow for the project's own claims, one permanent and one temporary.

**Permanent:** on macOS the seed is a **dynamically linked** Mach-O executable. "Zero external dependencies" therefore has to be read as "no third-party dependencies"; on macOS the seed links against `libSystem`, which ships with the OS, and static linking against macOS system libraries is not an option.

**Temporary:** on Linux the answer depends on the phase. The C scaffold before M2 is built by a C compiler and reaches the same seven primitives through libc, so it is a dynamically linked ELF as well. From M2 the seed emits syscalls itself and links nothing. That difference belongs to the scaffold rather than to the design, and it disappears when the scaffold does.

### 6.2 Container Writer and Signing

The seed writes the executable container itself on all three hosts - ELF64, PE32+ and Mach-O ([Backend](backend.md), section 5) - so no assembler and no linker appear anywhere in the chain, on any platform.

The container writer is not part of the shared POSIX source set. It is selected by output format rather than by host, and ELF64 and Mach-O share no structure: one is a table of program headers over flat segments, the other a linked list of load commands. Linux and macOS therefore share the glue and differ in the writer, which is the smallest split the formats allow.

macOS still differs from the other two in one respect that no amount of care removes: an executable on Apple Silicon must be signed before it will run.

**Writing the container and signing it are two separate jobs, and only the first belongs in the seed.** The seed writes an unsigned Mach-O, and the user ad-hoc signs the result:

```
codesign --force --sign - koivu-bridge
```

That command needs no certificate, no developer account and no network, and it is the same command the user already runs for any locally built binary on Apple Silicon. The alternative - a code directory and a superblob inside the seed - would add a second binary format to implement and audit, bought for no gain in convenience.

Raw syscalls are not a stable interface on macOS, so the executables the seed produces link against `libSystem`, as the seed itself does (section 6.1).

The consequence for the roadmap is that macOS reaches the bootstrap goal like the other two hosts: the seed lowers Pino IR and writes the container, and the only platform tool left is the signing command ([Roadmap to Self-hosting](selfhosting.md), section 7). All three container formats are in scope, as resolved decision 8 in [Backend](backend.md), section 9 records.

## 7. Open Questions

| # | Question | Why it matters |
| :--- | :--- | :--- |
| 1 | Are binaries for other targets published per release, or on request? | also recorded as an open item in [Seed Artifacts](08_seed_artifacts.md), section 8 |
