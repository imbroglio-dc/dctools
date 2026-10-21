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

.git_dirty_files <- function(repo, exclude) {
  status <- .git(repo, c("status", "--porcelain", "--untracked-files=all"))
  paths <- sub('^"(.*)"$', "\\1", sub("^.* -> ", "", substring(status, 4L)))
  prefix <- paste0(sub("/+$", "", exclude), "/")
  paths[!startsWith(paths, prefix)]
}

.is_absolute <- function(path) grepl("^(/|[A-Za-z]:[/\\\\])", path)

.repo_relative <- function(path, root) {
  if (.is_missing(path)) {
    return(NA_character_)
  }
  prefix <- paste0(sub("/+$", "", root), "/")
  if (startsWith(path, prefix)) substring(path, nchar(prefix) + 1L) else path
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
  url <- sub("^git@([^:]+):", "https://\\1/", remote)
  url <- sub("^ssh://git@", "https://", url)
  url <- sub("\\.git$", "", url)
  if (grepl("^https?://", url)) url else NA_character_
}

.as_chr <- function(x) {
  if (.is_missing(x)) NA_character_ else as.character(x)
}
