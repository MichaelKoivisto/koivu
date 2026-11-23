# Koivu Bootstrapping Paths and Trust

**Status:** Architecture Blueprint  

**Component:** Global  

> Pintel: "So, what Barbossa did is, he tied a cannon to Bootstrap's bootstraps."<br>
> Ragetti: "Bootstrap's bootstraps..."<br>
> 
> *— reminiscing how they sent "Bootstrap Bill" Turner to the bottom of the ocean, only to later realize they needed his blood to break the Curse of the Black Pearl.*

---

## 1. What This Document Covers

Bootstrapping has two distinct meanings in Koivu, and both are covered here:

* **The build chain** - how the seed produces the bridge, the bridge produces Stage 3, and Stage 3 eventually produces itself. This is described step by step in section 6.
* **The trust question** - what a user can verify about the binaries they run, and what they cannot. This is described in sections 3 to 5.

The milestone names (M0 to M4) used below are defined in [Backend](backend.md), section 1. The artifact forms are defined in [Seed Artifacts](08_seed_artifacts.md).

## 2. The Seed

The seed is the only compiler Koivu distributes. Every other compiler in the chain is built from source on the machine that uses it. That asymmetry decides what has to be audited and what does not, and most of the reasoning in this document follows from it.

### One implementation, not one per target

The seed is written once and translated per target. It is not written separately in each target's assembly: duplicating it per host would multiply the review surface by the number of hosts and would guarantee that the hosts drift apart.

### The implementation language is a staged decision

The seed's source language changes once during the project's life. This is deliberate, not a compromise.

* **Early development: C.** The seed is written in C and built with an LLVM C compiler. C is chosen because it is the fastest route to a working chain - the seed's hardest work is byte-level (container headers, instruction templates), and C is the natural language for it. The C seed is a prototype. It is deleted, not maintained, once the chain can build the seed itself.
* **Late development: Scheme.** The seed is rewritten in Scheme and built by a Koivu compiler produced by the chain, lowered through Pino IR. The C source is then removed from the repository.

The rewrite is an accepted cost. It is mechanical provided the C seed is organised around the instruction set rather than around C idioms, and it buys a seed whose machine code corresponds to its source by construction.

### What auditability means here

Auditability is the ability of an independent reviewer to satisfy themselves that the seed does what its sources say. It has two separate objects, and they are not interchangeable:

* **Source auditability** - reading the seed's source and understanding what it computes.
* **Machine code auditability** - checking that the distributed binary actually corresponds to that source.

The distinction matters because the two pull in different directions. A source can be pleasant to read while its binary is produced by an optimizing translator that obscures the correspondence. A source can be awkward while every instruction maps to a fixed, checkable sequence of bytes.

**Machine code auditability outranks source auditability.** The seed is the artifact a user downloads and runs without rebuilding it. What they need is confidence in the bytes they execute, not in the elegance of the code that produced them.

### Size is a ceiling, not a target

Auditability outranks machine code size, and the relationship is not linear:

* Beyond some threshold a binary is simply not feasible to read, and auditability collapses however regular the code is.
* Below that threshold size barely matters. A binary ten times larger is *easier* to audit if its machine code is simpler, more regular and more obviously derived from the source.

The size budget in [Seed Artifacts](08_seed_artifacts.md), section 7 is therefore a ceiling to stay under, not a quantity to minimise. Its numeric value is an open item there.

### How the priorities shift

The priority order is not constant. It is staged, and the stages are defined by one event: **the seed becomes self-compilable**, meaning a Koivu compiler produced by the chain can build the seed from its own source.

* **Early development, before that event.** The seed is built by an external scaffold - today an LLVM C compiler. The priority is a simple implementation: small source, easy to write and easy to change. Seed auditability is explicitly *not* a goal, because optimising for it would slow the work and would be aimed at a design that is still moving. **No public seed release happens in this period**, which is what makes a scaffold acceptable: nothing is distributed while the scaffold is in the trust chain.
* **Late development, after that event.** The seed is a release artifact. Machine code auditability outranks both source size and source auditability. Where they conflict, the choice that leaves the distributed binary easier to verify wins.

A seed implementation that can never become self-compilable cannot leave early development, and therefore cannot satisfy the late-stage priority.

### Options considered and rejected

Recorded so that they are not re-derived later.

* **Writing the seed in Pino IR.** Rejected. Pino IR is a lowering target, not a programming language: a small fixed instruction set, an implicit operand stack, no structured control flow, no aggregates. Writing a compiler in it is assembly programming with S-expression syntax, and it would force the instruction set to grow into a real language before the seed could be written.
* **Writing the seed in `.ll` and keeping it there permanently.** Rejected. The binary would always be the output of an optimizing translator, so machine code auditability - the top priority in late development - would never be reached.
* **Writing the seed in `.ll` early and in Scheme later.** Rejected as dominated: the same end state as the C route, but a harder early scaffold. Emitting container headers and instruction templates in `.ll` is markedly more laborious than in C, and the existing `.ll` seed is an evaluator design that the stack-machine backend discards anyway.
* **Writing the seed in Scheme from the start, built by an external Scheme compiler.** Rejected. It avoids the rewrite, but it requires choosing, installing and tracking a Scheme system, keeping the seed's source inside the intersection of that system's dialect and Koivu's own, and carrying a large opaque toolchain through the early phase.

## 3. Two Bootstrapping Paths

From a security and trust point of view there are two major paths for bootstrapping:

* **Simple Path:** bootstrap from the assembly or the binary of the seed compiler on some consumer-grade operating system.
* **Secure Path:** bootstrap from the machine binary of the seed compiler in a secure bootstrapping environment, similar to the GNU Bootstrapping Project.

They are a trade-off, not competing claims. Each path is described below with what it does and does not give the user.

## 4. Simple Path

> Capt. Barbossa: I must admit, Jack, I thought I had you figured. But it turns out you're a hard man to predict.<br>
> Capt. Jack Sparrow: Me? I'm dishonest. And a dishonest man you can always trust to be dishonest. Honestly. It's the honest ones you want to watch out for, because you can never predict when they're going to do something incredibly... stupid.

Simple Path is a convenience for the majority of developers and users. Linux and macOS users translate the committed seed assembly into an executable with their platform assembler. Windows users receive a binary seed as part of the Koivu download, because a bare Windows OS has no assembler tool.

A small binary is still suitable for human inspection, at least in theory: it can be opened in a hex editor and compared against the assembly. More practical options exist as well: an antivirus scan, a digital signature check, an automated comparison of the binary against the source assembly, and so on. The smaller the binary, the easier the inspection. The available recipes are listed in [Seed Artifacts](08_seed_artifacts.md), section 6.

Simple Path is not truly secure or trustable. It is only as secure as the operating system on which the compiler infrastructure is built. A particular instance of a consumer-grade operating system may contain malicious code aimed at the compiler infrastructure: from random viruses to elaborate code engineered by the OS provider. Most people trust their OS provider and use antivirus software against viruses, so this path is good enough for the majority of users.

Two limits should be stated plainly:

* **What it proves.** That the seed behaves as its source says, to the extent the user actually inspects it.
* **What it does not prove.** That a distributed binary was produced from the published sources. This is a recorded non-goal; see [Seed Artifacts](08_seed_artifacts.md), section 5.

## 5. Secure Path

> Capt. Barbossa: "Boiled beef, mustard, a bit of caviar... and an apple, one of those."<br>
> Elizabeth: (Suspicious) "What is it, poisoned?"

Secure Path is for cases where full trust in the compiler chain is an absolute requirement. See Ken Thompson's 1984 ACM Turing Award lecture, "Reflections on Trusting Trust."

In that case the Koivu compiler infrastructure may serve as a drop-in replacement for the compiler seeding steps of the GNU Bootstrapping Project. Or a more elaborate simultaneous OS and compiler bootstrapping procedure may be designed. The details of such a procedure are beyond the scope of Koivu: Koivu covers the compiler bootstrapping part only.

Linux is expected to be the first platform where this path is exercised in practice, because it combines a large number of advanced users with the technical and organizational freedom to experiment with bootstrapping and trust (see [Platforms and Targets](01_platforms.md), section 2).

## 6. Build Steps

The chain has four steps. Each step names the compiler that runs, the intermediate artifact it produces, and the tool that lowers that artifact to machine code.

### Terminology: S-LLVM IR versus a `.ll` file

Two different things in this chain are both intermediate, and conflating them is the easiest mistake to make here.

* **S-LLVM IR** is an in-memory data structure: S-expressions held in the memory of a Koivu Lisp compiler, conforming to the `ast-s-llvm-ir-` schema. It exists only while a compiler is running.
* **A `.ll` file** is text: LLVM IR written in the format defined by the LLVM specifications. It is what the emitter produces from S-LLVM IR, and what `llc` or `koivu-llc` consume.

When a step below says that a compiler "emits IR", it means the compiler builds S-LLVM IR in memory. A `.ll` file appears only when the lowering path goes through text.

A third form is possible in principle. S-LLVM IR could be written out as Lisp source text - S-expressions saved to a file and read back by an ordinary Lisp reader, which every Koivu stage already has. That would be cheaper to parse than `.ll`. Koivu does not use it anywhere today: no artifact is stored or passed between stages in that form. It is recorded here only as an option, to be adopted if it ever simplifies something concrete.

### Step 1: Generating the Bridge Binary

* **Input:** Stage 2 bridge source code
* **Compiler running:** the Stage 1 seed
* **Intermediate:** in-memory S-LLVM IR built by the seed. It becomes the textual `koivu-bridge.ll` only when the lowering is an external `llc` (configuration E); under `simple-codegen` (configuration B) the AST is lowered to machine code directly and no `.ll` is written.
* **Lowering:** an external `llc` (interim, configuration E), or `simple-codegen` executed by the seed itself (long-term, configuration B)
* **Output:** `koivu-bridge` binary

```
+-----------------+      +--------------------+      +----------------------+      +------------------+
| Bridge Source   | ---> | Stage 1 Seed       | ---> | koivu-bridge.ll      | ---> | Bridge Binary    |
| (.scm)          |      | (builds S-LLVM IR) |      | (textual LLVM IR)    |      | (lowered+linked) |
+-----------------+      +--------------------+      +----------------------+      +------------------+
```

The diagram shows configuration E. Under configuration B the middle box does not exist: the seed lowers its in-memory S-LLVM IR straight to the executable.

The lowering column is the whole point of the milestone table in [Backend](backend.md), section 1: this is the step where the bootstrap goal - no external tools - is eventually reached.

### Step 2: Generating the Stage 3 Binary

* **Input:** Stage 3 source code
* **Compiler running:** the bridge binary
* **Intermediate:** in-memory S-LLVM IR built by the bridge, emitted as the textual `koivu-core.ll` for `llc` or `koivu-llc` to lower.
* **Lowering:** an external `llc` until M4, then `koivu-llc`
* **Output:** Stage 3 **Version A**

### Step 3: Native Rebuild

* **Input:** Stage 3 source code
* **Compiler running:** Stage 3 **Version A**, which contains the native lowering stack
* **Intermediate:** none - machine code is emitted directly
* **Lowering:** none
* **Output:** Stage 3 **Version B**

Version B emits machine code and was built by a compiler that emitted IR and was lowered by an external tool. That is the one-generation lag inherent to bootstrapping: a compiler can only use a lowerer it already contains.

### Step 4: The Fixpoint Check

* **Input:** Stage 3 source code
* **Compiler running:** Stage 3 **Version B**
* **Output:** Stage 3 **Version C**

If Version B and Version C are **byte-for-byte identical**, the compiler has reached a fixpoint and full, stable self-hosting is demonstrated.

Three conditions make this check meaningful:

1. **Compare B with C, not A with B.** Version A emits IR and was lowered externally; Version B emits machine code. Comparing them would measure the toolchain difference, not self-consistency.
2. **Use the same backend configuration for both builds.** A different target backend on either side invalidates the comparison.
3. **Require deterministic emission.** No timestamps, no absolute paths, stable ordering, stable symbol-table iteration. Determinism is an acceptance criterion in [Backend](backend.md), section 8.

The same cycle is drawn as T-diagrams in [Roadmap to Self-hosting](selfhosting.md).

## 7. Why This Ordering Is Mandatory

1. **Language compatibility.** Stage 3 source uses features that Stage 1 does not understand, hygienic macros first of all. Feeding Stage 3 directly to the seed will crash it or fail to parse.
2. **The bridge principle.** The bridge is written in a subset simple enough for the seed to compile, but its output is a compiler capable of handling the full Stage 3 language. It is the narrow waist of the whole chain.

## 8. What the Chain Proves, and What It Does Not

| Claim | Proved by |
| :--- | :--- |
| The seed does what its sources say | reading the seed source, then checking the distributed binary against it |
| Stage 3 reproduces itself | the B == C fixpoint |
| The compiler is free of deliberately planted backdoors | **nothing in this chain** |

The last row matters. A fixpoint check proves reproducibility and self-consistency; it does not prove trustworthiness. Thompson's point is precisely that a Trojan can be reproduced perfectly by a self-hosting compiler. That is why the Secure Path exists as a separate path, and why it is not a stronger version of the Simple Path but a different procedure with different assumptions.
