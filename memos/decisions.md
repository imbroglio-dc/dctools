# Decision log — dctools

Append-only, newest first. One entry per decision that would be **expensive to reverse**
or that someone might later ask *"why did we do it that way?"* — scope calls, API design
forks, dependency choices. Tooling friction goes in `workflow-feedback.md`, not here.

Add entries with `/log-decision`, or by hand using the template below.

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
