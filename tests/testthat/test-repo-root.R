# The repository root and the renv.lock location, for projects that are not at
# the root of their repository and for repositories git reports in another path
# form than R (Windows mapped network drives: git gives //server/share/...,
# R gives S:/...).

test_that(".git_root builds the root from R's own path, never from --show-toplevel", {
  dir <- withr::local_tempdir()
  sub <- file.path(dir, "project")
  dir.create(sub)
  calls <- character(0)
  testthat::local_mocked_bindings(
    .git = function(repo, args) {
      calls <<- c(calls, paste(args, collapse = " "))
      if (identical(args, c("rev-parse", "--show-toplevel"))) {
        return("//server/share/somewhere-else")
      }
      if (identical(args, c("rev-parse", "--show-cdup"))) {
        return(if (normalizePath(repo, winslash = "/") == normalizePath(sub, winslash = "/")) "../" else character(0))
      }
      stop("unexpected git call")
    }
  )
  expect_identical(.git_root(sub), normalizePath(dir, winslash = "/"))
  expect_identical(.git_root(dir), normalizePath(dir, winslash = "/"))
  expect_false(any(grepl("show-toplevel", calls)))
})

test_that(".git_root matches the form of the working directory in a real repository", {
  skip_if(Sys.which("git") == "")
  dir <- withr::local_tempdir()
  system2("git", c("-C", dir, "init", "-q"))
  sub <- file.path(dir, "a", "b")
  dir.create(sub, recursive = TRUE)
  root <- withr::with_dir(sub, .git_root("."))
  expect_identical(root, normalizePath(dir, winslash = "/"))
  here <- withr::with_dir(sub, normalizePath(getwd(), winslash = "/"))
  expect_true(startsWith(here, paste0(root, "/")))
  expect_identical(.repo_relative(file.path(here, "x.R"), root), "a/b/x.R")
})

test_that(".renv_lock_path finds the nearest renv.lock up to the repository root", {
  skip_if(Sys.which("git") == "")
  dir <- withr::local_tempdir()
  system2("git", c("-C", dir, "init", "-q"))
  proj <- file.path(dir, "project")
  dir.create(file.path(proj, "code"), recursive = TRUE)
  root <- normalizePath(dir, winslash = "/")

  expect_true(is.na(withr::with_dir(proj, .renv_lock_path("."))))
  writeLines("{}", file.path(dir, "renv.lock"))
  expect_identical(withr::with_dir(proj, .renv_lock_path(".")), file.path(root, "renv.lock"))
  writeLines("{}", file.path(proj, "renv.lock"))
  expect_identical(withr::with_dir(proj, .renv_lock_path(".")), file.path(root, "project", "renv.lock"))
  # From a folder below the project, the project's lock is still the nearest.
  expect_identical(
    withr::with_dir(file.path(proj, "code"), .renv_lock_path(".")),
    file.path(root, "project", "renv.lock")
  )
})

test_that("a project in a subfolder of its repository audits clean, with repo-relative paths", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture(subdir = TRUE)
  ledger <- jsonlite::read_json(fixture_ledger_path(proj))
  expect_identical(ledger$code$renv_lock, "project/renv.lock")
  expect_true(ledger$code$clean)
  files <- unique(vapply(ledger$provenance, function(p) p$file, ""))
  expect_identical(files, "project/R/evidence.R")

  result <- audit_copy(proj)
  expect_identical(status_of(result, "C1"), "PASS")
  expect_identical(status_of(result, "C11"), "PASS")
  expect_identical(attr(result, "verdict"), "PASS")
})

test_that("C11 still finds renv.lock in a ledger written before the renv_lock field", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture(subdir = TRUE)
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$code$renv_lock <- NULL
    l
  })
  expect_identical(status_of(audit_copy(proj), "C11"), "PASS")
})
