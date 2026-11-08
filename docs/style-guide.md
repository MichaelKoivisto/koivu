# Koivu Documentation Style Guide

> **Status:** System Style Mandate  
> **Target:** All `.md` files in `docs/` and root  

This document defines the structural, typographic, and stylistic rules for the Koivu project documentation. To maintain consistency with classic systems engineering design documents, our text must prioritize precision, brevity, and explicit data layout.

---

## 1. Tone and Voice

> Elizabeth: "Captain Barbossa, I am here to negotiate the cessation of hostilities against Port Royal!"<br>
> Capt. Barbossa: "There are a lot of long words in there, miss; we're naught but humble pirates. What is it that you want?"<br>
> Elizabeth: "I want you to leave and never come back!"<br>
> Capt. Barbossa: "I'm disinclined to acquiesce to your request... Means 'no'."

* **Be Direct and Analytical:** Write in the active voice using short, punchy sentences. Avoid passive, winding prose.
* **Document Complexity:** Record critical design decisions and technical rationale.
* **The "Hacker-Classic" Aesthetic:** Maintain the sober, authoritative tone of early computing manifestos (e.g., early GNU, Linux, and Emacs design specifications). 
* **Reject Hyperbole:** Koivu is an internal research infrastructure asset. Do not use marketing jargon or promotional language. Describe the systems as they exist or as they are mathematically planned.
* Pirate jokes are welcome as epigraphs in internal documentation as long as you quote them with a `>`.

---

## 2. Document Metadata Banner

Documents inside the `docs/` repository may begin with a uniform header block summarizing context and operational scope:

```markdown
# Document Title

> **Status:** [Architecture Blueprint / Specification / Developer Notes]  
> **Component:** [Stage 1 Core / Midend / Global / etc.]  
```

* *Architecture Blueprint* is a plan that outlines the most important design aspects of particular component. 

* *Specification* is a formal document that should cover all the details of its topic.

* *Developer Notes* are temporary documents and can have unstructured information that is useful in the process of development. 


---

## 3. Markdown Mechanics & Formatting Constraints

### A. Code Blocks and Syntax Highlighting
Always declare the explicit language identifier for code fences to ensure correct syntax rendering.

* Use ````llvm```` for Stage 1 `primitives.ll` files.
* Use ````lisp```` for Stage 2/3 Scheme-family code.
* Use ````assembly```` for raw machine target snippets.

### B. Structural Data Presentation
When comparing architectural layers, memory structures, or file sizes, **always use tables** rather than dense paragraphs. Tables allow for rapid visual scanning during technical reviews.

### C. Alerts and Safety Blocks
Utilize GitHub’s blockquote markdown components to emphasize critical compilation risks or architectural constraints:

```markdown
> [!WARNING]
> **Memory Allocation Capping:** Stage 1 does not utilize a garbage collector. Runaway recursion loops will cause unmitigated memory exhaustion.
```

---

## 4. Vocabulary and Architectural Terms

To prevent semantic confusion, documentation must adhere to strict term boundaries:

* **S-Expression:** Refers strictly to the symbolic nested lists processed by the interpreter and macros. Do not use generic "code trees."
* **Pass-Based Arena:** Refers strictly to memory buffers that undergo a complete pointer reset to zero at the termination of a compilation pass. Do not call this a "heap partition."
* **Lowering:** The explicit act of translating higher-level Intermediate Representation (IR) symbols down into raw target-specific hardware instructions.
* **x86_64:** The 64-bit extension of the 32-bit x86 instruction set architecture. (Also known as amd64 and x64.) Please avoid using amd64 as it is too easy to misread, 
especially seeing arm64 and amd64 in the same document.


Mandatory Helping Verbs:
* Use **“must”** to express a mandatory requirement.
* Use **“will”** to express a future requirement.
* Use **“may”** or **“can”** to express optional action or capability.
