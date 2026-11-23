# Would a Pino Interpreter Make the Seed Smaller?

**Status:** Developer Notes  

**Component:** Global  

[Seed Sizes](notes_on_seed_sizes.md), section 4 records a tiny Pino interpreter as a considered-and-rejected alternative to the current design. That one-line rejection is not enough: the idea keeps returning because it sounds obviously right - an interpreter is a small program, so a seed containing one should be small. This note works out where the size would actually come from, what it would cost, and whether the auditability claim survives contact with the details.

Confidence markers as in the seed sizes note: **[estimate]** derived here, **[unverified]** to be measured.

## 1. Three Different Proposals

"A Pino interpreter" means at least three different things, and only two of them change anything.

| Variant | What it is | Bootstrap impact |
| :--- | :--- | :--- |
| **V1 - interpreter in the seed** | the seed builds the sapling's Pino IR and *interprets* it instead of lowering it; the Pino compiler library is removed | large: changes what the seed is |
| **V2 - seed shipped as an image** | the seed's own logic lives as a Pino image; the distributed seed is a small interpreter plus that image | large: adds a rung and a format |
| **V3 - interpreter in `koivu-pino`** | a development mode that runs a Pino program directly | none: `koivu-pino` is outside the chain |

V3 is worth separating because it is cheap and separable: it touches no bootstrap artifact, and it would make Pino semantics testable without generating code. It is not what the size argument is about, and nothing below applies to it.

## 2. Where the Size Would Come From - and Where It Would Not

The intuition "interpreter instead of compiler, therefore smaller" fails on the seed itself. Decompose what is actually in the seed binary:

| Component | In the compiler seed | In the interpreter seed |
| :--- | :--- | :--- |
| reader, interner, arena, front end | present, **the bulk of the code** | unchanged, **still the bulk** |
| instruction encoder - one template per Pino instruction per target | present | **removed** |
| label table and backpatch resolver | present | **removed** |
| container writer, per format | present | still present - the executable is still a container |
| OS glue, seven primitives | present | unchanged |
| interpreter loop and Pino semantics | absent | **added** |

The encoder and the fixup resolver are small: 27 instructions across a handful of targets, each a short byte template, is a few KiB of machine code at most **[estimate]**. The interpreter that replaces them is a dispatch loop over the same 27 opcodes with stack, environment and arena state - also small, but *not smaller*: the two are the same order of magnitude, and the interpreter has to be correct in a harder way (section 5).

**So the seed does not get smaller by any interesting factor.** The front end, which is where the seed's code actually lives, is untouched. Replacing the last few KiB of encoder with a few KiB of interpreter is close to a wash.

What *does* change is the artifact the seed produces:

| | Current design | Interpreter design |
| :--- | :--- | :--- |
| the sapling executable contains | machine code of the sapling | interpreter + the sapling as Pino data |
| representation of the program | target machine code, 3-10 bytes per Pino instruction | Pino encoding, roughly 1-5 bytes per instruction |
| target independence | none - one binary per target | one image runs on every target |

The program's bulk is still present; it is just carried in a denser and more regular encoding. A realistic compression against machine code is a factor of **2-3** **[estimate]**, not an order of magnitude: Pino instructions still need opcodes and operands, and the image still contains the whole compiler.

**The honest summary of the size question.** An interpreter shrinks the artifact by 2-3× and does not meaningfully shrink the seed. It shrinks something else far more dramatically: the part of the artifact that has to be *read as machine code* falls from ~1.5 MiB to the size of the interpreter loop, on the order of 10 KiB **[estimate]**. That is a real and large change - but it is a change in *what kind of thing must be read*, not in total bytes.

## 3. Does It Actually Improve Auditability?

"Auditable" is not one property. Two are in play, and they pull in different directions.

* **Reading auditability** - can a person follow the artifact and satisfy themselves about its behaviour?
* **Mapping auditability** - can a tool, or a careful person, establish that artifact X is the exact consequence of source Y?

| | Current design (compiler) | Interpreter design |
| :--- | :--- | :--- |
| reading auditability | poor for 1.5 MiB of generated machine code | **good**: ~10 KiB of interpreter plus an image that is symbolic and diffable |
| mapping auditability | **mechanical**: one fixed byte template per Pino instruction, checkable by a tool ([Backend](backend.md), section 8, criterion 7) | semantic: "this interpreter implements the 27 Pino instructions correctly", argued by reading the interpreter |
| where the trust sits | in a *mapping* that can be verified | in an *implementation* that must be understood |
| blast radius of a bug | one instruction is mis-encoded | the whole language is wrong |

So the answer to "does it improve auditability, or does it just move the bulk" is: **it does both, and the movement is not neutral.**

It moves the bulk from machine code into Pino IR - that part of the suspicion is correct. But the bulk changes kind. Machine code is per-target, encoded and unstructured; Pino IR is symbolic, labelled, target-independent and carries declared stack effects. Moving a program from the first to the second genuinely makes it more reviewable, and it makes *deltas* reviewable, which machine code never is: two images can be diffed, two binaries cannot.

What it does not do is remove the need to trust machine code. It concentrates that need into a small program instead of spreading it over a large one. Whether that is a gain depends on which auditability the project is optimising, and Koivu has already answered that: machine-code auditability outranks source auditability ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2), and the current design delivers it as a mechanical mapping. The interpreter delivers a *smaller* machine-code surface but replaces the mechanical mapping with a semantic argument.

## 4. Is Pino IR Easier to Audit Than Machine Code?

For a human reader, yes, decisively: it is symbolic, its stack effects are declared per instruction, its labels are named, and it does not vary by target. A reviewer who can read Scheme can read Pino IR after ten minutes.

For a machine or a tool, the comparison inverts. Machine code has an *external* ground truth: the ISA manual, enforced by the hardware. Pino IR has an *internal* ground truth: our own documents plus whichever implementation is running. The first is a specification the project did not write and cannot weaken; the second is a specification the project maintains and can get wrong.

That asymmetry is the whole argument, and it is why "Pino IR is easier to audit" should never be stated without the qualifier. It is easier to *read*. It is not easier to *be certain about*, because certainty about machine code is anchored outside the project and certainty about Pino IR is anchored inside it.

There is a second, sharper asymmetry. A mistake in a lowering template is local: one instruction, one target, one program. A mistake in an interpreter is global: every program on every target, and it manifests as a wrong result rather than as an obviously malformed binary. Concentration buys reviewability and loses locality.

## 5. What It Would Cost

1. **Speed.** Interpretation is typically 5-20× slower than generated code **[unverified]**. The bootstrap compiles the sapling, then Stage 3, then Stage 3 again; the penalty lands on every one of those steps, and it grows with the compiler.
2. **A second implementation of Pino semantics.** The blueprints reject a permanent mirror on principle ([Backend](backend.md), section 3; decision 4): two implementations of the same thing is where divergence hides. An interpreter is exactly that - the same 27 instructions, defined once as byte templates and once as interpreter cases - and unlike the C-to-Scheme transition it never ends.
3. **Pino IR becomes a distribution format.** Today `.pino` is a debug dump precisely so that it never has to be stable ([Pino IR](pino.md), section 1): no stage reads it, no version is negotiated, no compatibility promise exists. Ship images and all three change at once - a specified encoding, a format version and a compatibility policy, in the same project that removed the R6RS library system partly to avoid exactly that kind of commitment.
4. **A runtime comes back.** [Stage 1 (Seed)](04_stage1_seed.md), section 5 states that a compiled Koivu program is self-contained code plus its container, and that nothing is called at run time except the seven host primitives. An interpreter design puts a runtime into every produced executable. That is not fatal, but it retires a property the blueprints currently rely on.
5. **The interpreter binary has to come from somewhere.** If Koivu produces it, a compiler seed is still needed and the interpreter is an addition rather than a replacement. If it is hand-written in machine code per host, that is a new bottom rung - the ladder already rejected in [Seed Sizes](notes_on_seed_sizes.md), section 4.

## 6. Where It Would Genuinely Win

* **Many targets.** One image, one interpreter per host: cross-compilation collapses to building an interpreter. With three hosts this is worth little; with fifteen it would be decisive.
* **A stronger fixpoint check.** Comparing images is comparing target-independent artifacts, so an image-level fixpoint implies a binary-level fixpoint on every target at once, instead of one comparison per target.
* **A smaller machine-code surface.** If the measured seed ever overshoots the ceiling by a wide margin, concentrating the trusted machine code into a few KiB of interpreter is the right lever - and it is the only lever that reduces *what a person must read at the instruction level* rather than what the build must carry.

## 7. Recommendation

Not adopted. The seed does not shrink, the produced artifact shrinks by roughly 2-3× **[estimate]**, and the price is a permanent second implementation of Pino semantics, a versioned distribution format, a runtime in every executable, and a 5-20× slowdown on every bootstrap step. Against that, the gain is a smaller machine-code surface - real, but not the property the current design optimises for.

Revisit if any of these becomes true:

* the measured seed exceeds the ceiling in [Seed Artifacts](08_seed_artifacts.md), section 7 by a factor of two or more;
* the supported target set grows past a handful, so that per-target templates stop being cheap;
* a requirement appears to ship one artifact that runs on several hosts.

V3 - an interpreter mode inside `koivu-pino` - is not covered by this recommendation. It is outside the chain, it adds no artifact to the trusted set, and it would make Pino semantics testable independently of any lowering. It is simply a separate, smaller decision.
