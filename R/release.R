# Release bundle -----------------------------------------------------------------
#
# Receipts, the candidate checklist and the manifest for one release candidate
# (architecture sections 4.3, 6.3, 12.3). Spec: biostat-support
# docs/superpowers/specs/2026-11-05-release-kit-design.md.

.requirements_schema_version <- 1L
.unresolved_schema_version <- 1L
.receipts_schema_version <- 1L
.checklist_schema_version <- 1L
.manifest_schema_version <- 1L

.receipt_checks <- c(
  "contract_checked", "execution_recorded", "extraction_rechecked",
  "render_checked", "reproduced", "disclosure_approved",
  "known_answer_checked", "diagnostics_checked"
)
.requirement_levels <- c("required", "optional", "not_applicable")
.dispositions <- c("unresolved", "resolved", "accepted_limitation")
.audit_plans <- c("sap_and_results", "sap_only", "none")

.release_error <- function(message, class) {
  stop(structure(
    class = c(class, "dctools_release_error", "error", "condition"),
    list(message = message, call = NULL)
  ))
}

#' Allocate a release ID
#'
#' An opaque release ID, `rel-YYYYMMDD-xxxxxx` with six random lowercase
#' base-32 characters. It is allocated before the release run (so documents
#' can show it) and is never a commit hash or tag.
#'
#' @param date The date part.
#' @return A string.
#' @examples
#' allocate_release_id()
#' @export
allocate_release_id <- function(date = Sys.Date()) {
  alphabet <- c(letters, as.character(2:7))
  paste0("rel-", format(as.Date(date), "%Y%m%d"), "-", paste(sample(alphabet, 6L, replace = TRUE), collapse = ""))
}

.release_id_pattern <- "^rel-[0-9]{8}-[a-z2-7]{6}$"

# The requirements and the problems that make them unusable for a release
# (each a nonwaivable `requirements:missing` blocker).
.read_requirements <- function(path, repo) {
  file <- file.path(repo, path)
  if (!file.exists(file)) {
    return(list(data = NULL, problems = paste0(path, " does not exist")))
  }
  data <- tryCatch(yaml::read_yaml(file), error = function(e) NULL)
  if (!is.list(data)) {
    return(list(data = NULL, problems = paste0(path, " is not a YAML mapping")))
  }
  problems <- character(0)
  if (!identical(as.integer(data$requirements_schema_version), .requirements_schema_version)) {
    problems <- c(problems, "requirements_schema_version must be 1")
  }
  if (!is.character(data$release_approver) || length(data$release_approver) != 1L ||
    !nzchar(data$release_approver)) {
    problems <- c(problems, "release_approver must name one GitHub login")
  }
  if (!isTRUE(data$audit_plan %in% .audit_plans)) {
    problems <- c(problems, paste0("audit_plan must be one of ", paste(.audit_plans, collapse = ", ")))
  }
  checks <- data$checks
  for (check in .receipt_checks) {
    level <- checks[[check]]
    if (is.null(level)) {
      problems <- c(problems, paste0("check ", check, " is not declared"))
    } else if (!isTRUE(level %in% .requirement_levels)) {
      problems <- c(problems, paste0("check ", check, " must be required, optional or not_applicable"))
    } else if (identical(level, "not_applicable")) {
      reason <- data$not_applicable_reasons[[check]]
      if (!is.character(reason) || !nzchar(reason)) {
        problems <- c(problems, paste0("check ", check, " is not_applicable without a reason"))
      }
    }
  }
  unknown <- setdiff(names(checks), .receipt_checks)
  if (length(unknown)) {
    problems <- c(problems, paste0("unknown checks: ", paste(sort(unknown), collapse = ", ")))
  }
  list(data = data, problems = problems)
}

.read_unresolved <- function(path, repo) {
  file <- file.path(repo, path)
  if (!file.exists(file)) {
    return(list(items = list(), problems = paste0(path, " does not exist")))
  }
  data <- tryCatch(yaml::read_yaml(file), error = function(e) NULL)
  if (!is.list(data) || !identical(as.integer(data$unresolved_schema_version), .unresolved_schema_version)) {
    return(list(items = list(), problems = paste0(path, " is not an unresolved-item inventory (schema 1)")))
  }
  problems <- character(0)
  items <- data$items
  if (is.null(items)) {
    items <- list()
  }
  ids <- character(0)
  for (i in seq_along(items)) {
    it <- items[[i]]
    where <- paste0("item ", i)
    ok_id <- is.character(it$id) && length(it$id) == 1L && grepl(.safe_name_pattern, gsub("-", "_", it$id))
    if (!ok_id) {
      problems <- c(problems, paste0(where, ": id must be an identifier such as DATA-012"))
      next
    }
    if (it$id %in% ids) {
      problems <- c(problems, paste0(it$id, ": duplicate id"))
    }
    ids <- c(ids, it$id)
    if (!isTRUE(it$disposition %in% .dispositions)) {
      problems <- c(problems, paste0(it$id, ": disposition must be unresolved, resolved or accepted_limitation"))
    }
    if (!is.logical(it$relevant_to_release) || length(it$relevant_to_release) != 1L ||
      is.na(it$relevant_to_release)) {
      problems <- c(problems, paste0(it$id, ": relevant_to_release must be true or false"))
    }
    if (!is.character(it$owner) || !nzchar(it$owner)) {
      problems <- c(problems, paste0(it$id, ": owner is required"))
    }
  }
  list(items = items, problems = problems)
}

.receipt <- function(check, outcome, reason = NULL, evidence = character(0)) {
  list(check = check, outcome = outcome, reason = reason, evidence = I(evidence))
}

.known_answer_receipt <- function(dirs, repo) {
  if (!length(dirs)) {
    return(.receipt("known_answer_checked", "not_run", "no known_answer_tests declared"))
  }
  .require_pkgs(c("callr", "testthat"), "build_release_bundle")
  per_dir <- vapply(dirs, function(d) {
    path <- file.path(repo, d)
    if (!dir.exists(path)) {
      return("missing")
    }
    res <- tryCatch(
      callr::r(
        function(dir) {
          r <- as.data.frame(testthat::test_dir(
            dir,
            reporter = "silent",
            stop_on_failure = FALSE,
            load_package = "none"
          ))
          c(n = nrow(r), failed = sum(r$failed), error = sum(r$error))
        },
        args = list(dir = normalizePath(path)),
        wd = normalizePath(repo),
        show = FALSE
      ),
      error = function(e) NULL
    )
    if (is.null(res)) {
      "error"
    } else if (res[["n"]] == 0) {
      "empty"
    } else if (res[["failed"]] > 0 || res[["error"]] > 0) {
      "fail"
    } else {
      "pass"
    }
  }, "")
  if (all(per_dir == "pass")) {
    return(.receipt("known_answer_checked", "pass", NULL, character(0)))
  }
  bad <- per_dir[per_dir != "pass"]
  reason <- paste(sprintf("%s: %s", names(bad), bad), collapse = "; ")
  outcome <- if (any(bad == "fail")) "fail" else "not_established"
  .receipt("known_answer_checked", outcome, reason)
}

.release_receipts <- function(audit, lock, requirements, repo, script) {
  verdict <- attr(audit, "verdict")
  execution <- switch(
    verdict,
    PASS = .receipt("execution_recorded", "pass", NULL, c("run/audit.md", "run/ledger.json")),
    FAIL = .receipt("execution_recorded", "fail", "the run audit's verdict is FAIL", c("run/audit.md")),
    .receipt("execution_recorded", "not_established", paste0("the run audit's verdict is ", verdict), c("run/audit.md"))
  )
  contract <- if (is.null(lock)) {
    .receipt("contract_checked", "not_run", "the project has no computation lock")
  } else {
    ok <- tryCatch(
      check_computation_lock(
        lock$links,
        config = lock$config,
        path = if (is.null(lock$path)) "contracts/computation.lock" else lock$path,
        script = script,
        repo = repo
      ),
      dctools_lock_mismatch = function(e) FALSE
    )
    if (isTRUE(ok)) {
      .receipt("contract_checked", "pass", "the committed lock matches the source")
    } else {
      .receipt("contract_checked", "fail", "the committed lock differs from the lock regenerated from source")
    }
  }
  known <- .known_answer_receipt(as.character(unlist(requirements$known_answer_tests)), repo)
  receipts <- list(
    contract,
    execution,
    .receipt("extraction_rechecked", "not_established", "no supported extraction check in this dctools version"),
    .receipt("render_checked", "not_established", "no insertion records in this dctools version"),
    .receipt("reproduced", "not_run", "no identified prior run"),
    .receipt("disclosure_approved", "not_run", "decided in the release approval"),
    known,
    .receipt("diagnostics_checked", "not_established", "no supported diagnostics check in this dctools version")
  )
  # A check the requirements declare not applicable is not run, for their reason.
  lapply(receipts, function(r) {
    if (identical(requirements$checks[[r$check]], "not_applicable") &&
      is.character(requirements$not_applicable_reasons[[r$check]])) {
      return(.receipt(r$check, "not_run", paste0("not applicable: ", requirements$not_applicable_reasons[[r$check]])))
    }
    r
  })
}

.blocker <- function(id, reason, nonwaivable) {
  list(id = id, reason = reason, nonwaivable = nonwaivable)
}

.release_checklist <- function(receipts, requirements, unresolved, audit, deliverables_missing, repo) {
  blockers <- list()
  req <- requirements$data
  for (p in requirements$problems) {
    blockers <- c(blockers, list(.blocker("requirements:missing", p, TRUE)))
  }
  for (p in unresolved$problems) {
    blockers <- c(blockers, list(.blocker("inventory:invalid", p, TRUE)))
  }
  checks <- lapply(receipts, function(r) {
    level <- if (is.null(req$checks[[r$check]])) "undeclared" else req$checks[[r$check]]
    list(check = r$check, requirement = level, outcome = r$outcome, reason = r$reason)
  })
  for (ck in checks) {
    if (identical(ck$requirement, "required") && ck$outcome != "pass" && ck$check != "disclosure_approved") {
      blockers <- c(blockers, list(.blocker(
        paste0("check:", ck$check),
        paste0("required check is ", ck$outcome, if (!is.null(ck$reason)) paste0(": ", ck$reason) else ""),
        FALSE
      )))
    }
  }
  status <- stats::setNames(audit$status, audit$check)
  for (chk in c("C5", "C10")) {
    if (identical(unname(status[chk]), "FAIL")) {
      blockers <- c(blockers, list(.blocker(
        "inputs:unidentified",
        paste0("audit check ", chk, " failed: the release inputs are not identified"),
        TRUE
      )))
    }
  }
  for (d in deliverables_missing) {
    blockers <- c(blockers, list(.blocker("deliverable:missing", paste0(d, " does not exist"), TRUE)))
  }
  items <- lapply(unresolved$items, function(it) {
    list(
      id = it$id, title = if (is.null(it$title)) "" else it$title, owner = it$owner,
      disposition = it$disposition, relevant_to_release = isTRUE(it$relevant_to_release)
    )
  })
  for (it in items) {
    if (it$relevant_to_release && !identical(it$disposition, "resolved")) {
      blockers <- c(blockers, list(.blocker(
        paste0("item:", it$id),
        paste0("relevant to release and ", it$disposition),
        FALSE
      )))
    }
  }
  list(
    checklist_schema_version = .checklist_schema_version,
    release_scope = if (is.null(req$release_scope)) NULL else req$release_scope,
    checks = checks,
    unresolved_items = items,
    blockers = blockers,
    information = list(
      audit_plan = if (is.null(req$audit_plan)) NULL else req$audit_plan,
      audit_rationale = if (is.null(req$audit_rationale)) NULL else req$audit_rationale,
      audit_tests_present = dir.exists(file.path(repo, "tests", "audit"))
    )
  )
}

.checklist_md <- function(checklist, release_id) {
  cell <- function(x) gsub("|", "\\|", if (is.null(x)) "" else x, fixed = TRUE)
  lines <- c(
    paste0("# Candidate checklist: ", release_id),
    "",
    paste0("Scope: ", cell(checklist$release_scope)),
    "",
    "This checklist proposes no acceptances. The release approver decides each blocker in the approval.",
    "",
    "## Checks",
    "",
    "| Check | Requirement | Outcome | Reason |",
    "| --- | --- | --- | --- |",
    vapply(checklist$checks, function(c) {
      sprintf("| %s | %s | %s | %s |", c$check, c$requirement, c$outcome, cell(c$reason))
    }, ""),
    "",
    "## Unresolved items",
    ""
  )
  if (length(checklist$unresolved_items)) {
    lines <- c(
      lines,
      "| ID | Title | Owner | Disposition | Relevant to release |",
      "| --- | --- | --- | --- | --- |",
      vapply(checklist$unresolved_items, function(it) {
        sprintf("| %s | %s | %s | %s | %s |", it$id, cell(it$title), cell(it$owner), it$disposition,
                if (it$relevant_to_release) "yes" else "no")
      }, "")
    )
  } else {
    lines <- c(lines, "None recorded. The checklist cannot tell whether the inventory is complete.")
  }
  lines <- c(lines, "", "## Blockers", "")
  if (length(checklist$blockers)) {
    lines <- c(
      lines,
      "| ID | Reason | Nonwaivable |",
      "| --- | --- | --- |",
      vapply(checklist$blockers, function(b) {
        sprintf("| %s | %s | %s |", b$id, cell(b$reason), if (b$nonwaivable) "yes" else "no")
      }, "")
    )
  } else {
    lines <- c(lines, "None.")
  }
  info <- checklist$information
  c(
    lines,
    "",
    "## Information (not a gate)",
    "",
    paste0("- Audit plan: ", cell(info$audit_plan), if (!is.null(info$audit_rationale)) paste0(" (", cell(info$audit_rationale), ")") else ""),
    paste0("- tests/audit/ present: ", if (isTRUE(info$audit_tests_present)) "yes" else "no"),
    ""
  )
}

.write_json_file <- function(x, path) {
  writeChar(
    paste0(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), "\n"),
    path,
    eos = NULL,
    useBytes = TRUE
  )
}

.bundle_files <- function(dir) {
  files <- sort(list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE), method = "radix")
  files[files != "manifest.json"]
}

# The manifest, written last: every bundle file but itself, with its SHA-256.
.write_manifest <- function(bundle_rel, release_id, run_id, analysis_commit, requirements, unresolved) {
  files <- .bundle_files(bundle_rel)
  manifest <- list(
    manifest_schema_version = .manifest_schema_version,
    release_id = release_id,
    run_id = run_id,
    analysis_commit = analysis_commit,
    # As git stores them at A (byte for byte on every platform).
    requirements_sha256 = .git_blob_sha256(".", analysis_commit, requirements),
    unresolved_sha256 = .git_blob_sha256(".", analysis_commit, unresolved),
    artifacts = lapply(files, function(f) list(path = f, sha256 = .sha256_file(file.path(bundle_rel, f))))
  )
  path <- file.path(bundle_rel, "manifest.json")
  .write_json_file(manifest, path)
  path
}

#' Build a release candidate bundle
#'
#' Writes `evidence/releases/<release_id>/` for the release candidate run
#' (architecture section 12.3, steps 1 and 2): the run's exported evidence,
#' receipts, the candidate checklist, byte copies of the declared
#' deliverables, and the manifest, written last.
#'
#' **Receipts** are computed here, never supplied: `execution_recorded` from
#' [audit_run()] on the run's ledger, `contract_checked` from
#' [check_computation_lock()], `known_answer_checked` from
#' `testthat::test_dir()` on each `known_answer_tests` directory (in a
#' separate R process). `extraction_rechecked`, `render_checked` and
#' `diagnostics_checked` are `not_established` in this version,
#' `reproduced` is `not_run` (no identified prior run), and
#' `disclosure_approved` is `not_run` because the release approval decides it.
#'
#' **The checklist** lists each check with its requirement and outcome, the
#' unresolved items and the blockers, and proposes no acceptances. A required
#' check that did not pass, and an item relevant to the release that is not
#' resolved, are waivable blockers. Missing or invalid requirements, an
#' invalid inventory, failed input checks (audit C5 or C10) and a missing
#' deliverable are nonwaivable.
#'
#' **The manifest** lists the release and run IDs, the analysis commit A,
#' the digests of the requirements and inventory, and every bundle file with
#' its SHA-256. It does not hash itself and names no evidence commit,
#' approval or tag. Its own SHA-256 is the digest the approval and tag repeat.
#'
#' The build stops (class `dctools_release_error`) unless HEAD is A, the
#' working tree is clean apart from the ledger directory and the bundle, the
#' run was ledgered from a clean tree at A, and the bundle directory does not
#' exist yet.
#'
#' @param release_id From [allocate_release_id()].
#' @param ledger_path The release run's ledger (`<run_id>.json`).
#' @param lock `NULL`, or a list with the arguments the project passes to
#'   [check_computation_lock()]: `links`, `config` and optionally `path`.
#' @param requirements,unresolved Paths, relative to `repo`, of the
#'   requirements (`contracts/requirements.yml`) and the unresolved-item
#'   inventory (`records/unresolved.yml`).
#' @param store,script The targets store and script; default to the
#'   project's configuration.
#' @param repo The project root (a git repository).
#' @return Invisibly, a list with the bundle directory, the manifest path and
#'   the manifest's SHA-256.
#' @seealso [allocate_release_id()], [export_run_evidence()].
#' @export
build_release_bundle <- function(
  release_id,
  ledger_path,
  lock = NULL,
  requirements = "contracts/requirements.yml",
  unresolved = "records/unresolved.yml",
  store = NULL,
  script = NULL,
  repo = "."
) {
  .require_pkgs(c("targets", "jsonlite", "digest", "yaml"), "build_release_bundle")
  if (!is.character(release_id) || length(release_id) != 1L || !grepl(.release_id_pattern, release_id)) {
    .release_error("release_id must come from allocate_release_id()", "dctools_release_id_error")
  }
  ledger_path <- normalizePath(ledger_path, mustWork = TRUE)
  old_wd <- setwd(repo)
  on.exit(setwd(old_wd), add = TRUE)
  repo <- "."
  if (is.null(store)) {
    store <- targets::tar_config_get("store")
  }
  if (is.null(script)) {
    script <- targets::tar_config_get("script")
  }
  bundle_rel <- file.path("evidence", "releases", release_id)
  if (dir.exists(bundle_rel)) {
    .release_error(paste0(bundle_rel, " already exists; release evidence is append-only"), "dctools_release_exists_error")
  }
  ledger <- jsonlite::read_json(ledger_path, simplifyVector = FALSE)
  head <- .git_head(repo)
  ledger_dir <- .ledger_dir_in_repo(dirname(ledger_path), repo)
  dirty <- .git_dirty_files(repo, ledger_dir)
  if (length(dirty)) {
    .release_error("the working tree has uncommitted changes; a release is built from a committed A", "dctools_release_dirty_error")
  }
  if (!identical(.as_chr(ledger$code$sha), head) || !isTRUE(ledger$code$clean)) {
    .release_error("the run was not ledgered from a clean tree at HEAD; rerun the release candidate from A", "dctools_release_origin_error")
  }
  reqs <- .read_requirements(requirements, repo)
  inventory <- .read_unresolved(unresolved, repo)
  audit <- audit_run(ledger_path, store = store, script = script, repo = repo)

  dir.create(bundle_rel, recursive = TRUE)
  # git keeps the bundle's bytes as written (no line-ending conversion), so
  # the manifest's digests hold for the committed blobs on every platform.
  writeChar("* -text\n", file.path(bundle_rel, ".gitattributes"), eos = NULL, useBytes = TRUE)
  export_run_evidence(ledger_path, file.path(bundle_rel, "run"), result = audit, store = store, script = script, repo = repo)
  deliverables <- as.character(unlist(reqs$data$deliverables))
  missing <- deliverables[!file.exists(deliverables)]
  for (d in setdiff(deliverables, missing)) {
    to <- file.path(bundle_rel, "deliverables", d)
    dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
    file.copy(d, to, copy.date = FALSE)
  }
  receipts <- .release_receipts(audit, lock, reqs$data, repo, script)
  .write_json_file(
    list(receipts_schema_version = .receipts_schema_version, release_id = release_id, receipts = receipts),
    file.path(bundle_rel, "receipts.json")
  )
  checklist <- .release_checklist(receipts, reqs, inventory, audit, missing, repo)
  .write_json_file(c(list(release_id = release_id), checklist), file.path(bundle_rel, "checklist.json"))
  writeLines(.checklist_md(checklist, release_id), file.path(bundle_rel, "checklist.md"), useBytes = TRUE)

  manifest_path <- .write_manifest(bundle_rel, release_id, .as_chr(ledger$run$run_id), head, requirements, unresolved)
  digest <- .sha256_file(manifest_path)
  invisible(list(
    dir = bundle_rel,
    manifest = manifest_path,
    manifest_sha256 = digest,
    n_blockers = length(checklist$blockers),
    n_nonwaivable = sum(vapply(checklist$blockers, function(b) isTRUE(b$nonwaivable), logical(1)))
  ))
}
