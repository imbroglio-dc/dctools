# Replication / reproducibility ------------------------------------------------

#' Compare computed results against documented targets at their tolerances
#'
#' The mechanical half of a replication or reproducibility check: join each
#' computed value onto its target, take the signed difference, and mark
#' `PASS` / `FAIL` / `UNMATCHED` against the tolerance for that target's `kind`.
#' It returns the comparison *facts* only — the overall verdict vocabulary
#' (e.g. REPLICATED / PARTIAL / FAILED for a replication, PASS / FAIL for a
#' manuscript audit) is the calling skill's judgment, not this function's.
#'
#' Tolerance for a row is resolved in order: an explicit non-`NA` `tolerance`
#' column on `targets` (absolute: `abs(computed - reported) <= tolerance`);
#' otherwise the entry in `tolerances` for the row's `kind`. A `kind` of
#' `"p_value"` is compared by significance level (same bucket across the
#' conventional 0.001 / 0.01 / 0.05 cutpoints), not by numeric difference —
#' encode p-values as their actual value where known.
#'
#' Defaults mirror the replication tolerance table (integers exact; estimates
#' `< 0.01`; SEs `< 0.05`; percentages `< 0.1` pp): `count = 0`,
#' `estimate = 0.01`, `se = 0.05`, `percentage = 0.1`, `summary_stat = 0.01`.
#'
#' @param results Computed values: a data frame with the key column (`by`) and a
#'   `value` column, or a named numeric vector (names are keys).
#' @param targets Documented targets: a data frame with the key column (`by`),
#'   `value` (the reported value), `kind` (tolerance class), and optionally a
#'   per-row `tolerance` override.
#' @param tolerances Optional named list/vector mapping `kind` to a numeric
#'   tolerance; merged over (and so can extend or override) the defaults above.
#' @param by Name of the key column joining `results` to `targets`
#'   (default `"target"`).
#' @return A data frame, one row per target (in `targets` order), with columns
#'   `<by>`, `kind`, `reported`, `computed`, `diff`, `tolerance`, and `status`
#'   (`"PASS"`, `"FAIL"`, or `"UNMATCHED"`). `diff` and `tolerance` are `NA` for
#'   p-value rows.
#' @seealso The `estimation-diagnostics` skill (its `references/replication.md`),
#'   which homes this helper, and the `audit-reproducibility` skill, which uses
#'   it to check manuscript claims against pipeline outputs.
#' @examples
#' targets <- data.frame(
#'   target = c("att", "N"), value = c(-1.632, 2847),
#'   kind = c("estimate", "count")
#' )
#' compare_targets(c(att = -1.628, N = 2847), targets)
#' @export
compare_targets <- function(results, targets, tolerances = NULL, by = "target") {
  if (is.numeric(results) && !is.null(names(results))) {
    results <- data.frame(
      key = names(results), value = unname(results), stringsAsFactors = FALSE
    )
    names(results)[1] <- by
  }
  assert_columns(targets, c(by, "value", "kind"))
  assert_columns(results, c(by, "value"))

  tol <- utils::modifyList(
    .default_tolerances(),
    if (is.null(tolerances)) list() else as.list(tolerances)
  )

  merged <- dplyr::left_join(
    targets, results[, c(by, "value")], by = by, suffix = c("", ".computed")
  )
  reported <- merged[["value"]]
  computed <- merged[["value.computed"]]
  kind <- as.character(merged[["kind"]])
  n <- nrow(merged)
  row_tol <- if ("tolerance" %in% names(targets)) {
    merged[["tolerance"]]
  } else {
    rep(NA_real_, n)
  }

  status <- character(n)
  diff <- rep(NA_real_, n)
  applied_tol <- rep(NA_real_, n)

  for (i in seq_len(n)) {
    if (is.na(computed[i])) {
      status[i] <- "UNMATCHED"
    } else if (!is.na(row_tol[i])) {
      applied_tol[i] <- row_tol[i]
      diff[i] <- computed[i] - reported[i]
      status[i] <- if (abs(diff[i]) <= row_tol[i]) "PASS" else "FAIL"
    } else if (identical(kind[i], "p_value")) {
      status[i] <- if (.sig_bucket(reported[i]) == .sig_bucket(computed[i])) {
        "PASS"
      } else {
        "FAIL"
      }
    } else {
      t <- tol[[kind[i]]]
      if (is.null(t)) {
        cli::cli_abort(c(
          "No tolerance for {.field kind} {.val {kind[i]}}.",
          "i" = "Supply it via {.arg tolerances} or a {.field tolerance} column."
        ))
      }
      applied_tol[i] <- t
      diff[i] <- computed[i] - reported[i]
      status[i] <- if (abs(diff[i]) <= t) "PASS" else "FAIL"
    }
  }

  out <- data.frame(
    key = merged[[by]], kind = kind, reported = reported, computed = computed,
    diff = diff, tolerance = applied_tol, status = status,
    stringsAsFactors = FALSE
  )
  names(out)[1] <- by
  .report_compare(out)
  out
}

# --- internals ----------------------------------------------------------------

.default_tolerances <- function() {
  list(count = 0, estimate = 0.01, se = 0.05, percentage = 0.1, summary_stat = 0.01)
}

# Significance bucket: 0 (<.001), 1 ([.001,.01)), 2 ([.01,.05)), 3 (>=.05).
.sig_bucket <- function(p) findInterval(p, c(0.001, 0.01, 0.05))

.report_compare <- function(out) {
  n_pass <- sum(out$status == "PASS")
  n_fail <- sum(out$status == "FAIL")
  n_un <- sum(out$status == "UNMATCHED")
  msg <- "compare_targets: {n_pass} PASS, {n_fail} FAIL, {n_un} unmatched."
  if (n_fail > 0L || n_un > 0L) cli::cli_warn(msg) else cli::cli_alert_success(msg)
  invisible(out)
}
