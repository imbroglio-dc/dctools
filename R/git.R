# Git and hashing helpers (internal) -------------------------------------------
#
# The git CLI is used, not gert, so that every command the audit runs is one
# a person can run by hand to check it.

# Every argument is quoted: system2() pastes them into a shell command, and
# paths can hold spaces and pathspecs like "*.R" must reach git unexpanded.
.git <- function(repo, args) {
  out <- suppressWarnings(system2(
    "git",
    shQuote(c("-C", repo, args)),
    stdout = TRUE,
    stderr = FALSE
  ))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop(structure(
      class = c("dctools_git_error", "error", "condition"),
      list(
        message = paste0("git ", paste(args, collapse = " "), " failed"),
        call = NULL
      )
    ))
  }
  out
}

.git_ok <- function(repo, args) {
  tryCatch(
    {
      .git(repo, args)
      TRUE
    },
    dctools_git_error = function(e) FALSE
  )
}

.git_head <- function(repo) .git(repo, c("rev-parse", "HEAD"))

.git_root <- function(repo) {
  normalizePath(.git(repo, c("rev-parse", "--show-toplevel")), winslash = "/")
}

.strip_credentials <- function(url) sub("^(https?://)[^/]*@", "\\1", url)

.git_remote <- function(repo) {
  url <- tryCatch(
    .git(repo, c("remote", "get-url", "origin")),
    dctools_git_error = function(e) character(0)
  )
  if (length(url)) .strip_credentials(url[[1]]) else NA_character_
}

# Uncommitted or untracked files, outside the directory `exclude` and other
# than the repo-relative files `exclude_files` (the ledger directory and the
# declared records, which a run rewrites and C7 vouches for).
.git_dirty_files <- function(repo, exclude, exclude_files = character(0)) {
  status <- .git(repo, c("status", "--porcelain", "--untracked-files=all"))
  paths <- sub('^"(.*)"$', "\\1", sub("^.* -> ", "", substring(status, 4L)))
  prefix <- paste0(sub("/+$", "", exclude), "/")
  paths[!startsWith(paths, prefix) & !paths %in% exclude_files]
}

# The declared record files as repo-relative paths.
.records_in_repo <- function(records, repo = ".") {
  vapply(records, .ledger_dir_in_repo, "", repo = repo, USE.NAMES = FALSE)
}

.is_absolute <- function(path) grepl("^(/|[A-Za-z]:[/\\\\])", path)

.repo_relative <- function(path, root) {
  if (.is_missing(path)) {
    return(NA_character_)
  }
  prefix <- paste0(sub("/+$", "", root), "/")
  if (startsWith(path, prefix)) substring(path, nchar(prefix) + 1L) else path
}

# The ledger directory as a path relative to the repository root, however it
# was given (relative, "./"-prefixed, absolute) and whether or not it exists
# yet. The deepest existing ancestor is normalised so symlinks match the root.
.ledger_dir_in_repo <- function(path, repo = ".") {
  root <- .git_root(repo)
  path <- gsub("\\\\", "/", path)
  if (!.is_absolute(path)) {
    path <- file.path(getwd(), path)
  }
  path <- sub("/+$", "", gsub("/(\\.(/|$))+", "/", path))
  rest <- character(0)
  head <- path
  while (!file.exists(head) && dirname(head) != head) {
    rest <- c(basename(head), rest)
    head <- dirname(head)
  }
  full <- do.call(
    file.path,
    as.list(c(normalizePath(head, winslash = "/"), rest))
  )
  .repo_relative(full, root)
}

.sha256_file <- function(path) {
  if (.is_missing(path) || !file.exists(path) || dir.exists(path)) {
    return(NA_character_)
  }
  digest::digest(file = path, algo = "sha256")
}

.object_path <- function(store, name) file.path(store, "objects", name)

.web_url <- function(remote) {
  if (.is_missing(remote)) {
    return(NA_character_)
  }
  url <- .strip_credentials(remote)
  url <- sub("^git@([^:]+):", "https://\\1/", url)
  url <- sub("^ssh://git@", "https://", url)
  url <- sub("\\.git$", "", url)
  if (grepl("^https?://", url)) url else NA_character_
}

.as_chr <- function(x) {
  if (.is_missing(x)) NA_character_ else as.character(x)
}
