# Architectural Rationale: The Koivu Compiler Infrastructure

> **Status:** Project Vision Blueprint  

---

## 1. Project Statement and Objectives

The Koivu Project intends to develop a compact, portable compiler infrastructure. The design path serves a dual objective:

1. **Toolchain Expressiveness:** To provide a small, maintainable, and syntactically elegant toolchain optimized for compiler engineering and optimization passes.
2. **Minimalist Bootstrapping:** To establish a verifiably clear path to full self-hosting, initiated from a tiny, human-inspectable machine assembly or binary seed.

---

## 2. Functional Targets and LLVM Alignment

Koivu builds directly upon the established conventions of LLVM, maintaining fundamental compatibility with LLVM Intermediate Representation (IR). 

The operational scale of the project is bounded by two distinct delivery thresholds:

### 2.1 Minimum Capability Threshold
* **Target:** A fully compliant, functional C compiler on major operating systems (Windows, Linux, macOS). No dependancy on legacy tools like old C compilers, MSYS2, Visual Studio etc.
* **Scope:** Generation of stable native machine code from standard C sources, completely integrated into the self-hosting loop.

### 2.2 Extended Development Objective
* **Target:** Drop-in compatibility with the modern systems ecosystem.
* **Scope:** Implementation of all core LLVM IR tools (including low-level machine architecture lowering), a Clang-compatible frontend, and native frontends for **C++, Swift, Hylo, Rust, and Jai**. 
* **Compatibility:** The final binaries are engineered to respond identically to Clang command-line interfaces, diagnostic flags, and static formats.

---

## 3. Bootstrapping Analysis: Engineering Trade-offs

The core motivations of the Koivu bootstrap pipeline align entirely with the GNU Bootstrapping Project: ensuring system reproducibility, trust, and resilience against upstream binary compromises (Thompson's "Trusting Trust" attack vectors). Additionally, providing an engine that boots from a uniform, tiny seed across multiple target operating systems significantly reduces development friction on individual workspaces.

While the GNU Bootstrapping Project has successfully proven the viability of secure builds, its practical deployment reveals specific engineering constraints that Koivu attempts to address:

* **Maintenance Overhead on Diverse Hardware:** Porting and maintaining custom bootstrap layers across less common or emerging CPU architectures remains operationally complex.
* **Tooling Fragmentation:** The existing path relies on a varied sequence of platform-specific assembly templates, antique C compilers, and specialized interpreters. This heterogeneity increases the surface area that a single engineer must master.

Koivu seeks to provide an alternative path by utilizing a single, uniform language abstraction layer from Stage 1 through production, ensuring the compilation path remains compact and cross-platform.

---

## 4. Rationale for Selection of the Lisp Dialect

Lisp is selected as the primary language layer for all stages of the Koivu infrastructure. It represents the most pragmatic choice to fulfill both project goals within a singular language framework.

### 4.1 High-Level Expressiveness
Compilers are fundamentally string-to-tree and tree-to-array translation systems. Lisp excels at this domain. Historical implementations, most notably **Chez Scheme**, have demonstrated that a native code generator built on a disciplined sequence of small, isolated passes (the "nanopass" design) can achieve excellent compilation throughput. Originally specified in 1958, Lisp remains the second-oldest high-level language still in active use, drawing on decades of optimization literature.

### 4.2 Low-Level Simplicity
At the foundational level, the mechanics of a basic Lisp evaluator are remarkably straightforward. A functional interpreter seed can be written in a few hundred lines of clear, target-independent assembly or LLVM IR, allowing complete human verification of the initial execution state.

### 4.3 Mitigation of Performance Overhead
Traditional criticisms regarding Lisp's performance—specifically garbage collection latency and variable execution speed—are structural problems of general-purpose, interactive system profiles. Because Koivu is an **ahead-of-time (AOT) batch compiler**, these issues are mitigated by architectural isolation:
1. **Pass-Isolated Arenas:** Generic runtime garbage collection is omitted. Memory is managed via localized blocks that are reset to zero instantly between compiler passes.
2. **Data-Driven Architecture:** Code representations are stored in flat, cash-aligned arrays rather than deep pointer graphs, maximizing raw execution velocity directly on modern hardware.

