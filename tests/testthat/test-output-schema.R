test_that(".tokens_in_file takes symbols and the words of string constants", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "x.R")
  writeLines(
    c(
      "fit_model <- function(dat, family = 'binomial') {",
      "  stats::glm(y ~ x, data = dat, family = family)",
      "}",
      "label <- 'prep: done'"
    ),
    f
  )
  tok <- .tokens_in_file(f)
  expect_true(all(
    c("fit_model", "dat", "family", "binomial", "stats", "glm", "label", "prep", "done") %in% tok
  ))
  expect_false("prep: done" %in% tok)
  writeLines("this is not R (", f)
  expect_identical(.tokens_in_file(f), character(0))
})

test_that(".project_r_files falls back to _targets.R, R/ and code/ outside git", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "R"))
  dir.create(file.path(dir, "data"))
  writeLines("a <- 1", file.path(dir, "_targets.R"))
  writeLines("b <- 1", file.path(dir, "R", "f.R"))
  writeLines("secret_value <- 1", file.path(dir, "data", "dump.R"))
  files <- .project_r_files(dir)
  expect_setequal(basename(files), c("_targets.R", "f.R"))
})

test_that("branches fold into their pattern with a masked count", {
  progress <- data.frame(
    name = c("x", "y", "y_8f3dd8ad0244cf0e", "y_1338a8f267f85771", "y_e6ba27f5e49c53ce"),
    progress = c("completed", "completed", "completed", "completed", "errored"),
    stringsAsFactors = FALSE
  )
  parents <- c(y_8f3dd8ad0244cf0e = "y", y_1338a8f267f85771 = "y", y_e6ba27f5e49c53ce = "y")
  out <- .format_run_summary(
    progress,
    list(list(target = "y_e6ba27f5e49c53ce", code = "E_join", counts = list(n_rows = 7, n_site_SiteZ = 9))),
    character(0),
    "d",
    allowlist = c("x", "y", "E_join", "n_rows"),
    parents = parents
  )
  expect_false(any(grepl("8f3dd8|1338a8|e6ba27|SiteZ", out)))
  expect_true(all(c("x: completed", "y: completed", "y: <5 branches completed", "y: <5 branches errored") %in% out))
  expect_true("  y: code=E_join n_rows=7 warnings: ?" %in% out)
})

test_that("targets and codes outside the allowlist are withheld and counted", {
  out <- .format_run_summary(
    data.frame(name = c("known", "from_data_X"), progress = c("completed", "completed")),
    list(list(target = "from_data_X", code = "CODE_FROM_DATA")),
    character(0),
    "d",
    allowlist = c("known")
  )
  expect_false(any(grepl("from_data_X|CODE_FROM_DATA", out)))
  expect_true("  ?: code=? warnings: ?" %in% out)
  expect_true(any(grepl("^withheld: 1 line", out)))
})

test_that("an empty allowlist (manifest unreadable) withholds every target line", {
  out <- .format_run_summary(
    data.frame(name = c("a", "b"), progress = c("completed", "errored")),
    list(),
    character(0),
    "d",
    allowlist = character(0)
  )
  expect_identical(out[1], "== targets ==")
  expect_false(any(grepl("^(a|b):", out)))
  expect_true(any(grepl("^withheld: 2 line", out)))
})

test_that("status lines must be '<allowlisted>: <integer or allowlisted>'", {
  allow <- c("prep", "completed", "n_rows", "TOY")
  out <- .schema_status_lines(
    c(
      "-- TOY --",
      "prep: completed",
      "  n_rows: 3",
      "n_rows: 120",
      "n_rows: <5",
      "site: SiteZ",
      "prep: SiteZ",
      "free text with value 99",
      "n_rows: 3, extra: 4"
    ),
    allow,
    5L
  )
  expect_identical(
    as.character(out),
    c(
      "-- TOY --",
      "prep: completed",
      "  n_rows: <5",
      "n_rows: 120",
      "n_rows: <5",
      rep("  [withheld: not in the output schema]", 4)
    )
  )
  expect_identical(
    attr(out, "withheld"),
    c("site: SiteZ", "prep: SiteZ", "free text with value 99", "n_rows: 3, extra: 4")
  )
})

# End to end: leak fixtures through the shim ---------------------------------------

make_leaky_project <- function(env = parent.frame()) {
  proj <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(proj, "data", "raw"), recursive = TRUE)
  write.csv(
    data.frame(site = c("SiteZ", "SiteQ", "SiteZ"), v = c(3, 7, 11)),
    file.path(proj, "data", "raw", "obs.csv"),
    row.names = FALSE
  )
  writeLines(
    c(
      "library(targets)",
      load_dctools_line,
      "list(",
      "  tar_target(obs_file, 'data/raw/obs.csv', format = 'file'),",
      "  tar_target(obs, utils::read.csv(obs_file)),",
      "  tar_target(sites, unique(obs$site)),",
      "  tar_target(per_site, nrow(obs[obs$site == sites, ]), pattern = map(sites)),",
      "  tar_target(run_status, c(",
      "    paste0('n_obs: ', nrow(obs)),",
      "    paste0('first_site: ', obs$site[1]),",
      "    paste('rows for', obs$site[2], 'are', 7)",
      "  ))",
      ")"
    ),
    file.path(proj, "_targets.R")
  )
  dir.create(file.path(proj, "code", "pipeline"), recursive = TRUE)
  writeLines(
    c(
      load_dctools_line,
      "quit(status = run_targets_safe(",
      "  commandArgs(trailingOnly = TRUE),",
      "  status_targets = c(LEAKY = 'run_status')",
      "), save = 'no')"
    ),
    file.path(proj, "code", "pipeline", "run_pipeline_safe.R")
  )
  proj
}

test_that("data-derived branch names, levels and free text never reach stdout", {
  skip_subprocess(c("processx", "targets", "callr", "jsonlite", "tidyselect"))
  proj <- make_leaky_project()
  res <- run_rscript(proj, "code/pipeline/run_pipeline_safe.R")
  expect_identical(res$status, 0L, info = res$stdout)
  expect_identical(res$stderr, "")
  lines <- strsplit(res$stdout, "\n")[[1]]
  expect_false(grepl("SiteZ|SiteQ|per_site_[0-9a-f]", res$stdout), info = res$stdout)
  expect_true(all(c(
    "per_site: completed",
    "per_site: <5 branches completed",
    "-- LEAKY --",
    "n_obs: <5"
  ) %in% lines), info = res$stdout)
  expect_identical(sum(lines == "  [withheld: not in the output schema]"), 2L)
  expect_true(any(grepl("^withheld: 2 line", lines)), info = res$stdout)
  # Positive control: the withheld lines reached the private log.
  dbg <- list.dirs(file.path(proj, "data", "processed", "debug"), recursive = FALSE)
  log <- readLines(file.path(dbg, "runner.log"))
  expect_true(any(grepl("first_site: SiteZ", log, fixed = TRUE)))
})
