#' Stamp a rendered record with the run that produced it
#'
#' Called in a Quarto (or R Markdown) record built by a targets pipeline,
#' in a chunk with `results = "asis"`. Prints one human-readable line (run
#' id, git commit, dctools version) and an HTML comment holding the same
#' data plus the SHA-256 of each stored object the record read.
#' [write_run_ledger()] reads the comment back and the audit (check C7)
#' compares it with the ledger.
#'
#' @param targets_read Names of the targets the record reads.
#' @param store The targets store. Pass it explicitly from a Quarto
#'   document, which renders in its own directory (e.g.
#'   `here::here("_targets")`); defaults to the store of the current
#'   project.
#' @param run_id The run id; defaults to the `DCTOOLS_RUN_ID` environment
#'   variable that [run_targets_safe()] sets.
#' @param repo The git repository.
#' @return The stamp (a list with `run_id`, `sha`, `dctools_version`,
#'   `objects`), invisibly.
#' @seealso [write_run_ledger()], [audit_run()].
#' @examples
#' \dontrun{
#' stamp_record(c("eb_run_status", "eb_evidence_prep"),
#'              store = here::here("data", "processed", "_targets"))
#' }
#' @export
stamp_record <- function(
  targets_read,
  store = NULL,
  run_id = Sys.getenv("DCTOOLS_RUN_ID"),
  repo = "."
) {
  .require_pkgs(c("jsonlite", "digest"), "stamp_record")
  if (is.null(store)) {
    .require_pkgs("targets", "stamp_record")
    store <- targets::tar_config_get("store")
  }
  objects <- stats::setNames(
    lapply(targets_read, function(nm) .sha256_file(.object_path(store, nm))),
    targets_read
  )
  stamp <- list(
    run_id = run_id,
    sha = .git_head(repo),
    dctools_version = as.character(utils::packageVersion("dctools")),
    objects = objects
  )
  cat(
    "Run ",
    run_id,
    " | commit ",
    stamp$sha,
    " | dctools ",
    stamp$dctools_version,
    "\n\n",
    sep = ""
  )
  cat(
    "<!-- dctools-stamp ",
    as.character(jsonlite::toJSON(stamp, auto_unbox = TRUE, null = "null")),
    " -->\n",
    sep = ""
  )
  invisible(stamp)
}

.parse_stamps <- function(path) {
  if (!file.exists(path)) {
    return(list())
  }
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")
  found <- regmatches(
    text,
    gregexpr("<!-- dctools-stamp \\{.*?\\} -->", text, perl = TRUE)
  )[[1]]
  # A stamp that is not valid JSON becomes an empty stamp, so it still counts
  # and fails C7 (no run id, commit or objects) instead of crashing.
  lapply(sub("^<!-- dctools-stamp (\\{.*\\}) -->$", "\\1", found), function(x) {
    parsed <- tryCatch(
      jsonlite::fromJSON(x, simplifyVector = FALSE),
      error = function(e) list()
    )
    if (is.list(parsed)) parsed else list()
  })
}
