# Package management ----------------------------------------------------------

#' Read R package names from a plain-text file
#'
#' Lines beginning with `#` or `//` (after optional whitespace) are treated as
#' comments and ignored, as are blank lines. Implemented in base R so it carries
#' no dependencies.
#'
#' @param path Path to a text file with one package name per line.
#' @return A character vector of package names (de-duplicated, no blanks).
#' @examples
#' tmp <- tempfile()
#' writeLines(c("dplyr", "# a comment", "", "ggplot2"), tmp)
#' read_packages(tmp)
#' @export
read_packages <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- sub("\\s*(#|//).*$", "", lines) # strip trailing comments
  lines <- trimws(lines)
  unique(lines[nzchar(lines)])
}

#' Load (and optionally install) a vector of R packages
#'
#' Attaches each package, installing missing ones first via `renv` (if
#' available) and then Bioconductor as a fallback. Intended for the analysis
#' preamble of a project, not for use inside package code.
#'
#' @param pkgs Character vector of package names.
#' @param install Logical; install missing packages if `TRUE` (default).
#' @param repos CRAN mirror URL(s); defaults to `getOption("repos")`.
#' @return Named logical vector: `TRUE` = attached, `FALSE` = failed.
#' @export
load_packages <- function(pkgs, install = TRUE, repos = getOption("repos")) {
  pkgs <- unique(as.character(pkgs))
  if (length(pkgs) == 0L) {
    return(stats::setNames(logical(0), character(0)))
  }

  installed <- rownames(utils::installed.packages())
  to_install <- setdiff(pkgs, installed)

  if (length(to_install) > 0L && isTRUE(install)) {
    for (pkg in to_install) {
      ok <- FALSE
      if (requireNamespace("renv", quietly = TRUE)) {
        ok <- tryCatch({
          renv::install(pkg, repos = repos)
          TRUE
        }, error = function(e) FALSE, warning = function(w) FALSE)
      }
      if (!ok) {
        if (!requireNamespace("BiocManager", quietly = TRUE)) {
          tryCatch(
            utils::install.packages("BiocManager", repos = repos),
            error = function(e) NULL
          )
        }
        ok <- tryCatch({
          BiocManager::install(pkg, update = FALSE, ask = FALSE)
          TRUE
        }, error = function(e) FALSE)
      }
      if (!ok) cli::cli_warn("Failed to install package {.pkg {pkg}}.")
    }
  }

  loaded <- vapply(pkgs, function(p) {
    tryCatch({
      suppressPackageStartupMessages(
        library(p, character.only = TRUE, quietly = TRUE, warn.conflicts = FALSE)
      )
      TRUE
    }, error = function(e) FALSE)
  }, logical(1))

  stats::setNames(loaded, pkgs)
}
