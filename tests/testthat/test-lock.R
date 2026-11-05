# Pure helpers ---------------------------------------------------------------------

lock_arg <- function(text, config = list(window = list(days = 28L)), declared = TRUE) {
  .lock_argument(str2lang(text), "x", 1L, config, declared)
}

test_that("arguments are classified as literal, config, reference or unresolved", {
  expect_identical(lock_arg("18")$value, 18)
  expect_identical(lock_arg("-0.5")$value, -0.5)
  expect_identical(lock_arg("'adults'")$value, "adults")
  expect_identical(lock_arg("c(TRUE, FALSE)")$value, c(TRUE, FALSE))
  expect_identical(lock_arg("NULL")$status, "literal")
  expect_identical(lock_arg("NA")$status, "literal")
  cfg <- lock_arg("config$window$days")
  expect_identical(cfg[c("status", "config_key", "value")], list(status = "config", config_key = "window.days", value = 28L))
  expect_identical(lock_arg("config[['window']][['days']]")$value, 28L)
  expect_identical(lock_arg("raw_admissions")$status, "reference")
  for (text in c("setdiff(a, b)", "18 + 1", "y ~ x", "function(x) x", "c(1, a)", "-Inf", "Inf")) {
    arg <- lock_arg(text)
    expect_identical(arg[c("status", "reason")], list(status = "unresolved", reason = "expression"), info = text)
    expect_identical(arg$expression, .deparse1(str2lang(text)), info = text)
  }
})

test_that("a config key is never guessed", {
  missing <- lock_arg("config$window$hours")
  expect_identical(missing[c("status", "reason", "config_key")],
                   list(status = "unresolved", reason = "config key not found", config_key = "window.hours"))
  undeclared <- lock_arg("config$window$days", config = NULL, declared = FALSE)
  expect_identical(undeclared$reason, "no config file declared")
  expect_null(undeclared$value)
  expect_identical(lock_arg("settings$window$days")$status, "unresolved")
})

test_that("only a call to a function by name is read", {
  expect_identical(.lock_call("build(a, k = 2)", NULL, FALSE)$call, "build")
  expect_identical(.lock_call("stats::glm(y ~ x, data = d)", NULL, FALSE)$call, "stats::glm")
  for (cmd in c("{\n  a + 1\n}", "a %>% f()", "a + b", "if (x) a else b", "\"data/raw/x.csv\"", "(function(x) x)(a)")) {
    expect_identical(.lock_call(cmd, NULL, FALSE)$call_status, "unsupported", info = cmd)
  }
  empty <- .lock_call("f(a, )", NULL, FALSE)$arguments[[2]]
  expect_identical(empty[c("status", "reason")], list(status = "unresolved", reason = "empty argument"))
})

# End to end on a synthetic targets project ------------------------------------------

skip_lock_fixture <- function() {
  skip_on_cran()
  skip_if_not_installed("targets")
  skip_if_not_installed("callr")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("yaml")
}

lock_targets_script <- function(min_age = 18) {
  c(
    "library(targets)",
    "build_cohort <- function(...) 1",
    "list(",
    "  tar_target(raw_admissions, 1),",
    "  tar_target(",
    "    cohort,",
    sprintf("    build_cohort(raw_admissions, min_age = %s, window_days = config$window$days,", min_age),
    "      exclude = setdiff(1:3, 2), label = 'adults', flags = c(TRUE, FALSE), cut = -0.5)",
    "  ),",
    "  tar_target(model, {",
    "    cohort + 1",
    "  }),",
    "  targets::tar_target(fit, stats::glm(y ~ x, family = binomial(), data = cohort))",
    ")"
  )
}

lock_fixture <- function(env = parent.frame()) {
  proj <- withr::local_tempdir(.local_envir = env)
  writeLines(lock_targets_script(), file.path(proj, "_targets.R"))
  dir.create(file.path(proj, "config"))
  writeLines(c("window:", "  days: 28"), file.path(proj, "config", "analysis.yml"))
  git <- function(...) system2("git", c("-C", proj, ...), stdout = FALSE, stderr = FALSE)
  git("init", "-q")
  git("-c", "user.name=t", "-c", "user.email=t@t", "add", "-A")
  git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init")
  proj
}

lock_links <- function() {
  data.frame(
    decision_id = c("D3", "D1", "D2", "D4", "D5"),
    decision_status = "approved",
    target = c("cohort", "model", "fit", "gone", NA),
    role = "args",
    stringsAsFactors = FALSE
  )
}

entry_of <- function(lock, id) Filter(function(e) identical(e$decision_id, id), lock$entries)[[1]]

test_that("the lock records each linked target's call, arguments and location", {
  skip_lock_fixture()
  proj <- lock_fixture()
  lock <- computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj)
  expect_identical(lock$lock_schema_version, 1L)
  expect_identical(vapply(lock$entries, `[[`, "", "decision_id"), c("D1", "D2", "D3", "D4", "D5"))

  cohort <- entry_of(lock, "D3")
  expect_identical(cohort$location, list(file = "_targets.R", line = 5L))
  expect_identical(cohort$call, "build_cohort")
  args <- cohort$arguments
  expect_identical(vapply(args, `[[`, "", "status"),
                   c("reference", "literal", "config", "unresolved", "literal", "literal", "literal"))
  expect_null(args[[1]]$name)
  expect_identical(args[[2]][c("name", "value")], list(name = "min_age", value = 18))
  expect_identical(args[[3]]$value, 28L)
  expect_identical(args[[4]]$expression, "setdiff(1:3, 2)")

  expect_identical(entry_of(lock, "D1")$call_status, "unsupported")
  fit <- entry_of(lock, "D2")
  expect_identical(fit$call, "stats::glm")
  expect_identical(fit$location$line, 13L)
  expect_identical(vapply(fit$arguments, `[[`, "", "status"), c("unresolved", "unresolved", "reference"))
  expect_identical(entry_of(lock, "D4")$call_status, "missing_target")
  expect_null(entry_of(lock, "D5")$target)
  expect_identical(entry_of(lock, "D5")$call_status, "no_target")
})

test_that("regenerating gives identical bytes, and the check passes", {
  skip_lock_fixture()
  proj <- lock_fixture()
  path <- write_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj)
  first <- readBin(path, "raw", file.size(path))
  write_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj)
  expect_identical(readBin(path, "raw", file.size(path)), first)
  expect_true(check_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj))
  text <- rawToChar(first)
  for (absent in c("dctools_version", "timestamp", "run_id", "sha")) {
    expect_false(grepl(absent, text, fixed = TRUE), info = absent)
  }
})

test_that("a hand-edited lock fails the regeneration check", {
  skip_lock_fixture()
  proj <- lock_fixture()
  path <- write_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj)
  text <- readLines(path)
  edited <- sub('"value": 18$', '"value": 21', text)
  expect_false(identical(edited, text))
  writeLines(edited, path)
  err <- expect_error(
    check_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj),
    class = "dctools_lock_mismatch"
  )
  expect_match(conditionMessage(err), "D3 / cohort / min_age: changed: 21 -> 18", fixed = TRUE)

  # Same content, different bytes: still a failure.
  write_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj)
  writeLines(c(readLines(path), ""), path)
  expect_error(
    check_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj),
    "different bytes", class = "dctools_lock_mismatch"
  )
  unlink(path)
  expect_error(
    check_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj),
    "no committed lock", class = "dctools_lock_mismatch"
  )
})

test_that("a stale lock fails the check after the code changes", {
  skip_lock_fixture()
  proj <- lock_fixture()
  write_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj)
  writeLines(lock_targets_script(min_age = 21), file.path(proj, "_targets.R"))
  expect_error(
    check_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj),
    "min_age: changed: 18 -> 21", class = "dctools_lock_mismatch"
  )
})

test_that("the review table shows a changed argument against the approved baseline", {
  skip_lock_fixture()
  proj <- lock_fixture()
  write_computation_lock(lock_links(), config = "config/analysis.yml", script = "_targets.R", repo = proj)
  system2("git", c("-C", proj, "-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"), stdout = FALSE)
  system2("git", c("-C", proj, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "lock"), stdout = FALSE)
  system2("git", c("-C", proj, "tag", "plan-v1"), stdout = FALSE)
  baseline <- read_computation_lock(ref = "plan-v1", repo = proj)

  writeLines(lock_targets_script(min_age = 21), file.path(proj, "_targets.R"))
  links <- lock_links()[lock_links()$decision_id != "D1", ]
  now <- computation_lock(links, config = "config/analysis.yml", script = "_targets.R", repo = proj)
  table <- lock_review_table(now, baseline = baseline)
  expect_identical(table[1], "| Decision | Target | Location | Setting | Value or expression | Status | Change |")
  expect_true("| D3 | cohort | _targets.R:5 | min_age | 21 | literal | changed: 18 -> 21 |" %in% table)
  expect_true("| D3 | cohort | _targets.R:5 | window_days | 28 | config |  |" %in% table)
  expect_true("| D3 | cohort | _targets.R:5 | exclude | setdiff(1:3, 2) (expression) | unresolved |  |" %in% table)
  expect_true("| D3 | cohort | _targets.R:5 | #1 | raw_admissions | reference |  |" %in% table)
  expect_true(any(grepl("^\\| D1 \\| model \\| .* \\| removed \\|$", table)))
  expect_true("| D5 | - | unknown | - |  | no_target |  |" %in% table)

  # Without a baseline the change column is empty.
  expect_false(any(grepl("changed|added|removed", lock_review_table(now))))
})
