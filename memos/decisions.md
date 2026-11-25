# Decision log — dctools

Append-only, newest first. One entry per decision that would be **expensive to reverse**
or that someone might later ask *"why did we do it that way?"* — scope calls, API design
forks, dependency choices. Tooling friction goes in `workflow-feedback.md`, not here.

Add entries with `/log-decision`, or by hand using the template below.

## 2026-11-25 - Retire the render check: trust comes from reports calling validated targets, not from inspecting output
**Decision:** dctools does not inspect rendered deliverables, or other people's documents and files. `check_rendered_values()`, the `render_checked` receipt, `render_exemptions` and the bundle's insertion records are removed; deliverables are still copied into the release bundle and hashed. The trust chain instead runs: (1) reports are produced by Claude only from a notebook (qmd), with every reported number produced by inline code wherever possible; (2) those inline expressions read **output targets**, so the report shows a call to a target rather than a computation or a literal; (3) a report check (planned, `ROADMAP.md` section 8) confirms the report calls only targets the pipeline validates; (4) the pipeline validates that each output target is produced according to the spec. `show_count()` stays as a masked-count formatter but is not the reporting channel.
**Why:** Catching every number in rendered output overpromises. Figures and table images are invisible to it, code-generated tables fail it, and estimates have no insertion channel (AUD-008), so it pushes toward ever-wider exemptions. Moving the check up the chain makes the claim one we can keep: the numbers come from named targets, and the targets are what the pipeline machinery checks.
**Alternatives rejected:** a stricter render check that counts only non-exempt numbers (still blind to images and hostile to tables); scanning the qmd for literal numbers as the gate (useful as a review list, but it can't show that inline code reads validated values).
**Links:** dctools PR #42 (AUD-004/005), system audit `biostat_support/tests/audit/findings/2026-11-23-system.md` (AUD-005, AUD-008); architecture spec section 9 in biostat_support needs the matching change.

## 2026-10-20 - Run ledger: the audit, not the analyst, vouches for reported numbers
**Decision:** Reported numbers enter reports only through `record_count()` and friends, which record their source lines; a PHI-free ledger indexes each run; `audit_run()` checks it with a fixed catalogue (C1-C9) that projects cannot shorten and that is tested to fail on corrupted input. The audit runs once, right after the run.
**Why:** An agent-run analysis must be checkable without trusting the agent: its claims are citations into an audit file it cannot write, and the audit is reproducible from git, the store and the inputs.
**Alternatives rejected:** a claims file written by the agent (it could fabricate both claim and ledger); verification as a target (a target cannot audit the run it belongs to); snapshots only (they show change, not which code produced it); replaying old runs (needs hash-stable objects; not needed when every run is audited immediately).
**Links:** `memos/specs/2026-10-20-run-ledger-design.md`, `memos/plans/2026-10-20-run-ledger.md`.

## 2026-07-10 — `clean_colnames()` wraps `janitor::make_clean_names()`; janitor in Suggests

**Decision:** Refactor `clean_colnames()` to delegate name cleaning to
`janitor::make_clean_names(case = "snake")` instead of the hand-rolled `gsub` chain.
`janitor` goes in **`Suggests`**, not `Imports`. When it is not installed,
`clean_colnames()` **errors** with an install hint (`cli::cli_abort`) rather than falling
back to the old chain. The `"colname_map"` before/after attribute and the "Renamed N
columns" message are preserved. `check_colnames()` stays custom (report-only, no janitor
equivalent).

**Why:** `make_clean_names()` handles transliteration, non-ASCII, and de-duplication more
robustly than the gsub chain (ROADMAP section 1). But janitor pulls **8 packages** not
already in the dctools tree - including the heavy compiled `stringi` and `lubridate` -
so the "heavy/optional -> Suggests + `requireNamespace()` guard" convention (CLAUDE.md)
applies. Erroring rather than falling back keeps output **deterministic across
environments**: a QC/reproducibility tool must not emit a different `colname_map`
depending on whether a Suggested package happens to be installed, and a silent fallback
would route users to the *less* robust algorithm the refactor set out to retire.

**Alternatives rejected:** `janitor` in `Imports` (hard dependency; forces stringi +
lubridate on every install, against the low-dependency lean). Suggests + silent fallback
to the gsub chain (non-deterministic output across machines; defeats the robustness goal).

**Links:** `ROADMAP.md` section 1; `R/qc.R` `clean_colnames()`; branch
`roadmap-janitor-clean-colnames`.

## 2026-07-04 — ROADMAP sections 9-12 reframed as delegation gates; demand-driven build

**Decision:** The unbuilt ROADMAP groups (section 9 model-assumption diagnostics, 10
causal/semiparametric checks, 11 prediction evaluation, 12 simulation utilities) are the
**verification layer that makes agent-delegated analyses auditable** - machine-checkable
gates (positivity, balance, weights, calibration, coverage) that an analysis must pass
before its results are trusted. Build order is **demand-driven**: implement a function
when a real analysis or its home skill actually needs the gate, not in roadmap order.
Thin tests (`test-viz.R`, `test-packages.R`) get backfilled when those modules are next
touched.

**Why:** Strategic review 2026-07-04 (see `biostat-support/docs/north-star.md`). For a
statistician, silent errors are the failure mode of AI-assisted analysis; verification
infrastructure is what converts "Claude helps me code" into "I can delegate an analysis
and audit the gates." Demand-driven build is also the only honest test of an API - a
function written against a real analysis gets its signature right.

**Alternatives rejected:** Roadmap-order buildout (produces untested-in-anger APIs and
competes with higher-value work); moving judgment into the functions (violates the
design contract - gates report, skills decide).

**Links:** `ROADMAP.md`; `biostat-support/docs/north-star.md`;
`biostat-support/docs/design-philosophy.md`.

<!-- TEMPLATE - copy for each entry, newest at the top:

## {{YYYY-MM-DD}} - {{short decision title}}
**Decision:** {{what was decided, stated as a commitment}}
**Why:** {{the reasoning / evidence that settled it}}
**Alternatives rejected:** {{what else was on the table and why not}}
**Links:** {{commit / PR / memo / ClickUp task}}

-->
