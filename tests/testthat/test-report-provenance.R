test_that("record_count records the statement and function that computed the value", {
  env <- source_user_code(c(
    "build <- function(x) {",
    "  r <- dctools::create_report()",
    "  dctools::add_line(r, \"n: \",",
    "    dctools::record_count(r, \"n\", length(x)))",
    "  r",
    "}"
  ))
  r <- env$build(1:12)
  p <- r$provenance[["n"]]
  expect_identical(p$id, "n")
  expect_identical(basename(p$file), "user.R")
  expect_identical(c(p$line_start, p$line_end), c(3L, 4L))
  expect_match(p$code, "record_count(r, \"n\", length(x))", fixed = TRUE)
  expect_identical(p$function_name, "build")
  expect_identical(c(p$function_line_start, p$function_line_end), c(1L, 6L))
  expect_identical(p$target, NA_character_)
})

test_that("a suffixed duplicate id gets its own provenance", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::record_count(r, \"n\", 5)",
    "  dctools::record_count(r, \"n\", 6)",
    "  r",
    "}"
  ))
  r <- env$build()
  expect_identical(r$provenance[["n"]]$line_start, 3L)
  expect_identical(r$provenance[["n_2"]]$line_start, 4L)
})

test_that("every table cell carries the table call's provenance, also via add_tabulation", {
  env <- source_user_code(c(
    "build <- function(x) {",
    "  r <- dctools::create_report()",
    "  dctools::add_tabulation(r, \"grp\", x, labels_from_code = TRUE)",
    "  r",
    "}"
  ))
  r <- env$build(c("a", "a", "b"))
  expect_setequal(names(r$provenance), c("grp.1", "grp.2"))
  for (p in r$provenance) {
    expect_identical(basename(p$file), "user.R")
    expect_identical(p$line_start, 3L)
    expect_identical(p$function_name, "build")
  }
})

test_that("record_unprinted_count records provenance too", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::record_unprinted_count(r, \"~gap\", 2)",
    "  r",
    "}"
  ))
  expect_identical(env$build()$provenance[["~gap"]]$line_start, 3L)
})

test_that("a count recorded inside run_section keeps the line of its own statement", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::run_section(r, \"S\", {",
    "    dctools::add_line(r, dctools::record_count(r, \"n\", 9))",
    "  })",
    "  r",
    "}"
  ))
  p <- env$build()$provenance[["n"]]
  expect_identical(p$line_start, 4L)
  expect_identical(p$function_name, "build")
})

test_that("code with no source file records NA source fields, not a crash", {
  env <- new.env()
  eval(
    parse(
      text = "f <- function() { r <- dctools::create_report(); dctools::record_count(r, 'n', 1); r }",
      keep.source = TRUE
    ),
    env
  )
  p <- env$f()$provenance[["n"]]
  expect_identical(p$file, NA_character_)
  expect_identical(p$function_name, "f")
})
