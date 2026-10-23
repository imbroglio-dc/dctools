# Write `lines` to <tempdir>/user.R and source it with source references, the
# way a project's _targets.R sources its functions. Returns the environment.
source_user_code <- function(
  lines,
  env = new.env(),
  .local_envir = parent.frame()
) {
  dir <- withr::local_tempdir(.local_envir = .local_envir)
  path <- file.path(dir, "user.R")
  writeLines(lines, path)
  source(path, local = env, keep.source = TRUE)
  env
}
