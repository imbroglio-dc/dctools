# A synthetic project: A commits the analysis and release inputs; E adds the
# bundle (checklist, receipts, a deliverable, the manifest written last).

rid <- "rel-20261105-abcdef"

vgit <- function(proj, ...) {
  out <- system2("git", shQuote(c("-C", proj, ...)), stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) stop("git failed: ", paste(c(...), collapse = " "), "\n", paste(out, collapse = "\n"))
  out
}

verify_fixture <- function(blockers = list(), env = parent.frame()) {
  proj <- withr::local_tempdir(.local_envir = env)
  vgit(proj, "init", "-q", "-b", "main")
  vgit(proj, "config", "user.email", "t@example.com")
  vgit(proj, "config", "user.name", "t")
  dir.create(file.path(proj, "contracts"))
  dir.create(file.path(proj, "records"))
  dir.create(file.path(proj, "R"))
  writeLines(c("requirements_schema_version: 1", "release_approver: owner-login"),
             file.path(proj, "contracts", "requirements.yml"))
  writeLines(c("unresolved_schema_version: 1", "items: []"), file.path(proj, "records", "unresolved.yml"))
  writeLines("f <- function() 1", file.path(proj, "R", "analysis.R"))
  vgit(proj, "add", "-A")
  vgit(proj, "commit", "-q", "-m", "A")
  a <- vgit(proj, "rev-parse", "HEAD")
  vgit(proj, "checkout", "-q", "-b", "release")
  bundle <- file.path(proj, "evidence", "releases", rid)
  dir.create(file.path(bundle, "deliverables", "output"), recursive = TRUE)
  writeChar("* -text\n", file.path(bundle, ".gitattributes"), eos = NULL, useBytes = TRUE)
  writeLines("<p>flow chart</p>", file.path(bundle, "deliverables", "output", "chart.html"))
  .write_json_file(list(receipts_schema_version = 1L, release_id = rid, receipts = list()), file.path(bundle, "receipts.json"))
  .write_json_file(list(release_id = rid, checklist_schema_version = 1L, blockers = blockers), file.path(bundle, "checklist.json"))
  withr::with_dir(proj, .write_manifest(
    file.path("evidence", "releases", rid), rid, "20261105-120000", a,
    "contracts/requirements.yml", "records/unresolved.yml"
  ))
  vgit(proj, "add", "-A")
  vgit(proj, "commit", "-q", "-m", "E")
  list(
    proj = proj,
    a = a,
    e = vgit(proj, "rev-parse", "HEAD"),
    digest = digest::digest(file = file.path(bundle, "manifest.json"), algo = "sha256")
  )
}

approval_body <- function(fx, accept = NULL, release = rid, digest = fx$digest) {
  c_accept <- if (is.null(accept)) "accept: []" else c("accept:", unlist(lapply(accept, function(x) {
    c(paste0("  - id: ", x[[1]]), paste0("    rationale: \"", x[[2]], "\""))
  })))
  paste(c("Looks right.", "", "```release-approval", paste0("release: ", release), paste0("manifest: ", digest), c_accept, "```"),
        collapse = "\n")
}

review <- function(fx, body = approval_body(fx), state = "APPROVED", commit = fx$e,
                   login = "owner-login", id = 101, at = "2026-11-05T10:00:00Z") {
  list(id = id, user = list(login = login), state = state, commit_id = commit, body = body, submitted_at = at)
}

verify <- function(fx, reviews, head = fx$e) verify_release(rid, head, reviews, repo = fx$proj)
status <- function(result, check) result$status[result$check == check]
details <- function(result, check) result$detail[result$check == check][[1]]

blocker <- function(id, nonwaivable = FALSE) list(id = id, reason = "r", nonwaivable = nonwaivable)

skip_verify <- function() {
  skip_on_cran()
  skip_if_not_installed("yaml")
  skip_if_not_installed("digest")
  skip_if_not_installed("jsonlite")
}

test_that("an approval of E naming the release and manifest verifies", {
  skip_verify()
  fx <- verify_fixture()
  result <- verify(fx, list(review(fx, state = "COMMENTED", id = 99), review(fx)))
  expect_identical(attr(result, "verdict"), "PASS", info = paste(unlist(result$detail), collapse = "; "))
  expect_identical(attr(result, "review_id"), "101")
  expect_identical(attr(result, "manifest_sha256"), fx$digest)
})

test_that("a changed approved artifact fails V1", {
  skip_verify()
  fx <- verify_fixture()
  writeLines("<p>edited</p>", file.path(fx$proj, "evidence", "releases", rid, "deliverables", "output", "chart.html"))
  writeLines("extra", file.path(fx$proj, "evidence", "releases", rid, "extra.txt"))
  vgit(fx$proj, "commit", "-qam", "edit")
  vgit(fx$proj, "add", "-A")
  vgit(fx$proj, "commit", "-q", "-m", "extra")
  e2 <- vgit(fx$proj, "rev-parse", "HEAD")
  result <- verify(fx, list(review(fx, commit = e2)), head = e2)
  expect_identical(status(result, "V1"), "FAIL")
  expect_true("deliverables/output/chart.html: SHA-256 differs from the manifest" %in% details(result, "V1"))
  expect_true("extra.txt: in the bundle but not in the manifest" %in% details(result, "V1"))
  # The approval of the earlier E does not carry over to the new head.
  stale <- verify(fx, list(review(fx)), head = e2)
  expect_true(any(grepl("not E", details(stale, "V3"))))
})

test_that("a blocker not accepted fails V4; accepting it with a rationale passes", {
  skip_verify()
  fx <- verify_fixture(blockers = list(blocker("check:known_answer_checked"), blocker("item:DATA-012")))
  none <- verify(fx, list(review(fx)))
  expect_identical(status(none, "V4"), "FAIL")
  expect_setequal(details(none, "V4"), c("check:known_answer_checked: not accepted", "item:DATA-012: not accepted"))
  bare <- verify(fx, list(review(fx, body = approval_body(fx, list(
    list("check:known_answer_checked", ""), list("item:DATA-012", "Duplicate timestamp affects no count.")
  )))))
  expect_identical(details(bare, "V4"), "check:known_answer_checked: accepted without a rationale")
  ok <- verify(fx, list(review(fx, body = approval_body(fx, list(
    list("check:known_answer_checked", "Covered by the audit tests."), list("item:DATA-012", "Affects no count.")
  )))))
  expect_identical(attr(ok, "verdict"), "PASS")
})

test_that("a nonwaivable blocker fails V4 even when accepted, and unknown acceptances fail", {
  skip_verify()
  fx <- verify_fixture(blockers = list(blocker("inputs:unidentified", nonwaivable = TRUE)))
  result <- verify(fx, list(review(fx, body = approval_body(fx, list(
    list("inputs:unidentified", "We know the inputs."), list("item:NOPE-1", "?")
  )))))
  expect_identical(status(result, "V4"), "FAIL")
  expect_true("inputs:unidentified: nonwaivable and cannot be accepted" %in% details(result, "V4"))
  expect_true("item:NOPE-1: accepted but not a blocker in the checklist" %in% details(result, "V4"))
})

test_that("a non-evidence change or a merge between A and E fails V2", {
  skip_verify()
  fx <- verify_fixture()
  writeLines("f <- function() 2", file.path(fx$proj, "R", "analysis.R"))
  vgit(fx$proj, "commit", "-qam", "sneak")
  e2 <- vgit(fx$proj, "rev-parse", "HEAD")
  result <- verify(fx, list(review(fx, commit = e2)), head = e2)
  expect_identical(status(result, "V2"), "FAIL")
  expect_true("R/analysis.R: changed between A and E outside the bundle" %in% details(result, "V2"))

  fx2 <- verify_fixture()
  vgit(fx2$proj, "checkout", "-q", "main")
  writeLines("notes", file.path(fx2$proj, "NOTES.md"))
  vgit(fx2$proj, "add", "-A")
  vgit(fx2$proj, "commit", "-q", "-m", "main moves on")
  vgit(fx2$proj, "checkout", "-q", "release")
  vgit(fx2$proj, "merge", "-q", "--no-edit", "main")
  e3 <- vgit(fx2$proj, "rev-parse", "HEAD")
  merged <- verify(fx2, list(review(fx2, commit = e3)), head = e3)
  expect_true(any(grepl("merge commit", details(merged, "V2"))))
})

test_that("the approval must be the approver's latest decisive review, of E, naming this release and manifest", {
  skip_verify()
  fx <- verify_fixture()
  later_block <- verify(fx, list(review(fx), review(fx, state = "CHANGES_REQUESTED", id = 102, at = "2026-11-05T11:00:00Z")))
  expect_true(any(grepl("is CHANGES_REQUESTED", details(later_block, "V3"))))
  dismissed <- verify(fx, list(review(fx, state = "DISMISSED")))
  expect_identical(status(dismissed, "V3"), "FAIL")
  other <- verify(fx, list(review(fx, login = "someone-else")))
  expect_identical(details(other, "V3"), "no review by owner-login")
  wrong_digest <- verify(fx, list(review(fx, body = approval_body(fx, digest = strrep("0", 64)))))
  expect_true("the approval names another manifest digest" %in% details(wrong_digest, "V3"))
  wrong_release <- verify(fx, list(review(fx, body = approval_body(fx, release = "rel-20261105-zzzzzz"))))
  expect_true("the approval names another release" %in% details(wrong_release, "V3"))
  no_block <- verify(fx, list(review(fx, body = "LGTM")))
  expect_true("the review has no readable release-approval block" %in% details(no_block, "V3"))
})

test_that("the template's block, once filled in, verifies", {
  skip_verify()
  fx <- verify_fixture(blockers = list(blocker("item:DATA-012"), blocker("deliverable:missing", nonwaivable = TRUE)))
  lines <- release_approval_template(rid, repo = fx$proj)
  expect_true(paste0("manifest: ", fx$digest) %in% lines)
  expect_true("#  - id: item:DATA-012" %in% lines)
  expect_false(any(grepl("^#  - id: deliverable:missing", lines)))
  expect_true(any(grepl("Nonwaivable blockers", lines)))
  filled <- sub("^#  - id: ", "  - id: ", lines)
  filled <- sub("^#    rationale: \"\"$", "    rationale: \"Affects no count.\"", filled)
  result <- verify(fx, list(review(fx, body = paste(filled, collapse = "\n"))))
  expect_identical(status(result, "V3"), "PASS")
  expect_identical(details(result, "V4"), "deliverable:missing: nonwaivable")
})

fake_github <- function(fx, reviews) {
  function(path) {
    if (grepl("/reviews/", path)) {
      id <- sub(".*/reviews/", "", path)
      return(Filter(function(r) identical(as.character(r$id), id), reviews)[[1]])
    }
    if (grepl("/reviews\\?", path)) {
      return(reviews)
    }
    list(head = list(sha = fx$e))
  }
}

test_that("verify_release_pr fails CI on a failing verdict", {
  skip_verify()
  fx <- verify_fixture(blockers = list(blocker("item:DATA-012")))
  out <- utils::capture.output(err <- expect_error(
    verify_release_pr(rid, 7, slug = "o/r", repo = fx$proj, fetch = fake_github(fx, list(review(fx)))),
    class = "dctools_release_unverified"
  ))
  expect_true("V4 Blockers accepted: FAIL" %in% out)
  expect_true("verdict: FAIL" %in% out)
})

test_that("the approval archive is the review verbatim, and a later edit or dismissal is flagged", {
  skip_verify()
  fx <- verify_fixture()
  reviews <- list(review(fx))
  path <- archive_release_approval(rid, 7, slug = "o/r", repo = fx$proj, fetch = fake_github(fx, reviews))
  record <- jsonlite::read_json(path, simplifyVector = FALSE)
  expect_identical(record$body, reviews[[1]]$body)
  expect_identical(record[c("release_id", "pr", "review_id", "reviewer", "commit_id", "manifest_sha256")],
                   list(release_id = rid, pr = 7L, review_id = "101", reviewer = "owner-login",
                        commit_id = fx$e, manifest_sha256 = fx$digest))
  expect_identical(record$verification$verdict, "PASS")
  expect_true(check_approval_archive(rid, slug = "o/r", repo = fx$proj, fetch = fake_github(fx, reviews)))

  edited <- reviews
  edited[[1]]$body <- paste(edited[[1]]$body, "(edited)")
  expect_error(check_approval_archive(rid, slug = "o/r", repo = fx$proj, fetch = fake_github(fx, edited)),
               "body", class = "dctools_approval_archive_mismatch")
  dismissed <- reviews
  dismissed[[1]]$state <- "DISMISSED"
  expect_error(check_approval_archive(rid, slug = "o/r", repo = fx$proj, fetch = fake_github(fx, dismissed)),
               "state", class = "dctools_approval_archive_mismatch")
  expect_error(archive_release_approval(rid, 7, slug = "o/r", repo = fx$proj, fetch = fake_github(fx, reviews)),
               class = "dctools_release_exists_error")
})

test_that("a release that does not verify is not archived", {
  skip_verify()
  fx <- verify_fixture(blockers = list(blocker("item:DATA-012")))
  expect_error(
    archive_release_approval(rid, 7, slug = "o/r", repo = fx$proj, fetch = fake_github(fx, list(review(fx)))),
    class = "dctools_release_unverified"
  )
  expect_false(dir.exists(file.path(fx$proj, "evidence", "approvals")))
})
