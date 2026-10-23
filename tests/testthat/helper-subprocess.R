# Shared by tests that run R in a subprocess (Rscript shims, targets runs).

# The package source when testing from a checkout (load_all); "" when the
# tests run against an installed dctools (R CMD check, covr). An installed
# package also has a DESCRIPTION, so look for the R sources themselves.
dctools_src <- function() {
  src <- getNamespaceInfo(asNamespace("dctools"), "path")
  if (file.exists(file.path(src, "R", "pipeline.R"))) src else ""
}

load_dctools_line <- paste0(
  "if (nzchar(Sys.getenv('DCTOOLS_TEST_SRC'))) ",
  "pkgload::load_all(Sys.getenv('DCTOOLS_TEST_SRC'), quiet = TRUE) ",
  "else library(dctools)"
)

skip_subprocess <- function(pkgs = "processx") {
  skip_on_cran()
  for (p in pkgs) {
    skip_if_not_installed(p)
  }
  if (nzchar(dctools_src())) skip_if_not_installed("pkgload")
}

# Rscript `script` (relative to `wd`) with dctools loadable in the child.
run_rscript <- function(wd, script, args = character(0), env = character(0)) {
  res <- processx::run(
    file.path(R.home("bin"), "Rscript"),
    c(script, args),
    wd = wd,
    error_on_status = FALSE,
    env = c(
      "current",
      DCTOOLS_TEST_SRC = dctools_src(),
      R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
      env
    )
  )
  res$stdout <- gsub("\r\n", "\n", res$stdout, fixed = TRUE)
  res$stderr <- gsub("\r\n", "\n", res$stderr, fixed = TRUE)
  res
}
