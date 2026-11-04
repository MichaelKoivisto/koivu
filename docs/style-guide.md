# Koivu Documentation Style Guide

> **Status:** System Style Mandate  
> **Target:** All `.md` files in `docs/` and root  

This document defines the structural, typographic, and stylistic rules for the Koivu project documentation. To maintain consistency with classic systems engineering design documents, our text must prioritize precision, brevity, and explicit data layout.

---

## 1. Tone and Voice

* **Be Direct and Analytical:** Write in the active voice using short, punchy sentences. Avoid passive, winding prose.
* **Reject Hyperbole:** Koivu is an internal research infrastructure asset. Do not use marketing jargon or promotional language. Describe the systems as they exist or as they are mathematically planned.
* **The "Hacker-Classic" Aesthetic:** Maintain the sober, authoritative tone of early computing manifestos (e.g., early GNU, Linux, and Emacs design specifications). 

---

## 2. Document Metadata Banner

Every document inside the `docs/` repository must begin with a uniform header block summarizing its context and operational scope:

```markdown
# Document Title

> **Status:** [Research Track / Architecture Specification / Draft]  
> **Component:** [Stage 1 Core / Midend / Global]  
```

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
