skip_if_not_installed("jsonlite")

# A debug directory under a temp `data/processed/`, as the runner would set it.
local_debug_dir <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  d <- file.path(root, "data", "processed", "debug", "20260101-000000")
  dir.create(d, recursive = TRUE)
  d
}

read_status_json <- function(d, target) {
  jsonlite::fromJSON(
    file.path(d, paste0(target, ".status.json")),
    simplifyVector = FALSE
  )
}

test_that("abort_safe signals a classed error carrying code, counts, context, debug", {
  e <- tryCatch(
    abort_safe(
      "row EARLY-1 bad",
      code = "D5_norm",
      counts = list(n = 3),
      context = "plate",
      debug = data.frame(id = "EARLY-1"),
      class = "my_error"
    ),
    error = identity
  )
  expect_s3_class(e, c("my_error", "dctools_safe_error", "error"))
  expect_identical(e$code, "D5_norm")
  expect_identical(e$counts, list(n = 3L))
  expect_identical(e$context, "plate")
  expect_identical(e$debug$id, "EARLY-1")
  expect_match(conditionMessage(e), "row EARLY-1 bad", fixed = TRUE)
})

test_that("abort_safe requires an identifier-shaped code", {
  expect_error(abort_safe("x", code = "has space"), "code")
  expect_error(abort_safe("x", code = c("a", "b")), "code")
})

test_that("an error writes rds, txt and a PHI-free status sidecar, then re-raises", {
  d <- local_debug_dir()
  expect_error(
    capture_target_debug(
      abort_safe(
        "row EARLY-1 has value 99",
        code = "D5_norm",
        counts = list(n_rows = 3L),
        context = "plate",
        debug = data.frame(id = "EARLY-1", v = 99)
      ),
      "prep",
      d
    ),
    "row EARLY-1 has value 99",
    class = "dctools_safe_error"
  )
  for (f in c("prep.rds", "prep.txt", "prep.status.json")) {
    expect_true(file.exists(file.path(d, f)), info = f)
  }
  s <- read_status_json(d, "prep")
  expect_identical(s$target, "prep")
  expect_identical(s$status, "error")
  expect_identical(s$code, "D5_norm")
  expect_identical(s$counts, list(n_rows = 3L))
  expect_identical(s$context, "plate")
  expect_identical(s$n_warnings, 0L)
  status_txt <- paste(readLines(file.path(d, "prep.status.json")), collapse = "")
  expect_false(grepl("EARLY-1|99", status_txt))
  # Positive control: the detail kept out of the sidecar is in the bundle.
  txt <- paste(readLines(file.path(d, "prep.txt")), collapse = "\n")
  expect_match(txt, "row EARLY-1 has value 99", fixed = TRUE)
  expect_match(txt, "EARLY-1")
  bundle <- readRDS(file.path(d, "prep.rds"))
  expect_identical(bundle$debug$id, "EARLY-1")
})

test_that("the bundle .txt lists every row of a data-frame payload", {
  d <- local_debug_dir()
  df <- data.frame(id = sprintf("ID%03d", 1:150))
  expect_error(capture_target_debug(
    abort_safe("x", code = "C1", debug = df),
    "big",
    d
  ))
  txt <- readLines(file.path(d, "big.txt"))
  expect_true(all(sprintf("ID%03d", 1:150) %in% trimws(txt)))
})

test_that("a non-safe error records only its class in the sidecar", {
  d <- local_debug_dir()
  expect_error(
    capture_target_debug(stop("value EARLY-9 broke"), "t", d),
    "EARLY-9"
  )
  s <- read_status_json(d, "t")
  expect_null(s$code)
  expect_null(s$context)
  expect_length(s$counts, 0L)
  expect_true("simpleError" %in% unlist(s$class))
})

test_that("safe_class picks which condition class may fill the sidecar", {
  d <- local_debug_dir()
  e <- structure(
    class = c("prep_error", "error", "condition"),
    list(message = "m", call = NULL, code = "D1_x", counts = list(n = 2L))
  )
  expect_error(capture_target_debug(stop(e), "a", d, safe_class = "prep_error"))
  expect_identical(read_status_json(d, "a")$code, "D1_x")
  expect_error(capture_target_debug(stop(e), "b", d))
  expect_null(read_status_json(d, "b")$code)
})

test_that("sidecar fields failing their patterns are dropped", {
  d <- local_debug_dir()
  expect_error(capture_target_debug(
    abort_safe(
      "m",
      code = "C1",
      counts = list(ok = 2L, `bad name` = 3L, txt = "EARLY-1", na = NA, two = 1:2),
      context = "has space EARLY-1"
    ),
    "t",
    d
  ))
  s <- read_status_json(d, "t")
  expect_identical(s$counts, list(ok = 2L))
  expect_null(s$context)
})

test_that("warnings are muffled, written to file, and counted", {
  d <- local_debug_dir()
  expect_no_warning(
    res <- capture_target_debug(
      {
        warning("w1 EARLY-2")
        warning("w2")
        5
      },
      "w",
      d
    )
  )
  expect_identical(res, 5)
  expect_identical(
    readLines(file.path(d, "warnings_w.txt")),
    c("w1 EARLY-2", "w2")
  )
  s <- read_status_json(d, "w")
  expect_identical(s$status, "ok")
  expect_identical(s$n_warnings, 2L)
})

test_that("a clean run writes nothing to the debug directory", {
  d <- local_debug_dir()
  expect_identical(capture_target_debug(1 + 1, "clean", d), 2)
  expect_length(list.files(d), 0L)
})

test_that("warning then error: one sidecar, status error, n_warnings 1", {
  d <- local_debug_dir()
  expect_error(capture_target_debug(
    {
      warning("w")
      abort_safe("e", code = "C2")
    },
    "we",
    d
  ))
  expect_length(list.files(d, pattern = "status\\.json$"), 1L)
  s <- read_status_json(d, "we")
  expect_identical(s$status, "error")
  expect_identical(s$n_warnings, 1L)
})

test_that("no debug dir: plain evaluation, errors and warnings pass through", {
  withr::local_envvar(DCTOOLS_DEBUG_DIR = NA)
  expect_identical(capture_target_debug(3, "t"), 3)
  expect_warning(capture_target_debug(warning("ww"), "t"), "ww")
  expect_error(capture_target_debug(stop("ee"), "t"), "ee")
})

test_that("the debug dir defaults to DCTOOLS_DEBUG_DIR", {
  d <- local_debug_dir()
  withr::local_envvar(DCTOOLS_DEBUG_DIR = d)
  expect_identical(runner_debug_dir(), d)
  expect_error(capture_target_debug(stop("x"), "env"))
  expect_true(file.exists(file.path(d, "env.status.json")))
})

test_that("a debug dir outside the private root stops before writing", {
  root <- withr::local_tempdir()
  d <- file.path(root, "output", "debug")
  expect_error(
    capture_target_debug(1, "t", d),
    class = "dctools_unsafe_path_error"
  )
  expect_false(dir.exists(d))
  expect_error(
    capture_target_debug(1, "t", d, private_root = "output"),
    NA
  )
})

test_that("a target name that is not an identifier is refused", {
  d <- local_debug_dir()
  expect_error(capture_target_debug(1, "../x", d), "target_name")
})

test_that("a failing bundle write does not replace the original error", {
  d <- local_debug_dir()
  # A directory where the .rds should go makes saveRDS() fail.
  dir.create(file.path(d, "t.rds"))
  expect_error(capture_target_debug(stop("original"), "t", d), "original")
})

test_that("read_debug_status returns the sanitized sidecar, or NULL when absent", {
  d <- local_debug_dir()
  expect_null(read_debug_status(d, "none"))
  expect_null(read_debug_status("", "none"))
  expect_error(capture_target_debug(
    abort_safe("m", code = "D3_x", counts = list(n = 7L)),
    "p",
    d
  ))
  s <- read_debug_status(d, "p")
  expect_identical(s$code, "D3_x")
  expect_identical(s$counts, list(n = 7L))
  expect_identical(s$status, "error")
  # A tampered sidecar is re-sanitized on read.
  jsonlite::write_json(
    list(target = "p", status = "error", code = "EARLY 1", counts = list(`a b` = 1)),
    file.path(d, "p.status.json"),
    auto_unbox = TRUE
  )
  s <- read_debug_status(d, "p")
  expect_true(is.na(s$code))
  expect_length(s$counts, 0L)
  writeLines("{not json", file.path(d, "p.status.json"))
  expect_true(is.na(read_debug_status(d, "p")$code))
})

test_that("debug_error_sink writes numbered section bundles", {
  d <- local_debug_dir()
  sink <- debug_error_sink(d, "ev")
  sink(simpleError("one"))
  sink(simpleError("two"))
  expect_true(all(file.exists(file.path(
    d,
    c("ev_section01.txt", "ev_section02.rds")
  ))))
})

test_that("debug_error_sink refuses a non-private dir and no-ops on an empty one", {
  root <- withr::local_tempdir()
  expect_error(
    debug_error_sink(file.path(root, "out"), "ev")(simpleError("x")),
    class = "dctools_unsafe_path_error"
  )
  expect_null(debug_error_sink("", "ev")(simpleError("x")))
})
