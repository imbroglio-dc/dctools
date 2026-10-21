# Human-readable audit output ---------------------------------------------------
#
# <run_id>.md: the verdict, one row per check, what did not pass, and the
# commands that verify C1, C5 and C9 by hand. <run_id>.provenance.md: each
# reported value (masked as in its report) with the code that computed it,
# grouped by file and function. Neither holds anything the reports would not
# print.

.max_listed <- 10L

.is_sha <- function(x) {
  !is.na(x) && grepl("^[0-9a-f]{40}$", x)
}

.render_audit_md <- function(ledger, result) {
  run_id <- .as_chr(ledger$run$run_id)
  sha <- .as_chr(ledger$code$sha)
  web <- .web_url(.as_chr(ledger$code$remote))
  sha_ok <- .is_sha(sha)
  engine_sha <- .as_chr(ledger$code$dctools_remote_sha)
  if (!.is_sha(engine_sha)) {
    engine_sha <- "unknown"
  }
  commit <- if (is.na(web) || !sha_ok) {
    sprintf("`%s`", sha)
  } else {
    sprintf("[`%s`](%s/tree/%s)", sha, web, sha)
  }
  out <- c(
    sprintf("# Run %s audit: %s", run_id, attr(result, "verdict")),
    "",
    sprintf(
      "- Commit: %s (%s)",
      commit,
      if (isTRUE(ledger$code$clean)) "clean" else "uncommitted changes"
    ),
    sprintf(
      "- dctools: %s (commit %s)",
      .as_chr(ledger$code$dctools_version),
      engine_sha
    ),
    sprintf(
      "- Ledger: `%s.json`; provenance: `%s.provenance.md`",
      run_id,
      run_id
    ),
    "",
    "| Check | Name | Status | Evaluated | Failed |",
    "|---|---|---|---|---|",
    sprintf(
      "| %s | %s | %s | %d | %d |",
      result$check,
      result$name,
      result$status,
      result$n_evaluated,
      result$n_failed
    )
  )
  not_passed <- which(result$status != "PASS")
  if (length(not_passed)) {
    out <- c(out, "", "## Not passed")
    for (i in not_passed) {
      d <- result$detail[[i]]
      out <- c(
        out,
        "",
        sprintf(
          "### %s %s: %s",
          result$check[i],
          result$name[i],
          result$status[i]
        ),
        "",
        if (length(d)) paste0("- ", utils::head(d, .max_listed))
      )
      if (length(d) > .max_listed) {
        out <- c(
          out,
          sprintf("- ... and %d more (see the ledger)", length(d) - .max_listed)
        )
      }
    }
  }
  files <- c(
    vapply(ledger$inputs, function(x) .as_chr(x$path), ""),
    vapply(ledger$documents, function(x) .as_chr(x$path), "")
  )
  c1 <- .first_code_ref(ledger$provenance)
  c(
    out,
    "",
    "## Verify by hand",
    "",
    "From the project root:",
    "",
    "```sh",
    if (sha_ok) {
      sprintf(
        "git cat-file -e %s^{commit} && echo 'C1: the commit exists'",
        sha
      )
    } else {
      "(the ledger's commit is not a valid SHA; nothing to verify)"
    },
    if (sha_ok && length(c1)) {
      sprintf(
        "git show %s | sed -n '%d,%dp'   # C1: compare with the code in %s.provenance.md",
        shQuote(paste0(sha, ":", c1$file)),
        c1$start,
        c1$end,
        run_id
      )
    },
    if (length(files)) {
      sprintf(
        "sha256sum %s   # C5: compare with \"sha256\" in %s.json",
        paste(shQuote(files), collapse = " "),
        run_id
      )
    },
    "Rscript -e 'utils::packageDescription(\"dctools\")$RemoteSha'   # C9: compare with the dctools commit above",
    "```"
  )
}

.first_code_ref <- function(prov) {
  for (p in prov) {
    f <- .as_chr(p$file)
    start <- .int_or_na(p$line_start)
    end <- .int_or_na(p$line_end)
    if (!is.na(f) && !is.na(start) && !is.na(end) && !startsWith(f, "/")) {
      return(list(file = f, start = start, end = end))
    }
  }
  NULL
}

.resolve_value <- function(report, id) {
  if (is.null(report)) {
    return("(report not available)")
  }
  if (startsWith(id, "~")) {
    return("(not printed)")
  }
  .prepare_report_for_printing(report)
  report$resolver(paste0("{{", id, "}}"))
}

.number_lines <- function(code, start) {
  if (.is_missing(code)) {
    return("(no source)")
  }
  lines <- strsplit(code, "\n", fixed = TRUE)[[1]]
  sprintf("%d | %s", start + seq_along(lines) - 1L, lines)
}

.render_provenance_md <- function(ledger, reports) {
  run_id <- .as_chr(ledger$run$run_id)
  sha <- .as_chr(ledger$code$sha)
  web <- if (.is_sha(sha)) {
    .web_url(.as_chr(ledger$code$remote))
  } else {
    NA_character_
  }
  out <- c(
    sprintf("# Run %s: where each reported value came from", run_id),
    "",
    sprintf("Code at commit `%s`. Values are masked as in their reports.", sha)
  )
  prov <- ledger$provenance
  if (!length(prov)) {
    return(c(out, "", "No reported values."))
  }
  files <- vapply(prov, function(p) .as_chr(p$file), "")
  files[is.na(files)] <- "(no source file)"
  for (f in sort(unique(files))) {
    out <- c(out, "", paste0("## ", f))
    in_file <- prov[files == f]
    fns <- vapply(in_file, function(p) .as_chr(p$function_name), "")
    fns[is.na(fns)] <- "(no function)"
    for (fn in unique(fns)) {
      first <- in_file[[which(fns == fn)[1]]]
      out <- c(
        out,
        "",
        sprintf(
          "### %s() (lines %s-%s)",
          fn,
          .as_chr(first$function_line_start),
          .as_chr(first$function_line_end)
        )
      )
      for (p in in_file[fns == fn]) {
        start <- .int_or_na(p$line_start)
        end <- .int_or_na(p$line_end)
        link <- if (is.na(web) || f == "(no source file)" || is.na(start)) {
          ""
        } else {
          sprintf(
            " ([L%d-L%d](%s/blob/%s/%s#L%d-L%d))",
            start,
            end,
            web,
            sha,
            f,
            start,
            end
          )
        }
        out <- c(
          out,
          "",
          sprintf(
            "- `%s` / `%s` = `%s`%s",
            .as_chr(p$report),
            .as_chr(p$id),
            .resolve_value(reports[[.as_chr(p$report)]], .as_chr(p$id)),
            link
          ),
          "",
          "  ```r",
          paste0("  ", .number_lines(.as_chr(p$code), start)),
          "  ```"
        )
      }
    }
  }
  out
}

.write_audit_files <- function(ledger, result, reports, dir) {
  run_id <- .as_chr(ledger$run$run_id)
  writeLines(
    .render_audit_md(ledger, result),
    file.path(dir, paste0(run_id, ".md"))
  )
  writeLines(
    .render_provenance_md(ledger, reports),
    file.path(dir, paste0(run_id, ".provenance.md"))
  )
  invisible(NULL)
}
