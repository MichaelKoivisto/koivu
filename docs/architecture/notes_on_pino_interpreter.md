# Would a Pino Interpreter Beat the Lowerer?

**Status:** Developer Notes  

**Component:** Global  

[Seed Sizes](notes_on_seed_sizes.md), section 4 records a tiny Pino interpreter as a considered-and-rejected alternative, and [Koivu Vesi](koivu-vesi.md), section 1 rejects it again in one line. That one-line rejection is not enough: the idea keeps returning because it sounds obviously right - an interpreter is a small program, so the program that turns an image into something runnable should be small too. This note works out where the size would actually come from, what it would cost, and whether the auditability claim survives contact with the details.

It is written against the chain as it stands after the front-end / Vesi split. The seed writes an image and stops; `koivu-vesi` turns that image into an executable. So the question is not what happens to the seed - every variant below leaves it untouched - but what happens inside Vesi and inside the artifact Vesi produces.

Confidence markers as in the seed sizes note: **[estimate]** derived here, **[unverified]** to be measured.

## 1. Three Different Proposals

"A Pino interpreter" means at least three different things, and only two of them change the chain.

| Variant | What it is | Bootstrap impact |
| :--- | :--- | :--- |
| **V1 - Vesi interprets** | `koivu-vesi` reads an image and runs it instead of encoding it: no instruction encoder, no label table, no container writers | large: every produced program needs Vesi at run time |
| **V2 - interpreter plus image** | the produced artifact bundles a copy of the interpreter with the image, so the program stays self-contained | large: the artifact changes shape, and one container writer survives |
| **V3 - interpreter as a development mode** | a mode that runs an image directly, outside the chain, for testing Pino semantics | none: no chain artifact is touched |

The split has already delivered half of V2 without anyone calling it that: the seed is distributed as one target-independent image, and the user turns it into a seed themselves ([Seed Artifacts](08_seed_artifacts.md), section 1). What V2 adds is that the image would be *executed* rather than lowered - the payload of a produced program becomes its image instead of its machine code.

V3 is worth separating because it is cheap and separable: it touches no bootstrap artifact, and it would make Pino semantics testable without generating code. It is not what the size argument is about, and nothing below applies to it.

## 2. Where the Size Would Come From - and Where It Would Not

The intuition "interpreter instead of compiler, therefore smaller" has to be applied to the right program. The seed is not in the picture: it emits an image and stops, and every variant here leaves it exactly as it is. What changes is Vesi.

| Component | Vesi today | Vesi as an interpreter |
| :--- | :--- | :--- |
| `.pino` reader and stack-balance verifier | present | present - the image still has to be read and checked |
| instruction encoder - one template per instruction per target | present, **the bulk of the target work** | **removed** |
| label table and backpatch resolver | present | **removed** |
| container writer, one per format | present, three formats | **removed in V1**, one survives in V2 |
| OS glue, seven primitives | present | present, plus whatever running a program needs |
| interpreter loop and Pino semantics | absent | **added** |

So Vesi does get smaller, and this time the intuition is right in direction: the encoder, the label table and the container writers exist only because the output is machine code. What replaces them is a dispatch loop over the same instruction set.

It is not a large win. The encoder and the fixup resolver are small - one short byte template per instruction, per target **[estimate]** - and the interpreter that replaces them is a loop over the same opcodes with stack, environment and arena state, also small, and *not smaller*: the two are the same order of magnitude, and the interpreter has to be correct in a harder way (section 5).

The container writers are the part worth counting. ELF64, PE32+ and Mach-O are three separate encoders of executable structure, and V1 deletes all three. That is the one place where an interpreter design saves something substantial.

What V1 and V2 change most is not Vesi but the artifact:

| | Lowerer | V1 - Vesi interprets | V2 - interpreter plus image |
| :--- | :--- | :--- | :--- |
| what a produced program contains | machine code of the program | nothing - the program is run by Vesi | interpreter plus the image |
| representation of the program | target machine code, 3-10 bytes per Pino instruction | image only | Pino encoding, roughly 1-5 bytes per instruction |
| self-contained | yes | **no** - it needs Vesi | yes |
| target independence | none - one executable per target | one image runs wherever Vesi runs | one image runs wherever the bundled interpreter runs |

A realistic compression of the payload against machine code is a factor of **2-3** **[estimate]**, not an order of magnitude: Pino instructions still need opcodes and operands, and the image still contains the whole compiler.

**The honest summary of the size question.** An interpreter shrinks Vesi by the encoder and the container writers, and shrinks a produced program's payload by 2-3× **[estimate]**. It shrinks something else far more dramatically: the part of a produced program that has to be *read as machine code* falls from ~1.5 MiB for Stage 3 to the size of the interpreter loop, on the order of 10 KiB **[estimate]**. That is a real and large change - but it is a change in *what kind of thing must be read*, not in total bytes.

## 3. Does It Actually Improve Auditability?

"Auditable" is not one property. Two are in play, and they pull in different directions.

* **Reading auditability** - can a person follow the artifact and satisfy themselves about its behaviour?
* **Mapping auditability** - can a tool, or a careful person, establish that artifact X is the exact consequence of source Y?

| | Lowerer | Interpreter |
| :--- | :--- | :--- |
| reading auditability | poor for 1.5 MiB of generated machine code | **good**: ~10 KiB of interpreter plus an image that is symbolic and diffable |
| mapping auditability | **mechanical**: one fixed byte template per Pino instruction, checkable by a tool ([Backend](backend.md), section 8, criterion 7) | semantic: "this interpreter implements the Pino instructions correctly", argued by reading the interpreter |
| where the trust sits | in a *mapping* that can be verified | in an *implementation* that must be understood |
| blast radius of a bug | one instruction is mis-encoded | the whole language is wrong |

The split has already moved part of this in the interpreter's direction, and it is worth noticing. The image is text, so a reviewer can read what the front end produced without looking at machine code at all ([Koivu Vesi](koivu-vesi.md), section 2). What the interpreter would add is the second half: no machine code anywhere in a produced program.

So the answer to "does it improve auditability, or does it just move the bulk" is: **it does both, and the movement is not neutral.**

It moves the bulk from machine code into Pino IR - that part of the suspicion is correct. But the bulk changes kind. Machine code is per-target, encoded and unstructured; Pino IR is symbolic, labelled, target-independent and carries declared stack effects. Moving a program from the first to the second genuinely makes it more reviewable, and it makes *deltas* reviewable, which machine code never is: two images can be diffed, two binaries cannot.

What it does not do is remove the need to trust machine code. It concentrates that need into a small program instead of spreading it over a large one. Whether that is a gain depends on which auditability the project is optimising, and Koivu has already answered that: machine-code auditability outranks source auditability ([Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md), section 2), and the lowerer delivers it as a mechanical mapping. The interpreter delivers a *smaller* machine-code surface but replaces the mechanical mapping with a semantic argument.

## 4. Is Pino IR Easier to Audit Than Machine Code?

For a human reader, yes, decisively: it is symbolic, its stack effects are declared per instruction, its labels are named, and it does not vary by target. A reviewer who can read Scheme can read Pino IR after ten minutes.

For a machine or a tool, the comparison inverts. Machine code has an *external* ground truth: the ISA manual, enforced by the hardware. Pino IR has an *internal* ground truth: our own documents plus whichever implementation is running. The first is a specification the project did not write and cannot weaken; the second is a specification the project maintains and can get wrong.

That asymmetry is the whole argument, and it is why "Pino IR is easier to audit" should never be stated without the qualifier. It is easier to *read*. It is not easier to *be certain about*, because certainty about machine code is anchored outside the project and certainty about Pino IR is anchored inside it.

There is a second, sharper asymmetry. A mistake in a lowering template is local: one instruction, one target, one program. A mistake in an interpreter is global: every program on every target, and it manifests as a wrong result rather than as an obviously malformed binary. Concentration buys reviewability and loses locality.

## 5. What It Would Cost

1. **Speed.** Interpretation is typically 5-20× slower than generated code **[unverified]**. The bootstrap compiles the sapling, then Stage 3, then Stage 3 again; the penalty lands on every one of those steps, and it grows with the compiler.
2. **A second implementation of Pino semantics.** The blueprints reject a permanent mirror on principle ([Backend](backend.md), section 3; decision 4): two implementations of the same thing is where divergence hides. An interpreter is exactly that - the same instructions, defined once as byte templates in Vesi and once as interpreter cases - and unlike the C-to-Scheme transition it never ends.
3. **The image stops being a compile-time artifact.** The cost this note originally charged here has already been paid: `.pino` is now a specified, canonically printed and versioned interface that Vesi reads ([Koivu Vesi](koivu-vesi.md), section 2). What an interpreter would add is different, and larger. The image would become what a *program* is made of, so its encoding would have to stay stable for as long as any produced program exists. A compile-time interface can be revised together with the tool that reads it; a distribution format cannot.
4. **A runtime comes back.** [Stage 1 (Seed)](04_stage1_seed.md), section 5 states that a compiled Koivu program is self-contained code plus its container, and that nothing is called at run time except the seven host primitives. V1 puts a runtime *outside* every produced program - it needs Vesi to run at all - and V2 puts a copy of the interpreter *inside* every produced program. Neither is fatal, but both retire a property the blueprints currently rely on.
5. **The interpreter binary has to come from somewhere.** Today that binary is Vesi, so the question becomes whether an interpreter is easier to build from nothing than a lowerer. Slightly, yes: one dispatch loop instead of an encoder, a label table and three container writers. That is the honest point in the interpreter's favour, and it is smaller than it sounds, because the reader, the verifier and the arena are needed either way.

## 6. Where It Would Genuinely Win

* **Many targets.** One image, one interpreter per host: cross-compilation collapses to building an interpreter. With three hosts this is worth little; with fifteen it would be decisive.
* **A stronger fixpoint check.** Comparing images is comparing target-independent artifacts, so an image-level fixpoint implies a binary-level fixpoint on every target at once, instead of one comparison per target.
* **A smaller machine-code surface.** This is the largest of the three, and it connects to a decision recorded elsewhere: [Auditability](auditability.md), section 1 states that Koivu does not follow the byte-audit tradition, because its trusted binary is a ~600 KiB Vesi. An interpreter would concentrate a produced program's machine code into a ~10 KiB loop. That is the closest this design family comes to the property Koivu has decided not to have, and it is the reason to keep this note rather than forget the question.

## 7. Recommendation

Not adopted. In the terms the chain now uses: Vesi would shrink by its encoder, its label table and its three container writers, and a produced program's machine-code surface would fall to ~10 KiB **[estimate]**. Against that, the mechanical mapping becomes a semantic argument, every produced program either needs Vesi at run time or carries a copy of it, and the image becomes a distribution format rather than a compile-time interface.

Revisit if any of these becomes true:

* the measured Vesi exceeds the ceiling in [Seed Artifacts](08_seed_artifacts.md), section 7 by a factor of two or more;
* the supported target set grows past a handful, so that per-target templates stop being cheap;
* a requirement appears to ship one artifact that runs on several hosts;
* the auditability balance shifts - if the project ever decides that a small machine-code surface matters more than a mechanical mapping, which is the trade [Auditability](auditability.md) records as *not* taken, this is the design that delivers it.

V3 - an interpreter mode kept outside the chain - is not covered by this recommendation. It adds no artifact to the trusted set, and it would make Pino semantics testable independently of any lowering. It is simply a separate, smaller decision.
