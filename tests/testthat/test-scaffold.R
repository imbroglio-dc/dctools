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

test_that(".stamp_placeholders substitutes the project name", {
  root <- withr::local_tempdir()
  writeLines("# {{PROJECT_NAME}}", file.path(root, "README.md"))
  dctools:::.stamp_placeholders(root, "Sepsis Study")
  expect_equal(readLines(file.path(root, "README.md")), "# Sepsis Study")
})
