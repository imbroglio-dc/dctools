test_that("capture_environment records both tiers, without machine or user names", {
  env <- capture_environment(c("stats", "jsonlite", "stats"))
  comp <- env$computational
  expect_identical(comp$r_version, paste(R.version$major, R.version$minor, sep = "."))
  expect_identical(comp$collate, Sys.getlocale("LC_COLLATE"))
  expect_identical(as.character(comp$rng_kind), RNGkind())
  expect_named(comp$threads, .thread_vars)
  expect_identical(
    vapply(comp$packages, function(p) p$package, ""),
    c("jsonlite", "stats")
  )
  expect_identical(
    comp$packages[[1]]$version,
    as.character(utils::packageVersion("jsonlite"))
  )
  expect_true(all(c("os", "locale", "library_paths", "installed") %in% names(env$full)))
  expect_named(env$full$os, c("sysname", "release", "version", "machine"))
  info <- Sys.info()
  flat <- unlist(env$full$os)
  expect_false(info[["nodename"]] %in% flat)
  expect_false(info[["user"]] %in% flat)
})

test_that("capture_environment(full = FALSE) skips the full tier; a missing package is NA", {
  env <- capture_environment("no.such.package.dctools", full = FALSE)
  expect_null(env$full)
  expect_true(is.na(env$computational$packages[[1]]$version))
  expect_error(capture_environment(NA_character_), "character vector")
})

test_that("the computational tier is stable across calls, so it does not invalidate targets", {
  expect_identical(
    capture_environment("jsonlite", full = FALSE)$computational,
    capture_environment("jsonlite", full = FALSE)$computational
  )
})

test_that("a fingerprint global invalidates only the targets that reference it", {
  skip_subprocess(c("callr", "targets"))
  proj <- withr::local_tempdir()
  writeLines(
    c(
      "library(targets)",
      "env_fingerprint <- list(r = Sys.getenv('FP_R', '4.6'))",
      "list(",
      "  tar_target(a, { env_fingerprint; 1 }),",
      "  tar_target(b, 2)",
      ")"
    ),
    file.path(proj, "_targets.R")
  )
  withr::with_dir(proj, {
    targets::tar_make(reporter = "silent")
    expect_length(targets::tar_outdated(reporter = "silent"), 0L)
    withr::with_envvar(c(FP_R = "4.7"), {
      expect_identical(targets::tar_outdated(reporter = "silent"), "a")
    })
  })
})
