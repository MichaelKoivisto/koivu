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
| Linux | `x86_64` | committed `.s`, assembled locally | **1 - highest** |
| Windows | `x86_64` | published `koivu-seed.exe`, optionally signed | **2** |
| macOS | `arm64` | committed `.s`, assembled locally | **3 - lowest of the three** |

These three are the only host platforms. Other host architectures are not rejected, but they are very low priority: it is simply unlikely that anyone would want them.

### Why the Order Is What It Is

The order is a deliberate judgement, not a side effect of technical convenience. It is recorded here because it drives several other decisions: which platform reaches the bootstrap goal first, which platform is the reference for the seed size budget, and where experimentation with trust is expected to happen.

* **Linux is first.** It combines a high number of advanced users with the technical and organizational freedom to experiment with bootstrapping and trust. Those are exactly the users who will read the `.ll` sources, assemble the seed themselves and try the Secure Path.
* **Windows is second.** It has a large user base, but it is a closed platform, and its vendor is unlikely to experiment with bootstrapping. Koivu's role there is therefore narrower: a dependency-free compiler chain option for ordinary users, not a platform for trust experiments.
* **macOS is third.** It has fewer users than Windows, it is an even more closed platform, and signing of executable files adds complexity that the other two platforms do not have (see section 6).

The artifact forms and their trust levels are defined in [Seed Artifacts](08_seed_artifacts.md), section 2. Windows receives a binary because a bare Windows OS has no assembler; POSIX hosts receive assembly sources because they do.

## 3. Target Architectures

| Target architecture | Status | Notes |
| :--- | :--- | :--- |
| `x86_64` | first-class target | initial supported set |
| `arm64` | first-class target | initial supported set |
| 32-bit targets, for example `arm32` | future, cross-compilation only | see section 5 |
| any other architecture | reachable through a new target description | see section 4 |

A target is supported when a production target description exists for it (see [Backend](backend.md), section 5). A target becomes a *host* only when a seed artifact exists for it as well.

## 4. Porting to a New Platform

Two different goals are often confused, and they require different work.

### Goal A: a Koivu compiler that targets the new platform

This is what makes Koivu useful for producing code for that platform.

1. Write a full **production target description** for the new target.
2. Cross-compile Stage 3 on an existing host using the production backend.

Result: a native Koivu compiler that emits code for the new platform. This goal does **not** by itself produce a seed for that platform.

### Goal B: a seed that runs on the new platform

This is what makes the chain bootstrappable locally, without an existing host of that platform.

1. Write a **simple target description** for the new target. Its scope is fixed by the closure invariant in [Backend](backend.md), section 4: exactly the IR that Stage 1 emits when compiling the bridge, plus the OS glue.
2. Cross-compile the Stage 1 seed on an existing host.
3. Add the resulting artifact to the published set for that platform (see [Seed Artifacts](08_seed_artifacts.md), section 2).
4. Verify in order: Stage 1 test suite, bridge build, Stage 3 build.

Result: the platform can bootstrap Koivu locally. This goal does **not** by itself make the platform a useful compilation target.

Neither goal implies the other. Goal B is the prerequisite for local bootstrapping; Goal A is the prerequisite for emitting code for the platform.

This workflow is the reason the `.ll` sources of the seed are kept and published: a porter needs the source, not only a binary (see [Seed Artifacts](08_seed_artifacts.md), section 3).

## 5. Cross-Compilation Scope

* **Between 64-bit hosts:** required by the porting workflow in section 4 and therefore in scope.
* **To 32-bit targets** such as `arm32`: planned for the future, cross-compilation only. This is different from a compiler *running* on a 32-bit OS.
* **Running on a 32-bit host:** still under question. It may become possible as the project matures, if it does not complicate things too much.

## 6. Platform Notes: macOS

macOS is the platform with the largest gap between "supported" and "as simple as Linux", for two reasons that are worth stating before any code is written.

### 6.1 Glue Layer

The six host primitives in [Stage 1 (Seed)](04_stage1_seed.md), section 3 stay the same, but their implementation cannot use raw syscalls. On macOS, syscall numbers are not a stable ABI and `libSystem` is the supported interface, so a separate glue file (`koivu_seed_glue_macos.ll`) calls `libSystem` instead of issuing `svc` instructions.

This is the expected answer to the syscall problem, and it has one consequence for the project's own claims: on macOS the seed is a **dynamically linked** Mach-O executable. "Zero external dependencies" therefore has to be read as "no third-party dependencies"; on macOS the seed links against `libSystem`, which ships with the OS. Static linking against macOS system libraries is not an option.

### 6.2 Container Writer and Signing

**Decision: macOS ships as `.s` only.** The seed artifact for macOS is a committed assembly file that the user assembles locally. No ad-hoc signature is embedded in a distributed binary and no notarization is required for the seed artifact itself. This is the simplest option, and it matches the priority reasoning in section 2.

One consequence has to be stated clearly, because it is easy to miss:

> Shipping `.s` only solves **distribution**, not **execution**. On Apple Silicon, the executable that the seed *produces* must also be signed, not just the seed itself.

So on macOS there are two ways to get a runnable bridge binary, and only one of them is simple:

* **Seed emits `.s` for the bridge, platform tools finish the job.** The seed uses the emitter it already has; the user runs the platform assembler, linker and, if needed, `codesign`. No Mach-O writer is required at all, but macOS then depends on external tools and does **not** reach the bootstrap goal defined in [Backend](backend.md), section 1.
* **Seed emits a signed Mach-O itself.** This requires a Mach-O container writer plus an ad-hoc signer inside the seed - a code directory and a superblob, not just headers - which is the opposite of the simplest option.

The first option is chosen for now. macOS is therefore a Simple Path platform: it is supported, it bootstraps, but it keeps using platform tools, while Linux and Windows are expected to reach the bootstrap goal first.

This also means that whether a Mach-O container writer is needed at all in the near term is open question 1. Resolved decision 6 in [Backend](backend.md), section 9 lists ELF, PE and Mach-O as eventually required; that remains true as a long-term statement, but Mach-O is no longer on the near-term path.

## 7. Open Questions

| # | Question | Why it matters |
| :--- | :--- | :--- |
| 1 | Is a Mach-O container writer in scope in the near term, or is macOS served by `.s` output plus platform `as`, `ld` and `codesign` until further notice? | decides whether the seed grows by a Mach-O writer and an ad-hoc signer; revisits resolved decision 6 in [Backend](backend.md), section 9 |
| 2 | Do Linux and macOS share one POSIX source set (glue, emitter, ELF writer), or are they separate seed sources? | if macOS uses no container writer, sharing is cheap; if it gets one, separate sources may be clearer |
| 3 | Are binaries for other targets published per release, or on request? | also recorded as an open item in [Seed Artifacts](08_seed_artifacts.md), section 8 |
