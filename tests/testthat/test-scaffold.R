test_that("make_file_dirs builds the skeleton with markers", {
  root <- withr::local_tempdir()
  make_file_dirs(root)
  expect_true(dir.exists(file.path(root, "code", "functions")))
  expect_true(dir.exists(file.path(root, "data", "raw")))
  expect_true(dir.exists(file.path(root, "output", "figures")))
  expect_true(file.exists(file.path(root, "code", "functions", ".gitkeep")))
  gi <- readLines(file.path(root, ".gitignore"))
  expect_true(any(grepl("scratch/", gi, fixed = TRUE)))
})

test_that("make_file_dirs honours the extra argument and is idempotent", {
  root <- withr::local_tempdir()
  make_file_dirs(root, extra = "reports")
  expect_true(dir.exists(file.path(root, "reports")))
  expect_no_error(make_file_dirs(root)) # second run must not fail
})

test_that(".write_state_stack scaffolds memos/ only, no per-project feedback log", {
  root <- withr::local_tempdir()
  dctools:::.write_state_stack(root)
  expect_true(dir.exists(file.path(root, "memos")))
  expect_true(file.exists(file.path(root, "memos", ".gitkeep")))
  expect_false(file.exists(file.path(root, "workflow-feedback.md")))
})

test_that("analysis .gitignore keeps a README in each private data zone", {
  parent <- withr::local_tempdir()
  dest <- create_project("zoneproj", path = parent, type = "analysis", git = FALSE)
  gi <- readLines(file.path(dest, ".gitignore"))
  expect_true("!data/raw/README.md" %in% gi)
  expect_true("!data/processed/README.md" %in% gi)

  skip_if(Sys.which("git") == "", "git not available")
  system2("git", c("-C", dest, "init", "-q"))
  writeLines("x", file.path(dest, "data", "raw", "README.md"))
  writeLines("x", file.path(dest, "data", "raw", "secret.csv"))
  ignored <- function(p) {
    system2("git", c("-C", dest, "check-ignore", "-q", p)) == 0
  }
  expect_false(ignored("data/raw/README.md"))
  expect_true(ignored("data/raw/secret.csv"))
})

test_that("create_project(type = 'analysis') scaffolds offline, no network clone", {
  parent <- withr::local_tempdir()
  # No network: a green run here proves the clone dependency is gone.
  dest <- create_project("demoproj", path = parent, type = "analysis", git = FALSE)

  # Directory skeleton (delegated to make_file_dirs)
  expect_true(dir.exists(file.path(dest, "code", "functions")))
  expect_true(dir.exists(file.path(dest, "data", "raw")))
  expect_true(dir.exists(file.path(dest, "output", "tables")))
  expect_true(dir.exists(file.path(dest, "tests", "testthat")))

  # Mechanics reproduced directly (not cloned)
  expect_true(file.exists(file.path(dest, ".Rprofile")))
  expect_true(file.exists(file.path(dest, "demoproj.Rproj")))
  gi <- paste(readLines(file.path(dest, ".gitignore")), collapse = "\n")
  expect_match(gi, "data/raw/", fixed = TRUE) # PHI defense travels with the repo
  expect_match(gi, "scratch/", fixed = TRUE)

  # README stamped, no leftover placeholder
  readme <- paste(readLines(file.path(dest, "README.md")), collapse = "\n")
  expect_match(readme, "demoproj", fixed = TRUE)
  expect_false(grepl("{{PROJECT_NAME}}", readme, fixed = TRUE))

  # R version pinned in Reproducibility, independent of whether renv::init()
  # or an LLM session was ever involved
  expect_match(readme, paste0("R version: `", getRversion(), "`"), fixed = TRUE)

  # State stack: memos/
  expect_true(dir.exists(file.path(dest, "memos")))

  # Old-world content is gone (Gap 2): the router + kernel own these now
  expect_false(dir.exists(file.path(dest, ".claude")))
  expect_false(file.exists(file.path(dest, "CLAUDE.md")))
  expect_false(file.exists(file.path(dest, "_setup.R")))
})

test_that("create_project(type = 'analysis') initialises renv, whose lockfile pins R", {
  parent <- withr::local_tempdir()
  dest <- create_project("renvproj", path = parent, type = "analysis", git = FALSE)

  # The R version pin is renv.lock (checked by renv) + the README line; no
  # .Rversion, which no tool reads.
  expect_false(file.exists(file.path(dest, ".Rversion")))

  # .Rprofile stays our guarded activation line, not renv::init()'s bare one
  rprofile <- paste(readLines(file.path(dest, ".Rprofile")), collapse = "\n")
  expect_match(rprofile, "if (file.exists", fixed = TRUE)

  skip_if_not_installed("renv")
  expect_true(file.exists(file.path(dest, "renv", "activate.R")))
  expect_true(file.exists(file.path(dest, "renv.lock")))
  lock <- renv::lockfile_read(file.path(dest, "renv.lock"))
  expect_identical(lock$R$Version, as.character(getRversion()))
})

test_that("create_project(type = 'analysis', targets = TRUE) writes a pipeline stub", {
  parent <- withr::local_tempdir()
  dest <- create_project("tproj", path = parent, type = "analysis",
    targets = TRUE, git = FALSE
  )
  tf <- file.path(dest, "_targets.R")
  expect_true(file.exists(tf))
  expect_match(paste(readLines(tf), collapse = "\n"), "tar_make", fixed = TRUE)
})

test_that("create_project aborts on a non-empty destination", {
  parent <- withr::local_tempdir()
  create_project("dup", path = parent, type = "analysis", git = FALSE)
  expect_error(
    create_project("dup", path = parent, type = "analysis", git = FALSE),
    "already exists"
  )
})
