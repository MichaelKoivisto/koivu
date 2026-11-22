# Synchronising SourceCraft and GitHub

**Status:** Maintenance note

**Component:** Repository workflow

This document describes how the two copies of Koivu are kept in step: the
primary repository on SourceCraft and the public mirror-history repository on
GitHub. It is not an architecture document and says nothing about the compiler.

**Remotes used below:**

| Remote | Host | Role |
| :--- | :--- | :--- |
| `origin` | SourceCraft | primary working repository |
| `github` | GitHub | public repository, its own history is significant |

> **Never put a personal access token in this file, in a remote URL, or in any
> committed file.** Use the platform credential helper, the OS credential store,
> or an SSH key.

---

## 1. Why automatic mirroring is not used

SourceCraft can mirror a GitHub repository, but the feature does not fit this
project:

* Synchronisation runs **automatically every two hours**. "Sync now" exists as an
  additional manual trigger, not as a replacement for the timer — there is no
  manual-only mode.
* The sync is a **force push from GitHub onto the SourceCraft branch**. Any
  commit made in SourceCraft after the previous sync is overwritten.

Since work is committed on SourceCraft first and pushed to GitHub second, an
automatic force push in the opposite direction is exactly the wrong thing.

**Mirroring therefore stays off.** `koivu` on SourceCraft is a native
repository with no migration source attached, so nothing needs disabling; just
never enable it.

Synchronisation is done by hand with ordinary `git`, as described below.

---

## 2. Prerequisite: write credentials

The repository is public, so **cloning** needs no credentials — anonymous read
access over git HTTPS is intentional platform behaviour, not a leak.

**Pushing** to SourceCraft always requires authentication: a personal access
token or an SSH key, belonging to a user with the `Repository developer` role or
above. A token needs write permission; a read-only token will clone but fail on
push.

GitHub uses its own credentials. If both remotes need separate authentication,
configure a credential helper rather than embedding anything in the URL.

---

## 3. One-time step: unifying the histories

The two repositories started with independent histories. They only need to be
unified once; after that, keep them converged as described in section 4.

Check whether this is still needed:

```bash
git fetch origin
git fetch github
git merge-base origin/main github/main
```

If that prints a commit hash, the histories are already shared and this section
can be skipped. If it reports no merge base, unify them:

```bash
git switch main
git pull --ff-only origin main
git merge github/main
git push origin main
git push github main
```

Pushing the **same merge commit to both remotes** is what makes this a one-time
step. Afterwards `main` is identical on both sides.

**Expected conflicts.** The merge touches any file that both sides edited since
diverging. Resolve each one deliberately; `--ours` is the local branch
(SourceCraft's content), `--theirs` is what is arriving from GitHub:

```bash
git status --short
git checkout --ours -- path/to/file    # keep SourceCraft's version
git checkout --theirs -- path/to/file  # take GitHub's version
git add path/to/file
```

Never resolve by force-pushing either side.

---

## 4. Steady-state workflow

The normal direction is **SourceCraft first, GitHub second**.

```bash
git pull --ff-only origin main          # start from SourceCraft's latest
git switch -c pr/<topic>                # branch for the pull request
git push github pr/<topic>              # open the PR on GitHub
# ... merge the PR on GitHub ...
git switch main
git pull --ff-only github main          # GitHub's merge commit arrives locally
git push origin main                    # SourceCraft fast-forwards to it
```

**Note the syntax.** `git pull` takes a **remote name and a branch name as two
separate arguments** — `git pull origin main`. Writing `git pull origin/main`
makes git look for a remote literally named `origin/main`, which does not exist,
and it fails with `'origin/main' does not appear to be a git repository`.
Commands that take a commit rather than a remote — `merge`, `log`, `diff`,
`rev-parse`, `merge-base` — do accept `github/main`, because that is a
remote-tracking ref. The two forms look similar but are not interchangeable.

The last two commands are the whole trick: **after every PR merge, immediately
fast-forward SourceCraft to GitHub.** Both sides then sit on the same commit and
never drift.

---

## 5. The rule that keeps it painless

**Do not commit to SourceCraft's `main` between opening a pull request and
merging it.**

If you do, SourceCraft gains a commit the pull request does not contain, and the
next synchronisation stops being a fast-forward — you are back to a hand merge.
Using `--ff-only` on every pull is what surfaces this immediately instead of
silently creating a merge commit.

---

## 6. GitHub-first exception

Rarely, a commit is made directly on GitHub. Bring it back the same way:

```bash
git fetch github
git switch main
git merge --ff-only github/main
git push origin main
```

This stays clean only while SourceCraft has no commits that GitHub lacks — which
section 5 guarantees.

---

## 7. Verification

Both sides are converged when all three hashes agree:

```bash
git rev-parse main origin/main github/main
```

They must print the same commit hash. If `main` differs from `origin/main`, a
local commit has not been pushed. If it differs from `github/main`, a pull
request is still open, or GitHub has moved ahead.

Branch protection on SourceCraft's `main` rejects force pushes and deletion.
Normal pushes are allowed, so the commands above work unchanged.

---

## 8. Cheat sheet

| Direction | Commands | When |
| :--- | :--- | :--- |
| SourceCraft to GitHub | branch, `git push github <branch>`, open PR, merge | every change; the normal flow |
| GitHub to SourceCraft | `git pull --ff-only github main`, `git push origin main` | after every PR merge |
| Commit on SourceCraft | `git commit`, `git push origin main` | freely, when no PR is open |
| Automatic sync | none - mirroring stays off | never |
