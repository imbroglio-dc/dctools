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

test_that(".write_state_stack scaffolds memos/ and a workflow-feedback stub", {
  root <- withr::local_tempdir()
  dctools:::.write_state_stack(root)
  expect_true(dir.exists(file.path(root, "memos")))
  expect_true(file.exists(file.path(root, "memos", ".gitkeep")))
  wf <- file.path(root, "workflow-feedback.md")
  expect_true(file.exists(wf))
  expect_match(paste(readLines(wf), collapse = "\n"), "Workflow feedback",
    fixed = TRUE
  )
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

  # State stack (Gap 1)
  expect_true(dir.exists(file.path(dest, "memos")))
  expect_true(file.exists(file.path(dest, "workflow-feedback.md")))

  # Old-world content is gone (Gap 2): the router + kernel own these now
  expect_false(dir.exists(file.path(dest, ".claude")))
  expect_false(file.exists(file.path(dest, "CLAUDE.md")))
  expect_false(file.exists(file.path(dest, "_setup.R")))
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
