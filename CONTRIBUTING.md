# Contributing to dctools

This is a personal toolkit, but it follows package discipline so it
stays maintainable and trustworthy.

## Workflow

1.  Branch off `main` — never commit directly to `main`.

2.  Add or change code under `R/`, with a Roxygen2 block (`@param`,
    `@return`, `@export`) for every exported function. Internal helpers
    are prefixed `.`.

3.  Add a `testthat` test under `tests/testthat/` for new behavior.

4.  Regenerate docs and check:

    ``` r

    devtools::document()   # updates NAMESPACE + man/
    devtools::test()
    devtools::check()      # must pass clean
    ```

5.  Format with [Air](https://posit-dev.github.io/air/): `air format .`

6.  Update `NEWS.md`, open a PR. CI (R-CMD-check, coverage) must be
    green.

## Conventions

- **Data manipulation:** `dplyr` surface grammar. For large data, use
  the same verbs over `arrow` or `dbplyr` backends. Reserve `data.table`
  for profiled hot paths only.
- **Dependencies:** keep `Imports` minimal; put heavy or optional
  packages in `Suggests` and guard them with
  [`requireNamespace()`](https://rdrr.io/r/base/ns-load.html).
- **No PHI** ever enters this repo, including in tests or examples.
