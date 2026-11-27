# Review Progress - Working Notes

Temporary document. It records where the architecture review stands so that work
can be resumed in a later session without re-deriving context.

**Delete this file when the review is finished.** It is deliberately absent from
the index in `docs/architecture.md`.

Last updated after commit `7059f59`.

This file is a ledger, not a copy of the blueprints. Where a decision is written
down in a blueprint, the entry points at it. The previous revision restated
decisions here, the restatements drifted, and they ended up describing an
architecture that no longer exists - a whole section of it listed
`simple-codegen` and S-LLVM IR decisions that the front-end / Vesi split
replaced. What belongs here is *where the review stands*; what the architecture
is belongs in the blueprints.

---

## 1. Working agreement

Decisions about *how* the review is conducted, not about the architecture.

- **Language.** Discussion and documents are in English.
- **One document at a time.** Read the whole document and produce an
  inconsistency list *before* editing anything.
- **Nothing is committed without an explicit instruction.**
- **One commit per file** when the changes are local to that file. When a single
  decision spans several files, use **one commit across all of them** - splitting
  it would leave the documents contradicting each other between commits.
- **Do not rename files or sections without asking.**
- **Do not silently fix a defect that needs a decision.** Raise it instead.
- **Do not plan technical implementation before a repository exists.**
- **Conventional Commits.** `docs:`, `fix:`, `chore:`, `feat:`, with an optional
  scope such as `docs(vesi):`.
- **No `Co-Authored-By` trailer.** Commits are authored by the user alone. Five
  older commits carry a `Co-Authored-By: Claude Code` trailer; they were
  deliberately left uncorrected, because correcting them would rewrite history.
- **No history rewriting.** `main` is protected against force push and deletion
  (section 8).

## 2. Project preferences the documents must reflect

- **Machine code auditability outranks source auditability** ([Bootstrapping
  Paths & Trust](02_bootstrapping_and_trust.md), section 2). The seed is the
  artifact a user runs without rebuilding it.
- **Auditability outranks size.**
- **Size is a ceiling, not a target.** A larger binary with simpler, more regular
  code can be the better choice. The older rule *"small seed size is the top
  priority"* is superseded and must not reappear.
- **Simplest solution wins** for platform decisions.
- **Documents record *why*, including the rejected options.**

## 3. Where the review stands

### Reconciled with the front-end / Vesi split

| Document | What the review changed |
| :--- | :--- |
| [Koivu Vesi](koivu-vesi.md) | New. The blueprint for the lowerer: why lowering is a separate program, `.pino` as an interface, responsibilities, two fixpoints, decisions. |
| [Backend](backend.md) | The Pino compiler is a program, not a library. Vesi named in the container, target-description and acceptance-criteria sections; criterion 9 requires the C and Scheme lowerers to agree byte for byte. |
| [Pino IR](pino.md) | `.pino` is an interface, not a debug dump. The first function is `entry`; entry fields are constants; the M1 milestone no longer claims `flat-vector`. |
| [Platforms and Targets](01_platforms.md) | Host rows list published artifacts. Goal B is teaching Vesi a target. The container writer belongs to Vesi. |
| [Bootstrapping Paths & Trust](02_bootstrapping_and_trust.md) | Vesi is the only distributed binary. Three kinds of intermediate. Steps 1 and 2 gain a Vesi sub-step. |
| [Stage 1 (Seed)](04_stage1_seed.md) | The seed emits `<name>.pino` and writes no container. No `-o` and no `--emit-pino`. Two passes over one manifest. `bootstrap/pino/` is Vesi's source set. Two languages until M2. Tests use a committed golden image. |
| [Stage 2 (Sapling)](05_stage2_sapling.md) | Rewritten: one source set, two programs; the sapling emits an image; two expansion passes. |
| [Stage 3 (Production Core)](06_stage3_production_core.md) | Stage 3 is a traditional Lisp compiler. Arenas and pools kept; the SoA material removed. |
| [Seed Artifacts](08_seed_artifacts.md) | Vesi's binary and its `.s` published per host; the seed published as one shared image; the sapling as source only. Two size budgets. |
| [Roadmap to Self-hosting](selfhosting.md) | Two T's per front-end step. |
| [Flat Vector](flat-vector.md) | Stage 3 only, because it exists for the frontends Stage 3 hosts. |
| [README](../../README.md) | Stage list, directory overview and a Vesi paragraph. |
| [Architecture Map](../architecture.md) | The index no longer describes the pre-split chain: the seed and the sapling emit images, the end-user flow downloads Vesi and lowers the seed image, the seed no longer "adds macros", and three documents that were missing from the table are indexed. |
| [Koivu Language](03_language.md) | *Purpose and Scope*, the staging rule, the Stage 3 data types, and the statement that Koivu Scheme is a checked subset of R6RS rather than a different type discipline. |

The staging rule that came out of this work lives in
[Koivu Language](03_language.md): each stage compiles a subset of the next
stage's language, fixed by what that next stage's *source* actually uses. Its
corollary is written there too - the seed is not an unfinished Stage 3.

### Partially updated

- [Stage 3 (Production Core)](06_stage3_production_core.md) - SoA removed, but
  its *Stage 3 Library* section (extra syscalls for profiling and clock reads,
  "subject of ongoing research") was left untouched.

### Not yet reviewed

Queued in this order:

1. [Frontends](07_frontends.md) - not checked against the staging rule in
   [Koivu Language](03_language.md).
2. [Data-Oriented Design](data_oriented_design.md)
3. [Reader Macros Notes](notes_on_reader_macros.md) - its "stay dynamic" claim is
   gone as of `7059f59`; the rest of the document has not been reviewed.
4. [Carbon Datatypes](carbon_datatypes.md)
5. [Seed Sizes Notes](notes_on_seed_sizes.md) - probably overlaps the budgets in
   [Seed Artifacts](08_seed_artifacts.md), section 7; check before trusting
   either.
6. The `s-llvm-ir` family - [S-LLVM IR](s-llvm-ir.md),
   [AST S-LLVM IR](ast-s-llvm-ir.md),
   [S-LLVM IR to LLVM IR AST Notes](notes_on_s-llvm-ir_to_llvm_ir_ast.md) and
   [LLVM IR Parsing Notes](notes_on_llvm_ir_parsing.md). They describe a
   representation that Stages 1 and 2 no longer touch. Narrow to Stage 3 or
   delete; that is a decision, not an edit.
7. `docs/vision.md`, `docs/style-guide.md`

No change needed: [Pino Interpreter Notes](notes_on_pino_interpreter.md) is the
record of a rejected option and is cited by [Koivu Vesi](koivu-vesi.md), section
1.

## 4. Session log

Commits from the session that produced the split, oldest first. All on `main`.

| Commit | Scope |
| :--- | :--- |
| `39915c5` | `backend.md` finished: form, image capture, Vesi writes containers, criterion 9, decisions 3/4/8/12 |
| `1934f5b` | `koivu-vesi.md` section 10 marks the `backend.md` reconciliation done |
| `20a4b2d` | Entry decision (`entry` calls `main`) across `pino.md`, `koivu-vesi.md` and `04` |
| `2b30424` | Deleted the stale `05_stage2_bridge.md` |
| `5af89b4` | `03_language.md` gains *Purpose and Scope* |
| `0dcbe79` | `flat-vector` restaged to Stage 3 across four documents |
| `ba79442` | `README.md` stage list, `bootstrap/pino/` as Vesi, `targets/` read by Vesi |
| `0c56a21` | `06` no longer claims Stage 3 uses SoA flat-vector IRs |
| `2c22e65` | `05_stage2_sapling.md` fully rewritten |
| `b5c30d3` | `04` section 7: `bootstrap/stage1/` holds `*.c` and `*.scm` side by side until M2 |
| `837aa33` | `02`: Vesi in the build chain and the trust story; three kinds of intermediate |
| `867b46b` | `selfhosting.md` rewritten with two T's per front-end step |
| `c0d4ef5` | `08` fully rewritten: published set and two budgets |
| `7be69e9` | Published-set change propagated into `01`, `02`, `selfhosting`, `backend`, `pino` |
| `8537b88` | `08`: Vesi's `.s` is committed per host, not per target |
| `db08b5b` | `koivu-vesi.md` section 6: Goal B cross-compiles Vesi, not the seed |
| `ff21cc8` | Deleted `bootstrap/stage1-ll/` - the evaluator-shaped `.ll` prototype |
| `da266b5` | `02` section 2: dropped the rejected "seed in `.ll` early" option |
| `71ec0e9` | This file rewritten as a ledger rather than a copy of the blueprints |
| `8d7147` | `architecture.md`: seed and sapling emit images; Stages 1 and 2 no longer "lower it themselves" |
| `1a4d524` | `architecture.md`: end-user installation downloads Vesi and lowers the seed image |
| `52e5b65` | `architecture.md`: index gains `flat-vector`, the interpreter notes, the reader macros notes |
| `a54a73b` | `architecture.md`: the seed does not add macros; the sapling carries the expander |
| `7059f59` | Dropped the "stay dynamic" goal in `architecture.md` and the reader macros notes; `03` gains the checked-subset-of-R6RS statement |

Earlier commits are in the log. The previous revision of this file described
`811b5b4` through `83606d7`, which covered the first passes over `backend.md`,
`01`, `02`, `04`, `selfhosting.md` and `08`, the closures decision, and the
branch protection.

## 5. Decisions that reshaped the blueprints

Recorded here because each one spans several documents and the reasoning is
spread across them. Where a decision has a home, the home is named.

- **Lowering is a program, not a library.** `koivu-vesi.md`, section 1, and
  `backend.md`, section 9, decision 3.
- **The entry function is `entry`, which calls `main`.** `pino.md`, section 3.
  The alternative - `main` is the entry and ends with a `(syscall exit)` - was
  rejected because it requires exactly one procedure in every program never to
  return, and no verifier can express that: at process entry the return register
  holds nothing, so a stray `(ret)` jumps through garbage on `arm64` and pops
  garbage on `x86_64`.
- **No `-o` and no `--emit-pino`.** `04`, section 7. `--emit-pino` names a choice
  the seed does not have; `-o` cannot serve a manifest with several programs.
  Determinism is tested by a committed golden image instead.
- **The sapling emits a Pino image**, not expanded Scheme. `05`, section 1. The
  alternative would have created a third interchange format across a component
  boundary, needing canonical printing, versioning and verification of its own.
- **One source set.** The sapling is the seed's Scheme front end plus an
  expander, compiled into a second program; the same source becomes the seed at
  M2. `05`, section 1.
- **`flat-vector` is a Stage 3 data type.** `03` and `flat-vector.md`. Its raw
  reallocation form needs `realloc`/`free`, which the seed's bump arena has
  neither of.
- **The published set.** Vesi's binary plus Vesi's `.s`, per host; the seed as one
  shared `koivu-seed.pino`; the sapling as source only. `08`, section 1. The
  trusted artifact becomes the smaller program, and the two halves of the split
  audit are exactly what is published.
- **`build.sh` and `build.cmd` live in `bootstrap/`**, because they start two
  sibling programs. `04`, section 7. `bootstrap/pino/` keeps its name though it
  is now Vesi's source set: it is named for what it reads.

## 6. Known remaining inconsistencies

**None confirmed.** The two that were confirmed have been fixed and are listed
under *Resolved* below.

**Carried over from earlier passes, not re-checked since the split.**

- Static typing vs runtime predicates (`integer?`, `pair?`), given that "Cons
  Cells do not use value tagging". Possibly resolved by the checked-subset
  statement in [Koivu Language](03_language.md), since a predicate over a
  representation fixed at compile time folds to a constant; confirm rather than
  assume.
- Multi-file R6RS libraries vs a single input capped by `MAX_INPUT_BYTES`, with
  no import resolution.
- Pass-arena reset destroying the pass's own output - there is no
  ownership-transfer rule.
- Free-list pools vs the Arena / No-GC invariant.
- Two data-layout notations: `struct ast-pool` / `make-s64vector` vs
  `define-flat-vector:` / `flat-vector-ref`. Possibly resolved by moving
  `flat-vector` to Stage 3, since the two then belong to different stages;
  confirm rather than assume.

**Resolved, kept for the record.**

- [Architecture Map](../architecture.md) described the pre-split chain: the seed
  lowering with "the Pino compiler library", a pre-built seed published per host
  in the end-user flow, and "Stage 1 compiles the source code of Stage 2 (adding
  macros)". Fixed in `8d7147`, `1a4d524`, `52e5b65` and `a54a73b`.
- **"Stay traditional, dynamic, and macro-rich"** vs **"All Koivu stages are
  statically typed"**. The goal now asks for homoiconicity and macros rather than
  dynamism, and [Koivu Language](03_language.md) states that Koivu Scheme is a
  checked subset of R6RS. Fixed in `7059f59`.
- "Exactly six host OS primitives" vs eight calls in the adjacent table. The
  documents now say **seven** ([Stage 1](04_stage1_seed.md), section 3;
  [Platforms and Targets](01_platforms.md), section 6.1; [Seed
  Artifacts](08_seed_artifacts.md), section 7).
- `01`'s old section 7 open questions - Mach-O scope, POSIX source set,
  publication channel - are gone from that document and answered in place: all
  three container formats are Vesi's, Linux and macOS share one POSIX source set,
  and every release publishes for every supported host.
- The numeric size budgets and the CI regeneration check are no longer open
  items; both are stated in [Seed Artifacts](08_seed_artifacts.md), sections 3
  and 7, as estimates with ceilings.

## 7. Next step

[Frontends](07_frontends.md). Read it in full and produce the inconsistency list
before editing anything, then check its staging claims against the rule in
[Koivu Language](03_language.md): each stage compiles a subset of the next
stage's language, and the subset is fixed by what that next stage's source
actually uses.

## 8. Repository logistics

Context that is not part of the architecture but affects how work is delivered.

- **No code exists yet.** `bootstrap/` is empty since `ff21cc8`: the only thing
  in it was the `.ll` prototype, which contradicted the blueprint and was
  deleted. Every layout the blueprints describe - `bootstrap/stage1/`,
  `bootstrap/pino/`, `targets/` - is planned, not present. Read those sections as
  structure, not as an inventory.
- **`koivu` is public by design.** SourceCraft allows anonymous read access to
  public repositories over git HTTPS, so a credential-less clone is expected
  behaviour, not a leak. Anonymous access is read-only.
- **Write access** requires a PAT or SSH key *and* a role of `Repository
  developer` or above. `Repository viewer` and `Repository contributor` cannot
  push.
- **`main` is protected** since `83606d7`: force push and deletion are rejected.
  Direct commits are still allowed. There is no `.sourcecraft/review.yaml`, so
  review is not enforced on pull requests.
- **GitHub.** <https://github.com/MichaelKoivisto/koivu> exists and its history is
  meaningful. The SourceCraft `koivu` is a native repository, not an import, so
  the two histories are independent.
- **Do not enable mirroring** until the reconcile lands. Mirroring is one-way,
  GitHub -> SourceCraft, and overwrites the SourceCraft branch with a force push.
  Once GitHub's `main` contains every SourceCraft commit, mirroring becomes
  lossless and is the correct long-term sync.
- **Reconcile plan:** clone locally, add GitHub as a second remote,
  `git merge --allow-unrelated-histories --no-commit github/main`, resolve the
  conflict list file by file, commit, push a side branch, then open a PR on
  GitHub. Never force-push the GitHub side.
- **Incident, resolved:** an accidental discard in the web UI once wiped the
  uncommitted working tree, destroying this file and the first copy of
  `.sourcecraft/branches.yaml`. `branches.yaml` was recreated and committed in
  `83606d7`; this file was recreated afterwards. That is why the top of this
  document says to commit it.
