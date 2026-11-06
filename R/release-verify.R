# Release approval and verification ----------------------------------------------
#
# The approval template, release verification and the approval archive
# (architecture section 12.3, steps 3 to 7). Verification is a pure function
# of the repository and the PR's reviews; fetching them from GitHub is
# separate. Spec: biostat-support
# docs/superpowers/specs/2026-11-05-release-kit-design.md.

.archive_schema_version <- 1L
.decisive_states <- c("APPROVED", "CHANGES_REQUESTED", "DISMISSED")

.bundle_path <- function(release_id) file.path("evidence", "releases", release_id)

# A blob's exact bytes at `rev`, through a temporary file (no re-encoding).
.git_blob_sha256 <- function(repo, rev, path) {
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  status <- suppressWarnings(system2(
    "git",
    shQuote(c("-C", repo, "cat-file", "blob", paste0(rev, ":", path))),
    stdout = tmp,
    stderr = FALSE
  ))
  if (!identical(as.integer(status), 0L)) {
    return(NA_character_)
  }
  digest::digest(file = tmp, algo = "sha256")
}

.git_text <- function(repo, rev, path) {
  out <- tryCatch(.git(repo, c("show", paste0(rev, ":", path))), dctools_git_error = function(e) NULL)
  if (is.null(out)) NULL else paste(out, collapse = "\n")
}

.parse_approval <- function(body) {
  if (!is.character(body) || length(body) != 1L) {
    return(NULL)
  }
  body <- gsub("\r\n", "\n", body, fixed = TRUE)
  m <- regmatches(body, regexec("```release-approval[ \t]*\n(.*?)\n```", body))[[1]]
  if (length(m) < 2L) {
    return(NULL)
  }
  parsed <- tryCatch(yaml::yaml.load(m[2]), error = function(e) NULL)
  if (!is.list(parsed)) NULL else parsed
}

.verify_check <- function(check, name, problems) {
  data.frame(
    check = check,
    name = name,
    status = if (length(problems)) "FAIL" else "PASS",
    detail = I(list(problems)),
    stringsAsFactors = FALSE
  )
}

#' Verify a release candidate's bundle and approval
#'
#' Release verification (architecture section 12.3, step 5), run in CI on
#' the release PR and again on the `results-v*` tag. Four checks:
#'
#' * **V1 Bundle matches manifest**: at E, the bundle holds exactly the
#'   manifest's files, each with its recorded SHA-256 (read from git, byte
#'   for byte).
#' * **V2 Evidence only since A**: the manifest's analysis commit A is an
#'   ancestor of E, nothing between them is a merge, every change from A to
#'   E lies under the bundle directory, and the requirements and inventory at
#'   A have the digests the manifest records.
#' * **V3 Approval binds E**: the latest decisive review (approved, changes
#'   requested or dismissed) by the `release_approver` named in the
#'   requirements at A is an approval of E's commit, and its
#'   `release-approval` block names this release and the manifest's SHA-256.
#' * **V4 Blockers accepted**: the checklist has no nonwaivable blocker,
#'   every waivable blocker is accepted with a rationale, and nothing
#'   accepted is unknown.
#'
#' The approval block is a fenced code block in the review body:
#' ````
#' ```release-approval
#' release: rel-20261105-abcdef
#' manifest: <SHA-256 of manifest.json>
#' accept:
#'   - id: item:DATA-012
#'     rationale: "One line on why this is acceptable."
#' ```
#' ````
#' [release_approval_template()] writes it for the release PR.
#'
#' @param release_id The release ID.
#' @param head_sha E, the release PR's head commit.
#' @param reviews The PR's reviews in GitHub's REST shape (each with `id`,
#'   `user$login`, `state`, `commit_id`, `body`, `submitted_at`).
#' @param repo The repository.
#' @return A data frame, one row per check (`check`, `name`, `status`,
#'   `detail`), with the verdict (`"PASS"` or `"FAIL"`), the binding review's
#'   id and the manifest digest as attributes.
#' @seealso [verify_release_pr()], [archive_release_approval()].
#' @export
verify_release <- function(release_id, head_sha, reviews, repo = ".") {
  .require_pkgs(c("jsonlite", "digest", "yaml"), "verify_release")
  bundle <- .bundle_path(release_id)
  manifest_file <- file.path(bundle, "manifest.json")
  manifest_text <- .git_text(repo, head_sha, manifest_file)
  manifest <- if (is.null(manifest_text)) NULL else tryCatch(
    jsonlite::fromJSON(manifest_text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  digest <- .git_blob_sha256(repo, head_sha, manifest_file)

  # V1
  v1 <- character(0)
  if (is.null(manifest)) {
    v1 <- paste0("no readable manifest at ", manifest_file, " in ", substr(head_sha, 1, 7))
  } else {
    if (!identical(manifest$release_id, release_id)) {
      v1 <- c(v1, "the manifest names another release")
    }
    listed <- vapply(manifest$artifacts, function(a) .as_chr(a$path), "")
    at_e <- tryCatch(
      .git(repo, c("ls-tree", "-r", "--name-only", head_sha, "--", paste0(bundle, "/"))),
      dctools_git_error = function(e) character(0)
    )
    at_e <- setdiff(substring(at_e, nchar(bundle) + 2L), "manifest.json")
    for (p in setdiff(at_e, listed)) v1 <- c(v1, paste0(p, ": in the bundle but not in the manifest"))
    for (a in manifest$artifacts) {
      p <- .as_chr(a$path)
      got <- .git_blob_sha256(repo, head_sha, file.path(bundle, p))
      if (is.na(got)) {
        v1 <- c(v1, paste0(p, ": in the manifest but not in the bundle"))
      } else if (!identical(got, .as_chr(a$sha256))) {
        v1 <- c(v1, paste0(p, ": SHA-256 differs from the manifest"))
      }
    }
  }

  # V2
  v2 <- character(0)
  a <- if (is.null(manifest)) NA_character_ else .as_chr(manifest$analysis_commit)
  requirements <- NULL
  checklist <- NULL
  if (is.na(a)) {
    v2 <- "the manifest names no analysis commit"
  } else if (!.git_ok(repo, c("merge-base", "--is-ancestor", a, head_sha))) {
    v2 <- paste0("A (", substr(a, 1, 7), ") is not an ancestor of E")
  } else {
    merges <- .git(repo, c("rev-list", "--merges", paste0(a, "..", head_sha)))
    if (length(merges)) {
      v2 <- c(v2, paste0("A..E contains ", length(merges), " merge commit(s)"))
    }
    changed <- .git(repo, c("diff", "--name-only", a, head_sha))
    outside <- changed[!startsWith(changed, paste0(bundle, "/"))]
    for (p in outside) v2 <- c(v2, paste0(p, ": changed between A and E outside the bundle"))
    for (pair in list(c("requirements_sha256", "contracts/requirements.yml"), c("unresolved_sha256", "records/unresolved.yml"))) {
      got <- .git_blob_sha256(repo, a, pair[2])
      if (!identical(got, .as_chr(manifest[[pair[1]]]))) {
        v2 <- c(v2, paste0(pair[2], ": digest at A differs from the manifest"))
      }
    }
    req_text <- .git_text(repo, a, "contracts/requirements.yml")
    requirements <- if (is.null(req_text)) NULL else tryCatch(yaml::yaml.load(req_text), error = function(e) NULL)
  }
  checklist_text <- .git_text(repo, head_sha, file.path(bundle, "checklist.json"))
  checklist <- if (is.null(checklist_text)) NULL else tryCatch(
    jsonlite::fromJSON(checklist_text, simplifyVector = FALSE),
    error = function(e) NULL
  )

  # V3
  v3 <- character(0)
  approver <- if (is.list(requirements)) requirements$release_approver else NULL
  binding <- NULL
  approval <- NULL
  if (!is.character(approver) || length(approver) != 1L || !nzchar(approver)) {
    v3 <- "the requirements at A name no release_approver"
  } else {
    mine <- Filter(function(r) {
      identical(tolower(.as_chr(r$user$login)), tolower(approver)) &&
        isTRUE(.as_chr(r$state) %in% .decisive_states)
    }, reviews)
    if (!length(mine)) {
      v3 <- paste0("no review by ", approver)
    } else {
      times <- vapply(mine, function(r) .as_chr(r$submitted_at), "")
      binding <- mine[[order(times, method = "radix", decreasing = TRUE)[1]]]
      if (!identical(.as_chr(binding$state), "APPROVED")) {
        v3 <- c(v3, paste0("the latest decisive review by ", approver, " is ", binding$state))
      }
      if (!identical(.as_chr(binding$commit_id), head_sha)) {
        v3 <- c(v3, paste0("the review is on ", substr(.as_chr(binding$commit_id), 1, 7), ", not E (", substr(head_sha, 1, 7), ")"))
      }
      approval <- .parse_approval(binding$body)
      if (is.null(approval)) {
        v3 <- c(v3, "the review has no readable release-approval block")
      } else {
        if (!identical(.as_chr(approval$release), release_id)) {
          v3 <- c(v3, "the approval names another release")
        }
        if (is.na(digest) || !identical(.as_chr(approval$manifest), digest)) {
          v3 <- c(v3, "the approval names another manifest digest")
        }
      }
    }
  }

  # V4
  v4 <- character(0)
  if (is.null(checklist)) {
    v4 <- "no readable checklist in the bundle"
  } else {
    blockers <- checklist$blockers
    ids <- vapply(blockers, function(b) .as_chr(b$id), "")
    nonwaivable <- vapply(blockers, function(b) isTRUE(b$nonwaivable), logical(1))
    accepts <- if (is.null(approval)) list() else approval$accept
    if (!is.null(accepts) && !is.list(accepts)) {
      accepts <- list()
      v4 <- c(v4, "accept must be a list of {id, rationale}")
    }
    accepted <- vapply(accepts, function(x) .as_chr(x$id), "")
    rationale_ok <- vapply(accepts, function(x) is.character(x$rationale) && nzchar(trimws(x$rationale)), logical(1))
    for (i in which(nonwaivable)) {
      v4 <- c(v4, paste0(ids[i], ": nonwaivable", if (ids[i] %in% accepted) " and cannot be accepted" else ""))
    }
    for (i in which(!nonwaivable)) {
      j <- match(ids[i], accepted)
      if (is.na(j)) {
        v4 <- c(v4, paste0(ids[i], ": not accepted"))
      } else if (!rationale_ok[j]) {
        v4 <- c(v4, paste0(ids[i], ": accepted without a rationale"))
      }
    }
    for (x in setdiff(accepted, ids)) v4 <- c(v4, paste0(x, ": accepted but not a blocker in the checklist"))
  }

  result <- rbind(
    .verify_check("V1", "Bundle matches manifest", v1),
    .verify_check("V2", "Evidence only since A", v2),
    .verify_check("V3", "Approval binds E", v3),
    .verify_check("V4", "Blockers accepted", unique(v4))
  )
  attr(result, "verdict") <- if (all(result$status == "PASS")) "PASS" else "FAIL"
  attr(result, "review_id") <- if (is.null(binding)) NA_character_ else .as_chr(binding$id)
  attr(result, "manifest_sha256") <- digest
  result
}

# GitHub REST through the gh CLI, which takes its token from the environment
# (GH_TOKEN in Actions). Returns parsed JSON.
.gh_api <- function(path) {
  out <- system2("gh", c("api", "-H", shQuote("Accept: application/vnd.github+json"), shQuote(path)),
                 stdout = TRUE, stderr = FALSE)
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    .release_error(paste0("gh api ", path, " failed"), "dctools_github_error")
  }
  jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
}

.fetch_reviews <- function(slug, pr, fetch = .gh_api) {
  reviews <- list()
  page <- 1L
  repeat {
    batch <- fetch(sprintf("repos/%s/pulls/%d/reviews?per_page=100&page=%d", slug, as.integer(pr), page))
    reviews <- c(reviews, batch)
    if (length(batch) < 100L) break
    page <- page + 1L
  }
  reviews
}

#' @describeIn verify_release Fetch the PR's reviews from GitHub (through the
#'   `gh` CLI) and verify; stops with class `dctools_release_unverified` on
#'   any failure, printing the checks, so CI fails.
#' @param pr The release PR's number.
#' @param slug `owner/repo`; defaults to `GITHUB_REPOSITORY`.
#' @param fetch The GitHub API function (for tests).
#' @export
verify_release_pr <- function(
  release_id,
  pr,
  slug = Sys.getenv("GITHUB_REPOSITORY"),
  head_sha = NULL,
  repo = ".",
  fetch = .gh_api
) {
  if (is.null(head_sha)) {
    head_sha <- .as_chr(fetch(sprintf("repos/%s/pulls/%d", slug, as.integer(pr)))$head$sha)
  }
  result <- verify_release(release_id, head_sha, .fetch_reviews(slug, pr, fetch), repo = repo)
  lines <- .verify_lines(result)
  cat(lines, sep = "\n")
  if (!identical(attr(result, "verdict"), "PASS")) {
    stop(structure(
      class = c("dctools_release_unverified", "error", "condition"),
      list(message = paste(c("release verification failed", lines), collapse = "\n"), call = NULL)
    ))
  }
  invisible(result)
}

.verify_lines <- function(result) {
  c(
    vapply(seq_len(nrow(result)), function(i) {
      d <- result$detail[[i]]
      paste0(result$check[i], " ", result$name[i], ": ", result$status[i],
             if (length(d)) paste0("\n  - ", paste(d, collapse = "\n  - ")) else "")
    }, ""),
    paste0("verdict: ", attr(result, "verdict"))
  )
}

#' Write the approval template for a release PR
#'
#' The comment CI posts on the release PR (architecture section 12.3, step
#' 3): the release ID, the manifest's SHA-256 and an `accept:` list. Each
#' waivable blocker in the checklist appears commented out, so nothing is
#' accepted unless the approver uncomments it and writes a rationale;
#' nonwaivable blockers are listed as such and cannot be accepted.
#'
#' @param release_id The release ID.
#' @param repo The repository (its working tree is the release PR's head).
#' @return The comment's lines.
#' @export
release_approval_template <- function(release_id, repo = ".") {
  .require_pkgs(c("jsonlite", "digest"), "release_approval_template")
  bundle <- file.path(repo, .bundle_path(release_id))
  digest <- .sha256_file(file.path(bundle, "manifest.json"))
  if (is.na(digest)) {
    .release_error(paste0("no manifest for ", release_id), "dctools_release_missing_error")
  }
  checklist <- jsonlite::read_json(file.path(bundle, "checklist.json"), simplifyVector = FALSE)
  blockers <- checklist$blockers
  waivable <- Filter(function(b) !isTRUE(b$nonwaivable), blockers)
  hard <- Filter(function(b) isTRUE(b$nonwaivable), blockers)
  c(
    paste0("Release ", release_id, ": review the bundle, `checklist.md` and the disclosure terms, then submit an approving review of this head commit whose body contains the block below."),
    if (length(hard)) c("", "**Nonwaivable blockers (verification will fail; this candidate cannot be released):**",
                        vapply(hard, function(b) paste0("- `", b$id, "`: ", b$reason), "")),
    "",
    "```release-approval",
    paste0("release: ", release_id),
    paste0("manifest: ", digest),
    if (length(waivable)) {
      c("accept:", "# Uncomment each blocker you accept and give a one-line rationale:",
        unlist(lapply(waivable, function(b) c(paste0("#  - id: ", b$id), "#    rationale: \"\""))))
    } else {
      "accept: []"
    },
    "```"
  )
}

#' Archive a release approval, and check the archive
#'
#' After the release PR merges and `results-v*` is tagged,
#' `archive_release_approval()` writes the binding approving review verbatim
#' to `evidence/approvals/<release_id>.json` (architecture section 12.3, step
#' 7): review id, reviewer, state, commit, submission time, body, PR number,
#' release ID, manifest digest and the verification outcome. It refuses to
#' overwrite an archive or to archive a release that does not verify.
#' `check_approval_archive()` fetches the review again and fails (class
#' `dctools_approval_archive_mismatch`) unless every archived field matches,
#' so a review edited or dismissed later is flagged.
#'
#' @inheritParams verify_release_pr
#' @return `archive_release_approval()` returns the archive's path invisibly;
#'   `check_approval_archive()` returns `TRUE` invisibly.
#' @export
archive_release_approval <- function(
  release_id,
  pr,
  slug = Sys.getenv("GITHUB_REPOSITORY"),
  repo = ".",
  fetch = .gh_api
) {
  path <- file.path(repo, "evidence", "approvals", paste0(release_id, ".json"))
  if (file.exists(path)) {
    .release_error(paste0(path, " already exists; archives are append-only"), "dctools_release_exists_error")
  }
  reviews <- .fetch_reviews(slug, pr, fetch)
  head_sha <- .as_chr(fetch(sprintf("repos/%s/pulls/%d", slug, as.integer(pr)))$head$sha)
  result <- verify_release(release_id, head_sha, reviews, repo = repo)
  if (!identical(attr(result, "verdict"), "PASS")) {
    .release_error(paste(c("the release does not verify; nothing archived", .verify_lines(result)), collapse = "\n"),
                   "dctools_release_unverified")
  }
  id <- attr(result, "review_id")
  review <- Filter(function(r) identical(.as_chr(r$id), id), reviews)[[1]]
  record <- c(
    list(archive_schema_version = .archive_schema_version, release_id = release_id, pr = as.integer(pr)),
    .review_fields(review),
    list(
      manifest_sha256 = attr(result, "manifest_sha256"),
      verification = list(
        verdict = attr(result, "verdict"),
        checks = lapply(seq_len(nrow(result)), function(i) list(check = result$check[i], status = result$status[i]))
      )
    )
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  .write_json_file(record, path)
  invisible(path)
}

.review_fields <- function(review) {
  list(
    review_id = .as_chr(review$id),
    reviewer = .as_chr(review$user$login),
    state = .as_chr(review$state),
    commit_id = .as_chr(review$commit_id),
    submitted_at = .as_chr(review$submitted_at),
    body = .as_chr(review$body)
  )
}

#' @rdname archive_release_approval
#' @export
check_approval_archive <- function(
  release_id,
  slug = Sys.getenv("GITHUB_REPOSITORY"),
  repo = ".",
  fetch = .gh_api
) {
  path <- file.path(repo, "evidence", "approvals", paste0(release_id, ".json"))
  archived <- jsonlite::read_json(path, simplifyVector = FALSE)
  live <- .review_fields(fetch(sprintf(
    "repos/%s/pulls/%d/reviews/%s", slug, as.integer(archived$pr), archived$review_id
  )))
  fields <- names(live)
  differ <- fields[!vapply(fields, function(f) identical(.as_chr(archived[[f]]), live[[f]]), logical(1))]
  if (!identical(.as_chr(archived$release_id), release_id)) {
    differ <- c("release_id", differ)
  }
  if (length(differ)) {
    stop(structure(
      class = c("dctools_approval_archive_mismatch", "error", "condition"),
      list(message = paste0("the archived approval differs from the review on GitHub: ", paste(differ, collapse = ", ")), call = NULL)
    ))
  }
  invisible(TRUE)
}
