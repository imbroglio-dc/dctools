test_that(".bare_numbers skips placeholders and identifier-like tokens", {
  expect_identical(.bare_numbers("n = 12 of {{total}}"), "12")
  expect_identical(.bare_numbers("J7, death_28d and D13"), character(0))
  expect_identical(.bare_numbers("{{pct:a.1,a.2}}"), character(0))
  expect_setequal(.bare_numbers("1.5 and 3 and 3"), c("1.5", "3"))
  expect_identical(.bare_numbers(NA_character_), character(0))
})

guard_lines <- c(
  "build <- function(x, k) {",
  "  r <- dctools::create_report()",
  "  dctools::add_line(r, \"max: \", max(x))",
  "  dctools::add_line(r, \"within 48 hours\")",
  "  dctools::add_line(r, \"J7 and death_28d\")",
  "  dctools::add_line(r, \"n = \", dctools::record_count(r, \"n\", length(x)))",
  "  dctools::add_literal_line(r, paste(\"window\", k))",
  "  dctools::add_data_frame(r, data.frame(v = x[1:2]))",
  "  dctools::run_section(r, paste(\"Day\", k), dctools::add_line(r, \"ok\"))",
  "  dctools::run_section(r, \"Day 7\", dctools::add_line(r, \"ok\"))",
  "  dctools::add_tabulation(r, \"flag\", c(0, 1, 1))",
  "  r",
  "}"
)

test_that("numbers not written in the code of the adding call are flagged by location only", {
  env <- source_user_code(guard_lines)
  r <- env$build(c(31, 57, 64), k = 3)
  lines <- vapply(r$unprovenanced, function(p) p$line_start, integer(1))
  # max(x) (line 3), "window 3" (7), the data frame (8), the "Day 3" heading (9)
  expect_identical(sort(lines), c(3L, 7L, 8L, 9L))
  # Only the location is recorded: no text field holds the printed numbers.
  text_fields <- unlist(lapply(r$unprovenanced, function(p) {
    c(basename(p$file), p$code, p$function_name)
  }))
  expect_false(any(grepl("64|31|57|window 3|Day 3", text_fields)))
  expect_identical(basename(r$unprovenanced[[1]]$file), "user.R")
})

test_that("constants written in the code, placeholders and table labels pass", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::add_line(r, \"within 48 hours\")",
    "  dctools::run_section(r, \"Day 7\", dctools::add_line(r, \"n = \", dctools::record_count(r, \"n\", 40)))",
    "  dctools::add_tabulation(r, \"flag\", c(0, 1, 1))",
    "  r",
    "}"
  ))
  expect_length(env$build()$unprovenanced, 0L)
})

test_that("a constant in an add_line that is itself an argument is not flagged", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::run_section(r, \"S\", dctools::add_line(r, \"within 48 hours\"))",
    "  r",
    "}"
  ))
  expect_length(env$build()$unprovenanced, 0L)
})

test_that("a caller with no source file gets NA location, not the forcing code's", {
  e <- new.env()
  eval(
    parse(
      text = c(
        "build <- function(x) {",
        "  r <- dctools::create_report()",
        "  dctools::run_section(r, \"S\", dctools::add_line(r, \"v \", x))",
        "  dctools::run_section(r, \"T\", dctools::record_count(r, \"n\", x))",
        "  r",
        "}"
      ),
      keep.source = TRUE
    ),
    e
  )
  r <- e$build(31)
  expect_length(r$unprovenanced, 1L)
  p <- r$unprovenanced[[1]]
  expect_identical(p$file, NA_character_)
  expect_identical(p$line_start, NA_integer_)
  expect_identical(p$line_end, NA_integer_)
  expect_identical(p$code, NA_character_)
  expect_identical(p$function_name, "build")
  counts <- r$provenance[["n"]]
  expect_identical(counts$file, NA_character_)
  expect_identical(counts$code, NA_character_)
  expect_identical(counts$line_start, NA_integer_)
})
