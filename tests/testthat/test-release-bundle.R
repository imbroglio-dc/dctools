release_requirements <- function(...) {
  checks <- list(
    contract_checked = "required",
    execution_recorded = "required",
    extraction_rechecked = "optional",
    render_checked = "optional",
    reproduced = "optional",
    disclosure_approved = "required",
    known_answer_checked = "required",
    diagnostics_checked = "not_applicable"
  )
  overrides <- list(...)
  checks[names(overrides)] <- overrides
  list(
    requirements_schema_version = 1L,
    release_approver = "owner-login",
    release_scope = "Synthetic counts",
    audit_plan = "none",
    audit_rationale = "Synthetic fixture.",
    checks = Filter(Negate(is.null), checks),
    not_applicable_reasons = list(diagnostics_checked = "No model is fitted."),
    known_answer_tests = list("tests/known"),
    deliverables = list("output/record.html")
  )
}

release_item <- function(id, disposition = "unresolved", relevant = TRUE) {
  list(id = id, title = paste("Item", id), owner = "owner-login",
       disposition = disposition, relevant_to_release = relevant)
}

# Commits the release inputs as A and reruns the pipeline from A, as a
# release candidate run would (the engine is mocked by the caller).
release_fixture <- function(requirements = release_requirements(), items = list(),
                            known_test = "expect_true(TRUE)", lock = TRUE, env = parent.frame()) {
  proj <- copy_fixture(env = env)
  dir.create(file.path(proj, "contracts"))
  dir.create(file.path(proj, "records"))
  dir.create(file.path(proj, "tests", "known"), recursive = TRUE)
  yaml::write_yaml(requirements, file.path(proj, "contracts", "requirements.yml"))
  yaml::write_yaml(list(unresolved_schema_version = 1L, items = items), file.path(proj, "records", "unresolved.yml"))
  writeLines(sprintf("test_that('known answer', { %s })", known_test), file.path(proj, "tests", "known", "test-known.R"))
  if (lock) {
    write_computation_lock(fixture_links(), script = "_targets.R", repo = proj)
  }
  git <- function(...) system2("git", c("-C", proj, ...), stdout = TRUE, stderr = TRUE)
  git("add", "-A", "--", "contracts", "records", "tests")
  git("commit", "-q", "-m", "release-inputs")
  # The release candidate run, from A with a fresh store (architecture 10.1):
  # every target is rebuilt, the record's stamp names A, and the ledger is
  # written afresh.
  unlink(file.path(proj, "_targets"), recursive = TRUE)
  unlink(file.path(proj, "output", "record.html"))
  before <- withr::with_dir(
    proj,
    .inputs_before("_targets.R", documents = "decisions.yml", input_dirs = "data/raw")
  )
  res <- run_rscript(proj, "run.R", env = c(DCTOOLS_RUN_ID = fixture_run_id, FIXTURE_FAIL = "0"))
  if (res$status != 0L) {
    stop("release fixture run failed: ", res$stderr)
  }
  withr::with_dir(proj, write_run_ledger(
    path = "docs/runs",
    run_id = fixture_run_id,
    reportable = "evidence",
    links = fixture_links(),
    documents = "decisions.yml",
    records = "output/record.html",
    store = "_targets",
    script = "_targets.R",
    exit_code = 0L,
    inputs_before = before,
    input_dirs = "data/raw",
    env_packages = "jsonlite"
  ))
  proj
}

build_copy <- function(proj, release_id = "rel-20261105-abcdef", lock = TRUE) {
  build_release_bundle(
    release_id,
    fixture_ledger_path(proj),
    lock = if (lock) list(links = fixture_links()) else NULL,
    store = "_targets",
    script = "_targets.R",
    repo = proj
  )
}

bundle_json <- function(proj, file, release_id = "rel-20261105-abcdef") {
  jsonlite::read_json(file.path(proj, "evidence", "releases", release_id, file), simplifyVector = FALSE)
}

blocker_ids <- function(proj) {
  vapply(bundle_json(proj, "checklist.json")$blockers, `[[`, "", "id")
}

test_that("release IDs are opaque and well formed", {
  ids <- replicate(20, allocate_release_id(as.Date("2026-11-05")))
  expect_true(all(grepl(.release_id_pattern, ids)))
  expect_true(all(startsWith(ids, "rel-20261105-")))
  expect_gt(length(unique(ids)), 1L)
})

test_that("a clean candidate gives passing receipts, no blockers and a manifest written last", {
  skip_ledger_fixture()
  skip_if_not_installed("yaml")
  local_engine()
  proj <- release_fixture()
  out <- build_copy(proj)
  dir <- file.path(proj, out$dir)
  receipts <- bundle_json(proj, "receipts.json")$receipts
  outcomes <- stats::setNames(vapply(receipts, `[[`, "", "outcome"), vapply(receipts, `[[`, "", "check"))
  expect_identical(
    outcomes[c("contract_checked", "execution_recorded", "known_answer_checked", "render_checked",
               "reproduced", "disclosure_approved")],
    c(contract_checked = "pass", execution_recorded = "pass", known_answer_checked = "pass",
      render_checked = "not_established", reproduced = "not_run", disclosure_approved = "not_run")
  )
  expect_identical(blocker_ids(proj), character(0))
  expect_identical(out$n_blockers, 0L)
  diag <- Filter(function(r) r$check == "diagnostics_checked", receipts)[[1]]
  expect_identical(diag[c("outcome", "reason")], list(outcome = "not_run", reason = "not applicable: No model is fitted."))

  manifest <- bundle_json(proj, "manifest.json")
  files <- sort(list.files(dir, recursive = TRUE, all.files = TRUE), method = "radix")
  expect_identical(vapply(manifest$artifacts, `[[`, "", "path"), setdiff(files, "manifest.json"))
  for (a in manifest$artifacts) {
    expect_identical(a$sha256, digest::digest(file = file.path(dir, a$path), algo = "sha256"), info = a$path)
  }
  expect_true("deliverables/output/record.html" %in% files)
  expect_true(all(c("run/ledger.json", "run/audit.md", "receipts.json", "checklist.md", ".gitattributes") %in% files))
  expect_identical(manifest$requirements_sha256,
                   digest::digest(file = file.path(proj, "contracts", "requirements.yml"), algo = "sha256"))
  expect_identical(manifest$analysis_commit, system2("git", c("-C", proj, "rev-parse", "HEAD"), stdout = TRUE))
  expect_identical(out$manifest_sha256, digest::digest(file = file.path(dir, "manifest.json"), algo = "sha256"))
  manifest_text <- paste(readLines(file.path(dir, "manifest.json")), collapse = "\n")
  expect_false(grepl("manifest.json|approval|tag", manifest_text))
  expect_true(any(grepl("proposes no acceptances", readLines(file.path(dir, "checklist.md")))))

  expect_error(build_copy(proj), class = "dctools_release_exists_error")
})

test_that("a required check that did not pass and an open relevant item are waivable blockers", {
  skip_ledger_fixture()
  skip_if_not_installed("yaml")
  local_engine()
  proj <- release_fixture(
    items = list(
      release_item("DATA-012"),
      release_item("DATA-013", disposition = "accepted_limitation"),
      release_item("DATA-014", disposition = "resolved"),
      release_item("SAP-002", relevant = FALSE)
    ),
    known_test = "expect_equal(1 + 1, 3)"
  )
  build_copy(proj)
  blockers <- bundle_json(proj, "checklist.json")$blockers
  ids <- vapply(blockers, `[[`, "", "id")
  expect_setequal(ids, c("check:known_answer_checked", "item:DATA-012", "item:DATA-013"))
  expect_false(any(vapply(blockers, `[[`, logical(1), "nonwaivable")))
  expect_length(bundle_json(proj, "checklist.json")$unresolved_items, 4L)
})

test_that("a missing lock is a blocker only when the contract check is required", {
  skip_ledger_fixture()
  skip_if_not_installed("yaml")
  local_engine()
  proj <- release_fixture(lock = FALSE)
  build_copy(proj, lock = FALSE)
  expect_identical(blocker_ids(proj), "check:contract_checked")
  proj2 <- release_fixture(requirements = release_requirements(contract_checked = "optional"), lock = FALSE)
  build_copy(proj2, lock = FALSE)
  expect_identical(blocker_ids(proj2), character(0))
})

test_that("missing requirements, a missing deliverable and failed input checks are nonwaivable", {
  skip_ledger_fixture()
  skip_if_not_installed("yaml")
  local_engine()
  reqs <- release_requirements(reproduced = NULL)
  reqs$deliverables <- list("output/record.html", "output/missing.html")
  reqs$checks$diagnostics_checked <- "not_applicable"
  reqs$not_applicable_reasons <- list()
  proj <- release_fixture(requirements = reqs)
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$input_stability[[1]]$sha256_before <- strrep("0", 64)
    l
  })
  build_copy(proj)
  blockers <- bundle_json(proj, "checklist.json")$blockers
  nonwaivable <- vapply(Filter(function(b) isTRUE(b$nonwaivable), blockers), `[[`, "", "id")
  expect_true(all(c("requirements:missing", "deliverable:missing", "inputs:unidentified") %in% nonwaivable))
  reasons <- vapply(blockers, `[[`, "", "reason")
  expect_true(any(grepl("check reproduced is not declared", reasons)))
  expect_true(any(grepl("diagnostics_checked is not_applicable without a reason", reasons)))
  expect_true(any(grepl("output/missing.html does not exist", reasons)))
})

test_that("a release is built only from a clean tree at the ledgered commit", {
  skip_ledger_fixture()
  skip_if_not_installed("yaml")
  local_engine()
  proj <- release_fixture()
  writeLines("x", file.path(proj, "R", "scratch.R"))
  expect_error(build_copy(proj), class = "dctools_release_dirty_error")
  unlink(file.path(proj, "R", "scratch.R"))
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$code$sha <- strrep("a", 40)
    l
  })
  expect_error(build_copy(proj), class = "dctools_release_origin_error")
  expect_false(dir.exists(file.path(proj, "evidence")))
  expect_error(build_copy(proj, release_id = "abc123"), class = "dctools_release_id_error")
})
