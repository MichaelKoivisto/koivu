# Review Progress — Working Notes

Temporary document. It records where the architecture review stands so that work
can be resumed in a later session without re-deriving context.

**Delete this file when the review is finished.** It is deliberately absent from
the index in `docs/architecture.md`.

Last updated after commit `83606d7`.

---

## 1. Working agreement

These are decisions about *how* the review is conducted, not about the
architecture itself. They were established during the review and should be
honoured in later sessions.

- **Language.** Discussion and documents are in English.
- **One document at a time.** Read the whole document and produce an
  inconsistency list *before* editing anything.
- **Nothing is committed without an explicit instruction.** A rejected commit is
  not retried.
- **One commit per file** when the changes are local to that file. When a single
  decision spans several files, use **one commit across all of them** — splitting
  it would leave the documents contradicting each other between commits.
- **Do not rename files or sections without asking.** Approved so far:
  `koivu_seed_glue_posix.ll` splits into `koivu_seed_glue_linux.ll` plus a new
  `koivu_seed_glue_macos.ll`. Deliberately *not* renamed:
  `koivu_seed_build_posix.sh`, because `01_platforms.md` §7 Q2 is still open.
- **Do not silently fix a defect that needs a decision.** Raise it instead.
- **Do not plan technical implementation before a repository exists.**

Project preferences that the documents must reflect:

- **Small seed size is the top priority**, above bridge size. Permanent rule.
- **Simplest solution wins** for platform decisions.
- **Documents record *why*, not just *what*.** Platform priorities,
  auditability rationale and rejected options belong in the text so that
  decisions are not re-derived later.

---

## 2. Commits landed

All on `main`.

| Commit | Scope |
| :--- | :--- |
| `811b5b4` | `backend.md` rewritten — vocabulary, two LLVM dependencies, bootstrap goal, M0–M4, inventory, emitter / `simple-codegen` / five configurations A–E, closure invariant, target descriptions, `koivu-llc`, acceptance criteria 1–7, decisions 1–9 |
| `e1cc574` | `08_seed_artifacts.md` added; `architecture.md` index updated |
| `bd324f8` | `01_platforms.md` rewritten; decision 6 annotated (Mach-O deferred) |
| `6987cf6` | `02_bootstrapping_and_trust.md` — four-step chain, B-vs-C fixpoint, what the chain proves |
| `cb261b0` | Decision 10 recorded: `backend.md` §9 and §8 criterion 6, `04_stage1_seed.md` §4 "Closures (simplified)" and §2 `musttail`, `03_language.md` (closures moved to basic types shared by all stages; Stage 2 now lists only wider integers + `flat-vector`; removed the wrong "three basic data types" count) |
| `522a93f` | Closures no longer attributed to Stage 2 in `README.md`, `architecture.md`, `selfhosting.md` |
| `188a1a1` | `04_stage1_seed.md` — §3 macOS `libSystem` note, qualified intro claim, §4 `eval` split plus the "compiles vs executes" paragraph (decision 7), §7 glue split Linux/macOS and "Build Process (development builds)", §8 tests 6 and 7, `Brige` typo |
| `2a51671` | `selfhosting.md` pass 1 (structure) — Step 0 = seed build, Steps 1–4 renumbered to match `02` §6, lowering shown inside Step 1, note that `simple-codegen` never covers Stage 3 IR, "LLVM scaffold completely discarded" claim removed |
| `0bdd271` | `selfhosting.md` pass 2 — §6 Artifact Axis, §7 macOS: the Simple Path Platform |
| `83606d7` | `.sourcecraft/branches.yaml` — `main` protected against force push and deletion |

---

## 3. Document status

### Rewritten and considered done

- `backend.md`
- `08_seed_artifacts.md`
- `01_platforms.md`
- `02_bootstrapping_and_trust.md`
- `04_stage1_seed.md`
- `selfhosting.md` (two passes)

### Partially updated

- `03_language.md` — closures only. The dynamic-vs-static typing contradiction
  and the reader-macro items are still open.
- `architecture.md`, `README.md` — closures wording only.

### Not yet reviewed

Queued in this order:

1. `05_stage2_bridge.md`
2. `06_stage3_production_core.md`
3. `07_frontends.md`
4. `data_oriented_design.md`
5. `flat-vector.md`
6. `notes_on_llvm_ir_parsing.md`

Present in `docs/architecture/` but not yet scheduled:
`ast-s-llvm-ir.md`, `s-llvm-ir.md`, `notes_on_reader_macros.md`,
`notes_on_s-llvm-ir_to_llvm_ir_ast.md`, `carbon_datatypes.md`.
Also unreviewed: `docs/vision.md`, `docs/style-guide.md`.

---

## 4. Decisions in force

Numbered in `backend.md` §9.

1. `simple-codegen` input = **in-memory S-LLVM IR AST only**.
2. `simple-codegen` output = **linked executable**, produced with the container
   writer.
3. `koivu-llc` input = **textual `.ll`** (true drop-in; parser lives in the
   production stack, never in the seed).
4. `simple-codegen`'s subset does **not** cover the Stage 3 build.
5. `(koivu backend s-llvm-ir)` = **mirror**. *Provisional.*
6. Container formats: all three eventually; **near term ELF and PE only**.
7. **B long-term** (Stage 1 Lisp executed by the seed's evaluator), **E interim**
   (external `llc`).
8. External `llc` for the Stage 3 build **until M4**. *Provisional.*
9. **Bootstrap goal:** the bridge build must not depend on any external tool. Met
   at M2.
10. **Stage 1 closures:** `closure = { code_ptr, env_ptr }`, frames
    `{ parent_env_ptr, slot0, ... }` linked not copied, access by compile-time
    `(depth, index)`, `set!` on captured variables allowed, arena-backed so no
    GC; fixed arity only, `musttail` for tail calls.

Session-level decisions that shaped the commits:

- Decision 10 was applied as **one commit across three files**, not split.
- `selfhosting.md` was reviewed in **two passes** at the author's request.
- The **"exactly six host OS primitives"** discrepancy was left unfixed on
  purpose — `01_platforms.md` §6.1 depends on the number six, so it needs a
  decision rather than a quiet edit.
- macOS uses the **shape of rejected option D** in `selfhosting.md` §7, stated
  explicitly so it does not read as a contradiction of `backend.md` §3.3.

---

## 5. Open questions

Recorded in the documents and still unanswered.

- **`01_platforms.md` §7 Q1:** Is a Mach-O container writer in near-term scope,
  or is macOS served by `.s` plus the platform `as`/`ld`/`codesign`? This also
  decides whether macOS can reach Steps 3 and 4, since those need Stage 3 to
  emit a signed Mach-O.
- **`01_platforms.md` §7 Q2:** Do Linux and macOS share one POSIX source set, or
  separate seed sources?
- **`01_platforms.md` §7 Q3:** Are other-target binaries published per release or
  on request?
- **`08_seed_artifacts.md` §8:** numeric seed size budget per artifact; whether CI
  regenerates `.s` and fails on mismatch.

---

## 6. Known remaining inconsistencies

Cross-document items, to be fixed file by file:

- **"Stay traditional, dynamic"** (`architecture.md`) vs **"all stages are
  statically typed"** (`03_language.md`).
- **Static typing vs runtime predicates** (`integer?`, `pair?`) given that
  "Cons Cells do not use value tagging".
- **Multi-file R6RS libraries** vs a single input capped by
  `MAX_INPUT_BYTES` = 16 MiB with no import resolution.
- **Pass-arena reset destroying the pass's own output** — there is no
  ownership-transfer rule.
- **Free-list pools** vs the Arena / No-GC invariant.
- **Two data-layout notations:** `struct ast-pool` / `make-s64vector` vs
  `define-flat-vector:` / `flat-vector-ref`.
- **"Exactly six host OS primitives"** (`04_stage1_seed.md` §3) vs eight calls in
  the adjacent table (`fstat`/`lseek`, `close`/`exit` are pairs).

---

## 7. Next step

**`docs/architecture/05_stage2_bridge.md`** — read it in full and produce the
inconsistency list before editing anything.

Known items to confirm:

- It says Stage 2 emits macro-expanded Scheme and terminates. This contradicts
  `architecture.md` and `02_bootstrapping_and_trust.md`, where the bridge emits
  IR for Stage 3.
- "Strict hygiene" is claimed, but only a `gensym`-style renamer is described.
- Local macros are forbidden, while `03_language.md` promises modular pipelines.
- Reader macros (`#+`, `#-`, `#llvm_ir{...}`, `#asm[...]`, `#c{...}`) are
  unhandled by Pass 1.

---

## 8. Repository logistics

Context that is not part of the architecture, but affects how work is delivered.

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
  meaningful. The SourceCraft `koivu` is a native repository (not imported), so
  the two histories are independent.
- **Do not enable mirroring** until the reconcile lands. Mirroring is one-way,
  GitHub → SourceCraft, and overwrites the SourceCraft branch with a force push.
  Once GitHub's `main` contains every SourceCraft commit, mirroring becomes
  lossless and is the correct long-term sync.
- **Reconcile plan:** clone locally, add GitHub as a second remote,
  `git merge --allow-unrelated-histories --no-commit github/main`, resolve the
  conflict list file by file, commit, push a side branch, then open a PR on
  GitHub. Never force-push the GitHub side.
- **Incident, resolved:** an accidental discard in the web UI wiped the
  uncommitted working tree, destroying this file and the first copy of
  `.sourcecraft/branches.yaml`. `branches.yaml` was recreated and committed in
  `83606d7`. This file was recreated afterwards — hence the instruction at the
  top: commit it.
