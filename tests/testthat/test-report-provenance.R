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
  expect_identical(p$line_start, NA_integer_)
  expect_identical(p$line_end, NA_integer_)
  expect_identical(p$code, NA_character_)
  expect_identical(p$function_name, "f")
})

test_that("a count passed through a wrapper in another file is attributed to the caller", {
  env <- new.env()
  source_user_code(
    c(
      "note <- function(r, ...) {",
      "  x <- 1",
      "  dctools::add_line(r, \"pad \", ...)",
      "}"
    ),
    env = env
  )
  # A second file: source_user_code writes user.R in a fresh temp dir each call.
  source_user_code(
    c(
      "build <- function() {",
      "  r <- dctools::create_report()",
      "  note(r, dctools::record_count(r, \"n\", 9))",
      "  r",
      "}"
    ),
    env = env
  )
  p <- env$build()$provenance[["n"]]
  expect_identical(basename(p$file), "user.R")
  expect_identical(p$line_start, 3L)
  expect_match(p$code, "note(r, dctools::record_count", fixed = TRUE)
  expect_identical(p$function_name, "build")
  expect_identical(c(p$function_line_start, p$function_line_end), c(1L, 5L))
})

test_that("a caller without source references is never given its caller's lines", {
  env <- new.env()
  eval(
    parse(
      text = c(
        "inner <- function() {",
        "  r <- dctools::create_report()",
        "  dctools::add_line(r, dctools::record_count(r, 'n', 1))",
        "  r",
        "}"
      ),
      keep.source = FALSE
    ),
    env
  )
  source_user_code(
    c(
      "outer <- function() {",
      "  inner()",
      "}"
    ),
    env = env
  )
  p <- env$outer()$provenance[["n"]]
  expect_identical(p$file, NA_character_)
  expect_identical(p$line_start, NA_integer_)
  expect_identical(p$line_end, NA_integer_)
  expect_identical(p$code, NA_character_)
  expect_identical(p$function_name, "inner")
})

test_that(".enclosing_srcref selects the statement made from the caller's own frame", {
  env <- source_user_code(c(
    "caller <- function() {",
    "  x <- 1",
    "  list(probe())",
    "}",
    "probe <- function() {",
    "  dctools:::.enclosing_srcref(dctools:::.frame_of(parent.frame()))",
    "}"
  ))
  srcref <- env$caller()[[1]]
  expect_identical(as.integer(srcref)[c(1, 3)], c(3L, 3L))

  # The caller itself has no source references: nothing is guessed.
  bare <- new.env(parent = env)
  eval(
    parse(text = "caller2 <- function() list(probe())", keep.source = FALSE),
    bare
  )
  expect_null(bare$caller2()[[1]])
})

test_that("a count in an anonymous function is named so, a nested helper by its name", {
  env <- source_user_code(c(
    "helper <- function(r, v) dctools::record_count(r, 'h', v)",
    "build <- function(d) {",
    "  r <- dctools::create_report()",
    "  lapply(c('a', 'b'), function(g) dctools::record_count(r, paste0('n_', g), sum(d == g)))",
    "  add <- function(id, v) dctools::record_count(r, id, v)",
    "  add('n', length(d))",
    "  lapply(list(r), helper, v = 9)",
    "  r",
    "}"
  ))
  p <- env$build(c("a", "b", "b"))$provenance
  expect_identical(p$n_a$function_name, "(anonymous function)")
  expect_identical(
    c(p$n_a$function_line_start, p$n_a$function_line_end),
    c(4L, 4L)
  )
  expect_identical(p$n$function_name, "add")
  # Called as lapply's FUN, but defined as helper().
  expect_identical(p$h$function_name, "helper")
})

test_that("a count forced later through a closure gets NA lines, not the forcing line", {
  env <- source_user_code(c(
    "build <- function(d) {",
    "  r <- dctools::create_report()",
    "  keep <- function(val) function() val",
    "  getter <- keep(dctools::record_count(r, 'n', length(d)))",
    "  dctools::add_line(r, 'n = ', getter())",
    "  r",
    "}"
  ))
  p <- env$build(1:7)$provenance$n
  expect_identical(p$line_start, NA_integer_)
  expect_identical(p$line_end, NA_integer_)
  expect_identical(p$code, NA_character_)
})

test_that("the same id and value recorded at two sites keeps both provenances", {
  env <- source_user_code(c(
    "build <- function(d) {",
    "  r <- dctools::create_report()",
    "  dctools::add_line(r, 'n = ', dctools::record_count(r, 'n', length(d)))",
    "  dctools::record_count(r, 'n', 5)",
    "  for (i in 1:2) dctools::record_count(r, 'm', 3)",
    "  r",
    "}"
  ))
  r <- env$build(1:5)
  expect_identical(r$provenance$n$line_start, 3L)
  expect_identical(r$provenance$n_2$line_start, 4L)
  expect_identical(unname(r$counts[c("n", "n_2")]), c(5, 5))
  # The same site recording the same value again reuses its id.
  expect_false("m_2" %in% names(r$counts))
})
