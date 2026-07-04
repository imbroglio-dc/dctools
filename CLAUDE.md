# CLAUDE.md — dctools

This file guides Claude Code when working in this repository. `dctools`
is a personal R package of tested helper functions for prediction- and
causal-inference research. It lives in the `helpers` repo; the package
is named **`dctools`**.

## Design philosophy (read before adding or changing functions) — IMPORTANT

`dctools` is **one half of a system**. The other half is the
**biostat-support skills marketplace** (a separate repo). The division
of labor is a hard contract:

- **`dctools` = mechanics.** Tested, documented functions that *do* the
  repetitive work (intake QC, validation, diagnostics, scaffolding,
  formatting). No opinion about *when* to call them.
- **Skills = judgment.** What to do, when, what to check, red flags.
  That lives in the marketplace, not here.

**Therefore, when extending `dctools`:**

- Add a function only if it’s a **reusable mechanic** with a **home
  skill** that will call it (or a clear place on `ROADMAP.md`). Don’t
  add one-off, project-specific logic.
- Keep the *judgment/caveats* out of the function — a paragraph of
  “when/why” belongs in a skill or rule, not buried in roxygen. Roxygen
  documents *what it does*, not *when to use it*.
- If you find yourself wanting to hand-write a mechanic inside a skill
  or analysis, it belongs **here** instead.

`ROADMAP.md` lists planned functions grouped by analysis stage; each
group maps to a home skill (data-preparation, analysis-design,
statistical-critique, simulation-study, prediction-eval, …). Keep
`ROADMAP.md` and the marketplace’s `docs/design-philosophy.md` in sync
(that doc holds the full complementarity map).

**Build order is demand-driven, not roadmap order** (decision
2026-07-04, see `memos/decisions.md`): ROADMAP sections 9-12 are the
verification gates that make agent-delegated analyses auditable —
implement a function when a real analysis or its home skill needs the
gate. Cross-repo strategy: `biostat-support/docs/north-star.md`.

## Package discipline (non-negotiable)

- **`DESCRIPTION`:** `Authors@R` only (no redundant
  `Author:`/`Maintainer:`); MIT license.
- **Exports:** every exported function has a roxygen block (`@param`,
  `@return`, `@export`) and a `testthat` test. Internal helpers are
  prefixed `.` and not exported.
- **Imports:** call imported functions **fully qualified** (`pkg::fn`)
  so `NAMESPACE` stays export-only. Keep `Imports` minimal;
  heavy/optional packages go in `Suggests` and are guarded with
  [`requireNamespace()`](https://rdrr.io/r/base/ns-load.html).
- **ASCII-only R sources** (R CMD check `--as-cran` errors on non-ASCII;
  use `\uxxxx` or plain ASCII — no em-dashes/accents in `R/`).
- **After any roxygen/export change:** run `devtools::document()`
  (regenerates `man/` + `NAMESPACE`), then `devtools::test()` and
  `devtools::check()` — must pass clean. CI runs R-CMD-check +
  coverage + pkgdown and errors on warnings.
- **Format** with Air (`air format .`; config in `air.toml`).

## Conventions

- **Data manipulation:** `dplyr` surface grammar; `arrow`/`dbplyr` for
  large data (same verbs); `data.table` only for profiled hot paths.
- **Naming:** `snake_case` vars/columns; `verb_noun()` functions;
  `.dot_prefixed` internals.
- **PHI:** never in code, tests, examples, or fixtures.

## Build / test

``` r

devtools::document()   # after roxygen changes — updates man/ + NAMESPACE
devtools::test()
devtools::check()      # must pass clean
```

`man/` is roxygen-generated; do not hand-edit (it is committed so CI can
build).
