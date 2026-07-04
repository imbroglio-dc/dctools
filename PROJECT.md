# dctools - status

**Status:** active - **Stakes:** exploratory - **Updated:** 2026-07-04
**Tracker:** (see biostat-support `docs/repo-clickup-map.md`) - **Branch
convention:** `CU-<taskid>-<slug>`

## Current focus

Demand-driven build of the verification gates (ROADMAP sections 9-12):
implement a function when a real analysis or its home skill needs the
gate, not in roadmap order (decision 2026-07-04, `memos/decisions.md`).

## Next actions

Backfill the thin tests (`test-viz.R`, `test-packages.R`) when those
modules are next touched.

Build ROADMAP section 9-12 functions as home skills or real analyses
demand them.

Keep `ROADMAP.md` in sync with the marketplace’s
`docs/design-philosophy.md` complementarity map when either changes.

## Open questions / blockers

- None currently.

## Recent progress

- 2026-07-04 - ROADMAP sections 9-12 reframed as delegation gates;
  demand-driven build order adopted (`memos/decisions.md`); `PROJECT.md`
  deployed as the status home.

## Key files & entry points

- `R/` + `tests/testthat/` - package source and tests;
  `devtools::check()` must pass clean.
- `ROADMAP.md` - planned functions grouped by analysis stage, each with
  a home skill.
- `memos/decisions.md` - decision log; `workflow-feedback.md` - tooling
  friction.

## Notes
