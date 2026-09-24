<!--
OVERVIEW.md — the orientation document for this repo.
Read this first to understand what this repo is, why it exists, and how it is laid out.
This is durable: it changes when the project's goals or shape change, not day-to-day.
For where we are on the arc right now (focus, next actions, blockers), see STATUS.md.
For how Claude should work in this repo (conventions, guardrails), see CLAUDE.md.
-->

# dctools

A personal R package of tested helper functions for prediction- and causal-inference
research — the mechanics half of a two-repo system, paired with the `biostat-support`
skills marketplace (judgment).

## Goals

Give every home skill in the `biostat-support` marketplace a tested, documented mechanic
to call rather than a hand-rolled one-off. `ROADMAP.md` lists planned functions grouped by
analysis stage; each group maps to a home skill (data-preparation, analysis-design,
statistical-critique, simulation-study, prediction-eval, …).

## Approach

Hard contract (see `CLAUDE.md`): `dctools` = mechanics — tested, documented functions
that *do* the repetitive work, with no opinion about *when* to call them. Judgment —
what to do, when, what to check, red flags — lives in the marketplace's skills, not here.
Build order is demand-driven, not roadmap order (decision 2026-07-04, `memos/decisions.md`):
ROADMAP sections 9-12 (the verification gates that make agent-delegated analyses
auditable) get built when a real analysis or its home skill needs the gate.

## Structure

- `R/` — package source; exported functions are fully documented (roxygen + testthat).
- `tests/testthat/` — package tests; `devtools::check()` must pass clean.
- `man/` — roxygen-generated docs (committed, not hand-edited).
- `ROADMAP.md` — planned functions grouped by analysis stage, each with a home skill.
- `memos/decisions.md` — append-only decision log; `workflow-feedback.md` — tooling friction.

## Context & constraints

- **Tracker:** see biostat-support `docs/repo-clickup-map.md`. **Branch convention:**
  `CU-<taskid>-<slug>`.
- **PHI:** never in code, tests, examples, or fixtures.
- Package discipline is non-negotiable (see `CLAUDE.md`): ASCII-only R sources, fully
  qualified imports, `R CMD check --as-cran` clean, Air-formatted.

## Decisions

This repo's decision log predates the OVERVIEW/STATUS scheme and stays the canonical
decision home — see `memos/decisions.md` (append-only, newest first) rather than
duplicating entries here.

## Pointers

- **Current status & next actions:** `STATUS.md`
- **Working conventions & guardrails:** `CLAUDE.md`
- **Decision log:** `memos/decisions.md` · **Tooling friction:** `workflow-feedback.md`
- **Planned functions:** `ROADMAP.md`
