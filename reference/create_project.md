# Scaffold a new research project

Creates a project of one of two archetypes:

- `"analysis"` - clones the analysis template repo (mechanism: a fresh
  clone with history stripped), stamps the project name, and optionally
  adds a `targets` pipeline stub.

- `"package"` - wraps
  [`usethis::create_package()`](https://usethis.r-lib.org/reference/create_package.html)
  and layers the package best-practices set (MIT license, testthat 3,
  roxygen markdown, pkgdown, R-CMD-check + coverage + pkgdown GitHub
  Actions, NEWS, self-contained `.claude/`).

## Usage

``` r
create_project(
  name,
  path = ".",
  type = c("analysis", "package"),
  targets = FALSE,
  template_repo = "imbroglio-dc/UCSF-Anesthesia_Template",
  git = TRUE
)
```

## Arguments

- name:

  Project name (also the new directory name).

- path:

  Parent directory in which to create the project (default ".").

- type:

  `"analysis"` or `"package"`.

- targets:

  Logical; for analysis projects, scaffold a `_targets.R` stub.

- template_repo:

  `owner/repo` of the analysis template (default
  `"imbroglio-dc/UCSF-Anesthesia_Template"`).

- git:

  Logical; initialise a fresh git repository (default `TRUE`).

## Value

The created project path, invisibly.
