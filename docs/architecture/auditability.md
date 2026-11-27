# Developer Note: Bootstrap Auditability - Ecosystem Practice and Koivu's Position

**Status:** Developer Note  
**Component:** Global  

> "The only rules that really matter are these: what a man can do and what a man can't do."<br>
> *— Captain Jack Sparrow*

This note describes what the bootstrappable and reproducible-build ecosystems actually do about auditing a binary root, and then states Koivu's position: what it adopts, what it cannot have, and what it deliberately does not attempt. It is a companion to [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md) and [Seed Artifacts](08_seed_artifacts.md), which own the policy; where they disagree with this note, they win.

Two claims are kept apart throughout, because conflating them is how this subject goes wrong: what the ecosystem **practises**, and what Koivu **decides**. The first has sources; the second has reasons.

---

## 1. The byte-audit tradition, and why Koivu does not follow it

The bootstrappable-builds community starts from a seed small enough that one person can read every byte of it. In the Stage0 and GNU Mes lineage the root is hand-written hex or assembly, and the first tool - a `hex0` that turns hex text into bytes - is on the order of a few hundred bytes on a 64-bit architecture. The "512 bytes" figure that circulates in that community comes from boot sectors, not from an audit standard. Above that root the chain grows quickly: reaching a usable C compiler takes several further stages and orders of magnitude more code.

What the tradition actually prescribes is a **principle**, not a threshold: the root must be small enough to audit in full by a person, and it must ship with source that maps to it instruction by instruction. Every project draws its own line, and the lines differ by three orders of magnitude.

**Koivu does not meet that principle, and this note should not pretend otherwise.** Its binary root is `koivu-vesi`: a `.pino` reader, a symbol table, a static stack-balance verifier, an instruction encoder for two architectures, three container writers and the OS glue. That is estimated at roughly 600 KiB with a 1200 KiB ceiling ([Seed Artifacts](08_seed_artifacts.md), section 7). A program with that job cannot be a few kilobytes, and a claim that it is would be the first thing a reader checked.

So there is **no "under 10 KiB" standard**, and no Koivu ceiling derived from one. The number that binds Vesi is the one in [Seed Artifacts](08_seed_artifacts.md), section 7, and its purpose is the one [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2 gives it: size sets the limit below which review stays feasible, and below that limit a simpler, more regular instruction sequence is easier to verify even when it is larger. Size is a ceiling to stay under, not a quantity to minimise.

What replaces the byte-by-byte guarantee is a set of recipes, ordered by strength, in [Seed Artifacts](08_seed_artifacts.md), section 6. Two of them carry most of the weight:

* **Reassembly.** Vesi's assembly is committed beside each published binary, rendered by Vesi from the same image its binary is lowered from. A user reassembles it with the platform assembler and compares the result byte for byte with what they downloaded.
* **Lowering the seed yourself.** The seed is published as one target-independent image, and the user turns it into a seed with the Vesi they have just checked. No seed binary is distributed, so there is nothing about the seed's machine code to take on faith.

Both are weaker than reading every byte of a 300-byte seed, and stronger in a different way: the user performs the last step, and the artifact they check is a program with one narrow job.

## 2. Diverse Double-Compiling, and why it is out of reach here

David A. Wheeler's Diverse Double-Compiling (2005, extended 2009) is the practical answer to Ken Thompson's *Reflections on Trusting Trust*. Compile the compiler's source with two independent compilers and compare the results bit for bit: if they agree, then, absent collusion between the two chains, the binary really does follow from the published source.

The technique needs one thing Koivu cannot supply: **an independent implementation that produces the same output.** For Koivu that means a second Pino lowerer and a second Scheme front end - precisely the mirror that [Koivu Vesi](koivu-vesi.md), section 1 refuses, and that [Backend](backend.md) refuses as a library. Two lowering paths would each have to be maintained and audited, and the project would be back where the split started.

Two tempting shortcuts do not work either:

* **Running the seed image under Chez Scheme.** `koivu-seed.pino` is Pino IR, not Scheme. An R6RS host cannot execute or lower it. A translator written in Chez would *be* the second Vesi, with all the cost that implies.
* **Comparing a chain that uses Vesi against one that does not.** If the second chain does not use Vesi, its output differs by construction and the comparison proves nothing. If it does use Vesi, it is not independent and cannot expose a Trojan inside Vesi.

So strict DDC is a recorded non-goal, alongside two others it belongs with: [Seed Artifacts](08_seed_artifacts.md), section 5 (provenance cannot be proved) and [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 8 (the chain does not exclude a deliberately planted backdoor). A user who needs more than that needs the Secure Path, which is a different procedure with different assumptions rather than a stronger version of this one.

**What Koivu does have** is reproducibility and self-consistency, and it is worth naming precisely:

* **The compiler fixpoint.** Stage 3 Version B and Version C are compared byte for byte ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 6).
* **The lowerer fixpoint.** A Vesi built by Vesi from its own image is compared with the Vesi that built it ([Koivu Vesi](koivu-vesi.md), section 7).
* **The golden image.** CI recompiles the seed's source, prints the image and fails if it differs from the committed one ([Stage 1 (Seed)](04_stage1_seed.md), section 8).
* **An interface a third party can read.** `.pino` is specified and canonically printed ([Koivu Vesi](koivu-vesi.md), section 2), so anyone can write their own reader and check a published image without running a line of Koivu code. Two independently written readers disagreeing is a defect in the specification or in one of them - which is a real check, and cheap, even though it is not DDC.

None of these detect a backdoor that reproduces itself faithfully. That is Thompson's point, and the note keeps it rather than arguing with it.

## 3. Determinism

The fixpoint checks and the golden image are worthless if a build depends on its environment, so determinism is an acceptance criterion rather than a nicety ([Backend](backend.md), section 8, criterion 1).

What breaks it, and what the documents require instead:

* **Timestamps.** No build time anywhere, including the PE `TimeDateStamp`, which is written as zero.
* **Paths.** No absolute paths, no build directory names, no hostnames.
* **Ordering.** Symbols, labels and fixups are emitted in insertion order. Nothing may iterate in an order that depends on a memory address, a hash seed or a pointer value.
* **Allocation.** The arena hands out objects sequentially from a fixed base, so allocation order is deterministic by construction. It is the *order*, not the address, that matters: address-space randomisation affects a process at run time and never the bytes of a file, so a fixed load address buys nothing here and is not a requirement.
* **Canonical printing.** The image is printed one form per line, one instruction per line, decimal integers with no leading zeros ([Koivu Vesi](koivu-vesi.md), section 2). Without that the comparison has no well-defined result.

Container headers deserve their own line because they are the usual place metadata leaks back in: no build-ID, no `.comment`, no section names carrying a toolchain or a date.

## 4. Audit checklist for a published Vesi binary

Four invariants, checked against the disassembled binary before a release. They are the mechanical part of the recipes in [Seed Artifacts](08_seed_artifacts.md), section 6, not a replacement for them.

| Check | Method | Pass criterion |
| :--- | :--- | :--- |
| **1. Host primitives only** | Disassemble and inspect the syscall and `svc` sites | Only the seven host primitives of [Stage 1 (Seed)](04_stage1_seed.md), section 3. No sockets, no process creation, no dynamic library loading. |
| **2. No Trojan-shaped constants** | `strings` plus disassembly of immediate values | String and immediate data are Pino opcode names, diagnostics and container constants. Nothing that looks like a target of an attack - a file name, a host name, a credential, a compiler name. |
| **3. No self-modifying code** | Inspect every branch and call target | Control flow stays inside the code segment. Nothing branches into the input buffer, the arena or the emitted image. |
| **4. Byte-exact source match** | Assemble the committed `.s`, compare hashes with the published binary | Identical. This is the strongest mechanical check a user has, and the reason the `.s` is committed at all. |

Two notes on applying it. The binary is **published, not committed**; the `.s` is committed beside it and is a reading aid, never a build input ([Seed Artifacts](08_seed_artifacts.md), sections 2 and 3). And on Windows a bare system has no assembler, so check 4 is unavailable there and the remaining checks carry the whole burden - which is why Vesi's budget is the tighter of the two.

## 5. What each published artifact proves

Rebuilt from [Seed Artifacts](08_seed_artifacts.md), section 2 rather than from a parallel list, so that the two cannot drift:

| Artifact | Form | What it admits | What it does not prove |
| :--- | :--- | :--- | :--- |
| `koivu-vesi` | machine binary, one per host, optionally signed on Windows | reassembly against the committed `.s`; hex review of the entry point and syscall stubs; antivirus scan; signature check | that it was built from the published source, in the general case |
| `koivu-vesi.s` | text, committed, one per host | reading; local reassembly with the platform assembler | that the published binary matches, unless the reader compares |
| `koivu-seed.pino` | text, one file for all hosts | reading against the seed's source; lowering it locally with a checked Vesi | that it was printed from the published source, unless the reader compares |
| Vesi source, seed source | text, in the repository | full human review - these are the source of truth | that any artifact was produced from them |
| sapling source | text, in the repository | ordinary code review; the user builds the sapling with the seed | nothing is claimed - it is scaffolding, never released |
| Stage 3 source | text, in the repository | ordinary code review, plus the B == C fixpoint once the chain is self-hosting | - |

The last two rows are here to stop a familiar mistake: the sapling and Stage 3 are **not** distributed artifacts. Only Vesi's binary and the seed's image are published ([Seed Artifacts](08_seed_artifacts.md), section 1).

The honest summary is a single sentence: Koivu publishes one small program and one readable image, makes the last step of the build the user's own, and proves reproducibility rather than honesty.
