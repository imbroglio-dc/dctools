---
name: project-conventions
description: dctools package conventions — loaded automatically when writing or reviewing code in this repo.
user-invocable: false
---

# dctools Conventions

Apply when writing or reviewing code in this package.

## Package discipline

- Every exported function has a Roxygen2 block (`@param`, `@return`, `@export`)
  and a `testthat` test. Internal helpers are prefixed `.` and not exported.
- Call imported functions fully qualified (`pkg::fn`) so `NAMESPACE` stays
  export-only. Keep `Imports` minimal; heavy/optional packages go in `Suggests`
  and are guarded with `requireNamespace()`.
- After any change to roxygen or exports: run `devtools::document()`, then
  `devtools::test()` and `devtools::check()` (must pass clean).
- Format with Air (`air format .`); config in `air.toml`.

## Data manipulation

`dplyr` surface grammar. For large data, the same verbs over `arrow` or
`dbplyr`. Reserve `data.table` for profiled hot paths only.

## Safety

- Never commit PHI — not in code, tests, examples, or fixtures.
- Don't push directly to `main` (a hook blocks it); open a PR so CI runs.
