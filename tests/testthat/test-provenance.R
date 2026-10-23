# Probe files: lib.R stands in for a dctools function that records provenance;
# user.R is project code calling it.
write_probe_files <- function(dir) {
  writeLines(
    c(
      "grab <- function(expr) {",
      "  call <- sys.call()",
      "  env <- parent.frame()",
      "  force(expr)",
      "  dctools:::.capture_provenance(call, env)",
      "}"
    ),
    file.path(dir, "lib.R")
  )
  writeLines(
    c(
      "user_fn <- function() {",
      "  y <- 1",
      "  grab(",
      "    y + 1",
      "  )",
      "}",
      "user_nested <- function(wrap) {",
      "  wrap({",
      "    grab(3)",
      "  })",
      "}"
    ),
    file.path(dir, "user.R")
  )
}

source_probe <- function(dir, keep_source = TRUE) {
  env <- new.env()
  source(file.path(dir, "lib.R"), local = env, keep.source = keep_source)
  source(file.path(dir, "user.R"), local = env, keep.source = keep_source)
  env
}

test_that(".capture_provenance names the calling statement and its function", {
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  p <- source_probe(dir)$user_fn()
  expect_identical(basename(p$file), "user.R")
  expect_true(grepl("^(/|[A-Za-z]:)", p$file))
  expect_identical(c(p$line_start, p$line_end), c(3L, 5L))
  expect_identical(p$code, "  grab(\n    y + 1\n  )")
  expect_identical(p$function_name, "user_fn")
  expect_identical(basename(p$function_file), "user.R")
  expect_identical(c(p$function_line_start, p$function_line_end), c(1L, 6L))
  expect_identical(p$target, NA_character_)
})

test_that("a call inside a code block passed to another function keeps its own line and function", {
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  p <- source_probe(dir)$user_nested(function(code) force(code))
  expect_identical(c(p$line_start, p$line_end), c(9L, 9L))
  expect_identical(p$code, "    grab(3)")
  expect_identical(p$function_name, "user_nested")
  expect_identical(c(p$function_line_start, p$function_line_end), c(7L, 11L))
})

test_that("without keep.source the source fields are NA, not guessed", {
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  p <- source_probe(dir, keep_source = FALSE)$user_fn()
  expect_identical(p$file, NA_character_)
  expect_identical(p$line_start, NA_integer_)
  expect_identical(p$line_end, NA_integer_)
  expect_identical(p$code, NA_character_)
  expect_identical(p$function_file, NA_character_)
  expect_identical(p$function_line_start, NA_integer_)
  expect_identical(p$function_line_end, NA_integer_)
  expect_identical(p$function_name, "user_fn")
})

test_that("code with no source file (eval of parsed text) gives NA source fields", {
  env <- new.env()
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  source(file.path(dir, "lib.R"), local = env, keep.source = TRUE)
  eval(parse(text = "f <- function() grab(1)", keep.source = TRUE), env)
  p <- env$f()
  expect_identical(p$file, NA_character_)
  expect_identical(p$line_start, NA_integer_)
  expect_identical(p$line_end, NA_integer_)
  expect_identical(p$code, NA_character_)
  expect_identical(p$function_file, NA_character_)
  expect_identical(p$function_line_start, NA_integer_)
  expect_identical(p$function_line_end, NA_integer_)
  expect_identical(p$function_name, "f")
})

test_that("source references survive Rscript when sourced with keep.source = TRUE", {
  skip_subprocess()
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  writeLines(
    c(
      load_dctools_line,
      "source('lib.R', keep.source = TRUE)",
      "source('user.R', keep.source = TRUE)",
      "p <- user_fn()",
      "cat(basename(p$file), grepl('^(/|[A-Za-z]:)', p$file), p$line_start,",
      "  p$line_end, p$function_name, sep = '|')"
    ),
    file.path(dir, "probe.R")
  )
  res <- run_rscript(dir, "probe.R")
  expect_identical(res$stdout, "user.R|TRUE|3|5|user_fn", info = res$stderr)
})

test_that("source references and the target name survive a targets run", {
  skip_subprocess(c("processx", "targets", "callr"))
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  writeLines(
    c(
      "library(targets)",
      load_dctools_line,
      "source('lib.R', keep.source = TRUE)",
      "source('user.R', keep.source = TRUE)",
      "list(tar_target(probe, user_fn()))"
    ),
    file.path(dir, "_targets.R")
  )
  writeLines(
    c(
      "targets::tar_make(reporter = 'silent')",
      "p <- targets::tar_read(probe)",
      "cat(basename(p$file), p$line_start, p$line_end, p$function_name,",
      "  p$target, sep = '|')"
    ),
    file.path(dir, "run.R")
  )
  res <- run_rscript(dir, "run.R")
  expect_identical(res$stdout, "user.R|3|5|user_fn|probe", info = res$stderr)
})
