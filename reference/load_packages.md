# Load (and optionally install) a vector of R packages

Attaches each package, installing missing ones first via `renv` (if
available) and then Bioconductor as a fallback. Intended for the
analysis preamble of a project, not for use inside package code.

## Usage

``` r
load_packages(pkgs, install = TRUE, repos = getOption("repos"))
```

## Arguments

- pkgs:

  Character vector of package names.

- install:

  Logical; install missing packages if `TRUE` (default).

- repos:

  CRAN mirror URL(s); defaults to `getOption("repos")`.

## Value

Named logical vector: `TRUE` = attached, `FALSE` = failed.
