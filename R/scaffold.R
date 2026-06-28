# Project scaffolding ---------------------------------------------------------

#' Create the standard project directory skeleton
#'
#' Idempotent. Creates `code/`, `data/`, `output/`, `docs/`, and `tests/`
#' subtrees under `path` (only those requested), each with a `.gitkeep` marker,
#' and ensures `scratch/` is git-ignored.
#'
#' @param path Project root (default current directory).
#' @param code,data,output,docs,tests Logical; create that subtree.
#' @param extra Optional character vector of additional relative dirs to create.
#' @return `path`, invisibly.
#' @export
make_file_dirs <- function(path = ".", code = TRUE, data = TRUE, output = TRUE,
                           docs = TRUE, tests = TRUE, extra = NULL) {
  subtrees <- c(
    if (code)   c("code/functions", "code/analysis"),
    if (data)   c("data/raw", "data/processed", "data/metadata"),
    if (output) c("output/tables", "output/figures", "output/models"),
    if (docs)   "docs",
    if (tests)  "tests/testthat",
    extra
  )
  for (d in subtrees) {
    abs <- fs::path(path, d)
    fs::dir_create(abs)
    keep <- fs::path(abs, ".gitkeep")
    if (!fs::file_exists(keep)) fs::file_create(keep)
  }
  .ensure_gitignore_entry(path, "scratch/")
  fs::dir_create(fs::path(path, "scratch"))
  invisible(path)
}

#' Scaffold a new research project
#'
#' Creates a project of one of two archetypes:
#' * `"analysis"` - clones the analysis template repo (mechanism: a fresh clone
#'   with history stripped), stamps the project name, and optionally adds a
#'   `targets` pipeline stub.
#' * `"package"` - wraps [usethis::create_package()] and layers the package
#'   best-practices set (MIT license, testthat 3, roxygen markdown, pkgdown,
#'   R-CMD-check + coverage + pkgdown GitHub Actions, NEWS, self-contained
#'   `.claude/`).
#'
#' @param name Project name (also the new directory name).
#' @param path Parent directory in which to create the project (default ".").
#' @param type `"analysis"` or `"package"`.
#' @param targets Logical; for analysis projects, scaffold a `_targets.R` stub.
#' @param template_repo `owner/repo` of the analysis template
#'   (default `"imbroglio-dc/UCSF-Anesthesia_Template"`).
#' @param git Logical; initialise a fresh git repository (default `TRUE`).
#' @return The created project path, invisibly.
#' @export
create_project <- function(name, path = ".", type = c("analysis", "package"),
                           targets = FALSE,
                           template_repo = "imbroglio-dc/UCSF-Anesthesia_Template",
                           git = TRUE) {
  type <- match.arg(type)
  dest <- fs::path(path, name)
  if (fs::dir_exists(dest) && length(fs::dir_ls(dest)) > 0L) {
    cli::cli_abort("{.path {dest}} already exists and is not empty.")
  }
  switch(
    type,
    analysis = .create_analysis_project(name, dest, targets, template_repo, git),
    package  = .create_package_project(name, dest, git)
  )
  cli::cli_alert_success("Created {type} project at {.path {dest}}.")
  invisible(dest)
}

# --- internals ----------------------------------------------------------------

.create_analysis_project <- function(name, dest, targets, template_repo, git) {
  url <- paste0("https://github.com/", template_repo, ".git")
  cli::cli_alert_info("Cloning template {.val {template_repo}} ...")
  gert::git_clone(url, dest, verbose = FALSE)
  fs::dir_delete(fs::path(dest, ".git")) # strip template history

  .stamp_placeholders(dest, name)

  # rename project.Rproj -> <name>.Rproj
  rproj <- fs::path(dest, "project.Rproj")
  if (fs::file_exists(rproj)) {
    fs::file_move(rproj, fs::path(dest, paste0(name, ".Rproj")))
  }
  # make hooks executable
  hooks <- fs::dir_ls(fs::path(dest, ".claude", "hooks"), glob = "*.sh", fail = FALSE)
  if (length(hooks)) fs::file_chmod(hooks, "0755")
  # the standalone bootstrap is redundant once create_project() has run
  fs::file_delete(fs::path(dest, "_setup.R"))

  if (isTRUE(targets)) .write_targets_stub(dest)
  if (isTRUE(git)) .git_init(dest)
}

.create_package_project <- function(name, dest, git) {
  usethis::create_package(dest, open = FALSE, rstudio = FALSE)
  usethis::with_project(dest, quiet = TRUE, code = {
    .try("MIT license",      usethis::use_mit_license("David Chen"))
    .try("roxygen markdown", usethis::use_roxygen_md())
    .try("testthat 3",       usethis::use_testthat(3))
    .try("package doc",      usethis::use_package_doc())
    .try("NEWS",             usethis::use_news_md())
    .try("readme",           usethis::use_readme_md())
    .try("pkgdown",          usethis::use_pkgdown())
    .try("R-CMD-check CI",   usethis::use_github_action("check-standard"))
    .try("coverage CI",      usethis::use_github_action("test-coverage"))
    .try("pkgdown CI",       usethis::use_github_action("pkgdown"))
  })
  .write_air_toml(dest)
  .write_claude_package(dest)
  if (isTRUE(git)) .git_init(dest)
}

.try <- function(label, expr) {
  tryCatch(force(expr), error = function(e) {
    cli::cli_alert_warning("Skipped {label}: {conditionMessage(e)}")
  })
}

.stamp_placeholders <- function(dest, name) {
  for (f in c("CLAUDE.md", "README.md")) {
    p <- fs::path(dest, f)
    if (fs::file_exists(p)) {
      txt <- readLines(p, warn = FALSE)
      writeLines(gsub("{{PROJECT_NAME}}", name, txt, fixed = TRUE), p)
    }
  }
}

.write_targets_stub <- function(dest) {
  writeLines(c(
    "# _targets.R - pipeline definition. Run with targets::tar_make().",
    "library(targets)",
    "tar_source(\"code/functions\")",
    "tar_option_set(format = \"qs2\")",
    "",
    "list(",
    "  # tar_target(raw,   load_raw()),",
    "  # tar_target(clean, prepare(raw)),",
    "  # tar_target(fit,   analyze(clean))",
    ")"
  ), fs::path(dest, "_targets.R"))
}

.write_air_toml <- function(dest) {
  writeLines(c(
    "# Air formatter configuration (https://posit-dev.github.io/air/)",
    "[format]",
    "line-width = 80",
    "indent-width = 2"
  ), fs::path(dest, "air.toml"))
}

.write_claude_package <- function(dest) {
  cl <- fs::path(dest, ".claude")
  fs::dir_create(fs::path(cl, "hooks"))
  writeLines(c(
    "#!/usr/bin/env bash",
    "# Block direct pushes to main/master; encourage PR workflow.",
    "set -euo pipefail",
    "payload=\"$(cat)\"",
    "cmd=\"$(printf '%s' \"$payload\" | sed -n 's/.*\\\"command\\\"[[:space:]]*:[[:space:]]*\\\"\\(.*\\)\\\".*/\\1/p')\"",
    "case \"$cmd\" in",
    "  *\"git push\"*) printf '%s' \"$cmd\" | grep -qE '\\\\b(main|master)\\\\b' && { echo 'GUARD: push to main/master blocked; use a PR.' >&2; exit 2; } ;;",
    "esac",
    "exit 0"
  ), fs::path(cl, "hooks", "git-guard.sh"))
  fs::file_chmod(fs::path(cl, "hooks", "git-guard.sh"), "0755")
  writeLines(
    '{\n  "hooks": {\n    "PreToolUse": [\n      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash .claude/hooks/git-guard.sh" } ] }\n    ]\n  }\n}',
    fs::path(cl, "settings.json")
  )
}

.ensure_gitignore_entry <- function(path, entry) {
  gi <- fs::path(path, ".gitignore")
  lines <- if (fs::file_exists(gi)) readLines(gi, warn = FALSE) else character(0)
  if (!any(grepl(entry, lines, fixed = TRUE))) {
    writeLines(c(lines, entry), gi)
  }
}

.git_init <- function(dest) {
  .try("git init", {
    gert::git_init(dest)
    gert::git_add(".", repo = dest)
    gert::git_commit("Initial project scaffold", repo = dest)
  })
}
