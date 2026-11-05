# Closed runner-output schema -----------------------------------------------------
#
# What run_targets_safe() may print is decided by where each string came from.
# Identifiers in the committed source may appear: target names from
# tar_manifest(), and the symbols and identifier-shaped string constants of the
# project's R files. Nothing derived from data may: dynamic branches, whose
# names hash their data, are folded into their pattern with a masked count, and
# integers are masked below the threshold. A line that does not fit is withheld
# from stdout and kept in the private runner log. This holds only if the
# committed source itself passes the publish test.

.output_schema_version <- 1L

.token_types <- c(
  "SYMBOL",
  "SYMBOL_FUNCTION_CALL",
  "SYMBOL_SUB",
  "SYMBOL_FORMALS",
  "SYMBOL_PACKAGE",
  "STR_CONST"
)

.tokens_in_file <- function(path) {
  exprs <- tryCatch(
    parse(path, keep.source = TRUE),
    error = function(e) NULL,
    warning = function(w) NULL
  )
  pd <- if (is.null(exprs)) NULL else utils::getParseData(exprs)
  if (is.null(pd) || !nrow(pd)) {
    return(character(0))
  }
  symbols <- gsub("^`|`$", "", pd$text[pd$token %in% setdiff(.token_types, "STR_CONST")])
  # A string constant contributes its identifier-shaped words: "prep: " gives
  # prep. They are source text, whatever the data hold.
  strings <- pd$text[pd$token == "STR_CONST"]
  words <- unlist(regmatches(strings, gregexpr("[A-Za-z][A-Za-z0-9_.]*", strings)))
  text <- c(symbols, words)
  unique(text[grepl(.safe_name_pattern, text)])
}

# The project's R files: tracked by git when the project is a repository,
# otherwise _targets.R and the R files under R/ and code/.
.project_r_files <- function(repo = ".") {
  tracked <- tryCatch(
    .git(repo, c("ls-files", "--", "*.R", "*.r")),
    error = function(e) NULL
  )
  if (!is.null(tracked)) {
    return(file.path(repo, tracked))
  }
  c(
    file.path(repo, "_targets.R")[file.exists(file.path(repo, "_targets.R"))],
    list.files(
      file.path(repo, c("R", "code")),
      pattern = "\\.[Rr]$",
      recursive = TRUE,
      full.names = TRUE
    )
  )
}

.output_allowlist <- function(target_names, repo = ".") {
  files <- .project_r_files(repo)
  files <- files[file.exists(files)]
  unique(c(target_names, unlist(lapply(files, .tokens_in_file))))
}

# name -> pattern, for the dynamic branches in the store.
.branch_parents <- function(store) {
  meta <- tryCatch(
    as.data.frame(targets::tar_meta(
      fields = c("type", "parent"),
      targets_only = TRUE,
      store = store
    )),
    error = function(e) NULL
  )
  if (is.null(meta) || !all(c("name", "type", "parent") %in% names(meta))) {
    return(character(0))
  }
  branches <- meta[meta$type %in% "branch" & !is.na(meta$parent), , drop = FALSE]
  stats::setNames(as.character(branches$parent), branches$name)
}

# "<pattern>: <n> branches <progress>", one line per pattern and progress, with
# the count masked: how many branches a pattern has can depend on the data.
.branch_lines <- function(progress, parents, mask_below) {
  is_branch <- progress$name %in% names(parents)
  if (!any(is_branch)) {
    return(character(0))
  }
  rows <- progress[is_branch, , drop = FALSE]
  rows$parent <- unname(parents[rows$name])
  keys <- unique(rows[, c("parent", "progress")])
  keys <- keys[grepl(.safe_name_pattern, keys$progress), , drop = FALSE]
  vapply(
    seq_len(nrow(keys)),
    function(i) {
      n <- sum(rows$parent == keys$parent[i] & rows$progress == keys$progress[i])
      sprintf(
        "%s: %s branches %s",
        keys$parent[i],
        .mask_count(n, mask_below),
        keys$progress[i]
      )
    },
    ""
  )
}

.masked_value_pattern <- "^(<?[0-9]+)$"

# A status line is "<indent><identifier>: <value>", where the identifier is in
# the allowlist and the value is an integer (masked here) or an allowlisted
# identifier. Anything else is withheld.
.schema_status_line <- function(line, allowlist, mask_below) {
  m <- regmatches(line, regexec("^( *)([A-Za-z][A-Za-z0-9_.]*): (.+)$", line))[[1]]
  if (length(m) != 4L || !m[[3]] %in% allowlist) {
    return(NA_character_)
  }
  value <- m[[4]]
  if (grepl("^[0-9]+$", value)) {
    value <- .mask_count(as.numeric(value), mask_below)
  } else if (!(grepl("^<[0-9]+$", value) || value %in% allowlist)) {
    return(NA_character_)
  }
  paste0(m[[2]], m[[3]], ": ", value)
}

# Status lines that fit the schema, with a placeholder for each that does not;
# attr(, "withheld") holds the withheld originals for the private log.
.schema_status_lines <- function(lines, allowlist, mask_below) {
  is_header <- grepl("^-- [A-Za-z][A-Za-z0-9_.]* --$", lines)
  out <- lines
  checked <- vapply(
    lines[!is_header],
    .schema_status_line,
    "",
    allowlist = allowlist,
    mask_below = mask_below,
    USE.NAMES = FALSE
  )
  bad <- is.na(checked)
  checked[bad] <- "  [withheld: not in the output schema]"
  out[!is_header] <- checked
  attr(out, "withheld") <- lines[!is_header][bad]
  out
}
