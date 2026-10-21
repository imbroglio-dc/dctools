local_git_repo <- function(env = parent.frame()) {
  skip_if_not(nzchar(Sys.which("git")), "git is not installed")
  dir <- withr::local_tempdir(.local_envir = env)
  run <- function(...) {
    system2("git", c("-C", dir, ...), stdout = TRUE, stderr = TRUE)
  }
  run("init", "-q")
  run("config", "user.email", "test@example.com")
  run("config", "user.name", "test")
  writeLines("x", file.path(dir, "a.txt"))
  run("add", "-A")
  run("commit", "-q", "-m", "init")
  dir
}

test_that("git helpers read HEAD, dirty files and strip remote credentials", {
  repo <- local_git_repo()
  expect_match(.git_head(repo), "^[0-9a-f]{40}$")
  expect_identical(.git_dirty_files(repo, "docs/runs"), character(0))
  dir.create(file.path(repo, "docs", "runs"), recursive = TRUE)
  writeLines("{}", file.path(repo, "docs", "runs", "x.json"))
  writeLines("y", file.path(repo, "new file.txt"))
  expect_identical(.git_dirty_files(repo, "docs/runs"), "new file.txt")
  expect_identical(.git_remote(repo), NA_character_)
  system2(
    "git",
    c(
      "-C",
      repo,
      "remote",
      "add",
      "origin",
      "https://user:tok3n@example.com/o/r.git"
    )
  )
  expect_identical(.git_remote(repo), "https://example.com/o/r.git")
  expect_error(
    .git(repo, c("cat-file", "-e", "deadbeef")),
    class = "dctools_git_error"
  )
  expect_false(.git_ok(repo, c("cat-file", "-e", "deadbeef")))
})

test_that(".web_url turns remotes into browsable https URLs", {
  expect_identical(.web_url("git@github.com:o/r.git"), "https://github.com/o/r")
  expect_identical(
    .web_url("https://github.com/o/r.git"),
    "https://github.com/o/r"
  )
  expect_identical(.web_url(NA_character_), NA_character_)
  expect_identical(.web_url("/local/path"), NA_character_)
})

test_that(".sha256_file matches digest and is NA for a missing file", {
  skip_if_not_installed("digest")
  f <- withr::local_tempfile(lines = "abc")
  expect_identical(.sha256_file(f), digest::digest(file = f, algo = "sha256"))
  expect_identical(
    .sha256_file(file.path(tempdir(), "no-such-file")),
    NA_character_
  )
})

test_that("stamp_record prints a readable line and a stamp that parses back", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("digest")
  repo <- local_git_repo()
  store <- file.path(repo, "_targets")
  dir.create(file.path(store, "objects"), recursive = TRUE)
  saveRDS(1:3, file.path(store, "objects", "evidence"))
  out <- capture.output(
    stamp <- stamp_record(
      "evidence",
      store = store,
      run_id = "20260101-000000",
      repo = repo
    )
  )
  expect_match(
    out[1],
    "^Run 20260101-000000 \\| commit [0-9a-f]{40} \\| dctools "
  )
  html <- withr::local_tempfile(fileext = ".html")
  writeLines(c("<p>before</p>", out, "<p>after</p>"), html)
  parsed <- .parse_stamps(html)
  expect_length(parsed, 1L)
  expect_identical(parsed[[1]]$run_id, "20260101-000000")
  expect_identical(parsed[[1]]$sha, .git_head(repo))
  expect_identical(
    parsed[[1]]$objects$evidence,
    .sha256_file(file.path(store, "objects", "evidence"))
  )
  expect_identical(stamp$objects$evidence, parsed[[1]]$objects$evidence)
})

test_that(".strip_credentials removes everything up to the last @ before the host", {
  expect_identical(
    .strip_credentials("https://us:p@ss@host/x"),
    "https://host/x"
  )
  expect_identical(.strip_credentials("https://tok@host/x"), "https://host/x")
})
