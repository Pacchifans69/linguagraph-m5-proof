# linguagraph-m5-proof

Independent hosted proof evidence for the **M5 — Human-Reviewed POS Annotation
Foundation** checkpoint of
[`Pacchifans69/LinguaGraph`](https://github.com/Pacchifans69/LinguaGraph).

**Repository purpose.** This repository exists for exactly one reason: to run the
M5 **exact-candidate hosted Gate 2 proof** on a clean, independently hosted Linux
machine, and to retain the resulting evidence as immutable artifacts.

It is an **independent repository**: public, **not a fork**, with Git history
unrelated to the application repository. It contains **no application source
code**. The single proof job resolves the exact application candidate from the
remote application repository at run time, fails closed unless every identity
matches, and only then executes the verification surface against that detached
checkout.

---

## 1. Exact subject under proof

| Fact | Value |
| --- | --- |
| Application repository | `Pacchifans69/LinguaGraph` |
| Application candidate branch | `m5-human-reviewed-pos-annotation-foundation` |
| Exact candidate SHA | `139f3349b8556f5dd13d5c2d8808fda4a79dc819` |
| Exact candidate tree | `179aba060d5e798ace46ea6bed0a7c496a50e9ad` |
| Frozen M5 base | `11176df91dd9dc3d1169e4bef41808b0abfa8656` |
| Expected application `main` | `11176df91dd9dc3d1169e4bef41808b0abfa8656` |
| Expected Alembic head | `0006` |

The candidate is expected to be **10 commits ahead / 0 behind** the frozen base.

## 2. Canonical GitHub Actions diagnostic — why this proof exists

The current canonical exact-candidate GitHub Actions run for this candidate is
**run `34564666636`**. It targeted exactly this corrected candidate
(`head_sha = 139f3349b8556f5dd13d5c2d8808fda4a79dc819`) and concluded
`failure`, but it **failed before any repository-defined workflow step began**:
the job reported `steps = []` and its logs were unavailable
(`BlobNotFound`). No repository-defined command of the canonical workflow ever
executed.

This work is authorized under the **Human-approved M5-specific External
Infrastructure Exception**, which the Human has **explicitly re-approved for
this corrected exact candidate** (`139f3349b8556f5dd13d5c2d8808fda4a79dc819`,
tree `179aba060d5e798ace46ea6bed0a7c496a50e9ad`). The earlier M5 exception
approval was granted for the superseded candidate; it did **not** silently carry
forward, and this retargeted proof runs under that explicit re-approval. The
exception waives **only** successful execution on the GitHub-hosted runner. It
does **not** waive any execution, provenance, environment or integrity
requirement listed below.

### Superseded candidate — historical build #1 evidence (retained)

Proof build **#1** (`ci/circleci: m5-exact-candidate-proof`) succeeded, and it
proved the PREVIOUS application candidate only:

| Historical fact | Value |
| --- | --- |
| Old application candidate (superseded) | `285241dc5266f6ed5e1f8a9496662383ad01f536` |
| Old candidate tree (superseded) | `d82284c7fdd6bbde50dafbca243a47c14bbf9cdf` |
| Old proof commit | `4f9040d3c4fc3e7aa88640965c40ee9e328317d6` |
| Old proof tree | `43304d0b0ca2a70c78b8e793a0452a6f69d7e384` |
| Old canonical GitHub Actions run | `34493729495` — failure before any repository-defined step (`steps = []`, logs `BlobNotFound`) |
| CircleCI build | `#1` |
| Result | **SUCCESS** |

This record is **retained historical evidence**; it is not rewritten or
falsified. Build #1 proved **only** the superseded candidate
`285241dc5266f6ed5e1f8a9496662383ad01f536` (tree
`d82284c7fdd6bbde50dafbca243a47c14bbf9cdf`), and it does **NOT** prove the
corrected candidate `139f3349b8556f5dd13d5c2d8808fda4a79dc819` (tree
`179aba060d5e798ace46ea6bed0a7c496a50e9ad`), whose tree differs. The retargeted
proof — proof build **#2** — is intended to establish exact hosted evidence for
the corrected candidate.

### The exception explicitly does NOT waive

- exact provenance (candidate repository, branch, SHA, tree, frozen base,
  merge-base, and the proof repository's own HEAD/`CIRCLE_SHA1` identity);
- a clean, independent hosted Linux machine;
- Python **3.13** exactly;
- Node **24** exactly;
- PostgreSQL **18** exactly, as the only database backend;
- frozen dependency installation (`uv sync --frozen`, `npm ci`);
- migration verification (`alembic upgrade head` / `current` / `check`);
- the complete backend test suite against real PostgreSQL;
- **zero skipped tests**;
- frontend verification (lint, typecheck, tests, production build);
- the complete **M0–M5 Playwright surface**;
- cleanup checks (disposable databases removed, PostgreSQL container removed);
- dependency integrity (before/after lockfile hashes must be identical);
- final tracked-tree integrity (candidate, `main` and proof source unchanged).

## 3. Governance status

- This proof **does NOT close `G2-X01`**; that item remains `OPEN / EXTERNAL`.
- Earlier **M1–M4 proof evidence does not prove M5**. Those proofs cover
  different candidates and different checkpoints; they are not evidence for this
  checkpoint.
- A successful hosted run is **Gate 2 evidence only**.
- A successful hosted run **does NOT authorize** Human Static Diff Review, a
  pull request, a merge, branch deletion, or milestone completion. Those remain
  separate Human decisions.
- This repository never writes to `Pacchifans69/LinguaGraph`: it only reads
  remote refs and fetches the candidate.

## 4. Harness

Tracked files (the complete tracked tree):

```
.circleci/config.yml      CircleCI 2.1 pipeline: one machine job on branch main
.gitignore                excludes proof-artifacts/ and candidate/
README.md                 this contract
scripts/run-m5-proof.sh   the entire verification surface
```

`candidate/` (the detached application checkout), `proof-artifacts/` (generated
evidence) and all install/build output are untracked by design.

The CircleCI job `m5-exact-candidate-proof` runs on the `machine` executor
(`ubuntu-2404:current`, resource class `medium`), invokes the proof script with
`pipefail` and `tee proof-artifacts/command-transcript.log`, and stores the whole
`proof-artifacts/` directory as an artifact. No application CI logic lives in
`config.yml` beyond invoking the proof script.

### Fail-closed stages

| # | Stage | What it proves |
| --- | --- | --- |
| 1 | environment-contract | all required constants are present |
| 2 | environment | hosted Linux / CPU / memory / filesystem / Docker / timezone provenance |
| 3 | proof-provenance | proof repo, branch, `HEAD == CIRCLE_SHA1`, tracked tree clean, file hashes |
| 4 | candidate-checkout | remote refs, exact candidate SHA/tree, merge-base, detached checkout, clean worktree |
| 5 | dependency-hashes-before | SHA-256 of `pyproject.toml`, `uv.lock`, `package.json`, `package-lock.json` |
| 6 | runtime-python | uv installed; Python is exactly 3.13 |
| 7 | runtime-node | Node major is exactly 24 |
| 8 | runtime-postgresql | real `postgres:18` container; `show server_version` starts with `18.` |
| 9 | backend-sync | `uv sync --frozen`; resolved interpreter is Python 3.13 |
| 10 | migration | main database starts empty; `upgrade head`; `current` == `0006 (head)`; `check` clean |
| 11 | backend-tests | complete `uv run pytest -q` against real PostgreSQL 18 |
| 12 | backend-zero-skip | the backend log contains no skipped test |
| 13–17 | frontend-install/lint/typecheck/tests/build | `npm ci`, `npm run lint`, `typecheck`, `test`, `build` |
| 18 | playwright-install | Chromium plus system dependencies |
| 19 | playwright-e2e | `CI=1 npx playwright test` over the complete M0–M5 surface |
| 20 | playwright-surface-guard | every one of the six specifications actually executed |
| 21 | database-cleanup | zero remaining disposable `linguagraph_%` databases |
| 22 | dependency-hashes-after | lockfile hashes identical to stage 5 |
| 23 | final-integrity | remote candidate and `main` unchanged; candidate HEAD/tree/merge-base unchanged; no tracked or staged modification |

A stage failure aborts the run; the `EXIT` trap still writes final identity,
PostgreSQL evidence, cleanup and the SHA-256 artifact manifest. A cleanup failure
turns an otherwise successful proof into `FAIL`.

### Complete M0–M5 Playwright surface

```
e2e/golden-path.spec.ts
e2e/unicode.spec.ts
e2e/segmentation.spec.ts
e2e/token-segmentation.spec.ts
e2e/lemma-annotation.spec.ts
e2e/pos-annotation.spec.ts
```

No test filter, marker, selector or skip is used to shrink any suite.

### Required retained artifacts

`command-transcript.log`, `command-manifest.txt` (per-stage name, start time,
finish time and exit code), `environment.txt`, `runtime-versions.txt`,
`proof-provenance.txt`, `candidate-provenance.txt`, `dependency-lock-hashes.txt`,
`alembic-current.txt`, `backend-tests.log`, `frontend-install.log`,
`frontend-lint.log`, `frontend-typecheck.log`, `frontend-tests.log`,
`frontend-build.log`, `playwright-install.log`, `playwright-e2e.log`,
`post-e2e-databases.txt`, `final-integrity.txt`,
`final-proof-repository-{status,head,tree}.txt`,
`final-candidate-{status,head,tree}.txt`, `final-summary.txt`,
`artifact-manifest.sha256`, plus PostgreSQL container evidence and the Playwright
`test-results` archive when present.

### Result semantics

Only `proof_result=PASS` in `final-summary.txt` means every required stage
succeeded. Bootstrapping this repository, or a CircleCI pipeline merely
existing, is **not** proof success.

## 5. Reading the evidence

1. Take the proof commit SHA and tree from the CircleCI run
   (`final-proof-repository-head.txt` / `-tree.txt`).
2. Verify `final-summary.txt` says `proof_result=PASS` and that every stage in
   `command-manifest.txt` has `exit_code=0`.
3. Verify `candidate-provenance.txt` and `final-integrity.txt` show the exact
   candidate SHA/tree and the unchanged remote refs.
4. Verify `runtime-versions.txt` reports Python 3.13, Node 24 and PostgreSQL 18.
5. Verify the before/after sections of `dependency-lock-hashes.txt` are
   identical and that `post-e2e-databases.txt` is empty.
6. Verify `artifact-manifest.sha256` against the stored artifacts.
