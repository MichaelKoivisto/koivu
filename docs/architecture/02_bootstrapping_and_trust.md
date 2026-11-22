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

Bootstrapping starts from a simple Lisp compiler written in pure, generic LLVM IR.

Koivu also keeps, as part of its source code, target-dependent machine assembly files for the supported hosts. Those assembly files are obtained by translating the generic IR implementation of the seed: with LLVM's `llc` at the early stages, and with the Koivu tool `koivu-llc` once it exists (see [Backend](backend.md), section 6.5).

The purpose of keeping the seed in portable generic IR is to simplify maintenance of the project: one implementation, translated per target. The target-specific assembly seeds keep one important property in common with the generic IR seed: they are all human-readable and human-inspectable, because they are small. That property is the reason the size budget in [Seed Artifacts](08_seed_artifacts.md), section 7 exists.

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

### Step 1: Generating the Bridge Binary

* **Input:** Stage 2 bridge source code
* **Compiler running:** the Stage 1 seed
* **Intermediate:** `koivu-bridge.ll` - S-LLVM IR emitted by the seed
* **Lowering:** an external `llc` (interim, configuration E), or `simple-codegen` executed by the seed itself (long-term, configuration B)
* **Output:** `koivu-bridge` binary

```
+-----------------+      +--------------------+      +----------------------+      +------------------+
| Bridge Source   | ---> | Stage 1 Seed       | ---> | koivu-bridge.ll      | ---> | Bridge Binary    |
| (.scm)          |      | (emits S-LLVM IR)  |      | (intermediate)       |      | (lowered+linked) |
+-----------------+      +--------------------+      +----------------------+      +------------------+
```

The lowering column is the whole point of the milestone table in [Backend](backend.md), section 1: this is the step where the bootstrap goal - no external tools - is eventually reached.

### Step 2: Generating the Stage 3 Binary

* **Input:** Stage 3 source code
* **Compiler running:** the bridge binary
* **Intermediate:** `koivu-core.ll` - S-LLVM IR emitted by the bridge
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
| The seed does what its sources say | reading the `.ll`; inspecting the `.s` or the binary |
| Stage 3 reproduces itself | the B == C fixpoint |
| The compiler is free of deliberately planted backdoors | **nothing in this chain** |

The last row matters. A fixpoint check proves reproducibility and self-consistency; it does not prove trustworthiness. Thompson's point is precisely that a Trojan can be reproduced perfectly by a self-hosting compiler. That is why the Secure Path exists as a separate path, and why it is not a stronger version of the Simple Path but a different procedure with different assumptions.
