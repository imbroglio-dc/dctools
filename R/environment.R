# Environment capture ------------------------------------------------------------
#
# What a run actually executed under, in two tiers. The computational tier is
# what can change results: assigned to a global in _targets.R and referenced by
# the computational targets, its drift invalidates them through targets
# itself. The full tier is recorded in the run ledger only, since a kernel
# patch or an unrelated package update would otherwise rebuild everything.

.thread_vars <- c(
  "OMP_NUM_THREADS",
  "OPENBLAS_NUM_THREADS",
  "MKL_NUM_THREADS",
  "VECLIB_MAXIMUM_THREADS",
  "RCPP_PARALLEL_NUM_THREADS"
)

.env_var <- function(name) {
  value <- Sys.getenv(name, unset = NA)
  if (is.na(value)) NA_character_ else value
}

.package_identity <- function(package) {
  d <- suppressWarnings(utils::packageDescription(package))
  if (!is.list(d)) {
    return(list(
      package = package,
      version = NA_character_,
      remote_sha = NA_character_
    ))
  }
  list(
    package = package,
    version = .as_chr(d$Version),
    remote_sha = .as_chr(d$RemoteSha)
  )
}

.computational_env <- function(packages) {
  threads <- lapply(.thread_vars, .env_var)
  names(threads) <- .thread_vars
  list(
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    blas = .as_chr(extSoftVersion()[["BLAS"]]),
    lapack = .as_chr(La_library()),
    lapack_version = .as_chr(La_version()),
    rng_kind = I(RNGkind()),
    collate = Sys.getlocale("LC_COLLATE"),
    threads = threads,
    mc_cores = .as_chr(getOption("mc.cores")),
    packages = lapply(sort(unique(packages)), .package_identity)
  )
}

# Sys.info()'s nodename and user identify a machine and a person, not the
# software, so they are left out.
.full_env <- function() {
  info <- Sys.info()
  installed <- utils::installed.packages(fields = "RemoteSha")
  list(
    platform = R.version$platform,
    os = list(
      sysname = .as_chr(info[["sysname"]]),
      release = .as_chr(info[["release"]]),
      version = .as_chr(info[["version"]]),
      machine = .as_chr(info[["machine"]])
    ),
    locale = Sys.getlocale(),
    time_zone = .as_chr(Sys.timezone()),
    tz_env = .env_var("TZ"),
    library_paths = I(.libPaths()),
    installed = lapply(seq_len(nrow(installed)), function(i) {
      list(
        package = installed[i, "Package"],
        version = installed[i, "Version"],
        remote_sha = .as_chr(installed[i, "RemoteSha"]),
        library = installed[i, "LibPath"]
      )
    })
  )
}

#' Capture the environment a pipeline runs under
#'
#' Returns what the current R process is executing under, in two tiers.
#'
#' * `computational`: the R version, the BLAS and LAPACK libraries, the RNG
#'   kind, the collation locale (it sets sort order, and so factor levels
#'   and reference categories), the thread-count environment variables and
#'   `mc.cores`, and the version and `RemoteSha` of each package named in
#'   `packages`. `RemoteSha` matters for packages installed from GitHub,
#'   whose version string often stays the same while their code changes.
#' * `full` (when `full = TRUE`): the platform, the operating system and
#'   kernel release, all locale categories, the time zone, the library paths
#'   and every installed package with its version, `RemoteSha` and library.
#'   The machine's name and the user are not recorded.
#'
#' [write_run_ledger()] records both tiers. To make computational targets
#' rebuild when the computational tier drifts, assign it to a global in
#' `_targets.R` and reference that global in their commands; targets then
#' tracks it like any other dependency:
#' ```
#' env_fingerprint <- dctools::capture_environment(c("glmnet", "survival"))$computational
#' list(
#'   tar_target(fit, {
#'     env_fingerprint
#'     fit_model(analysis_data)
#'   })
#' )
#' ```
#' A target with `cue = tar_cue(mode = "always")` is not a substitute: targets
#' then reports it and everything downstream as outdated after every run.
#'
#' @param packages Names of the packages that do the core computation, for
#'   the computational tier.
#' @param full Whether to capture the full tier as well.
#' @return A list with elements `computational` and `full` (`NULL` when
#'   `full = FALSE`).
#' @seealso [write_run_ledger()].
#' @examples
#' env <- capture_environment("stats", full = FALSE)
#' env$computational$r_version
#' @export
capture_environment <- function(packages = character(0), full = TRUE) {
  if (!is.character(packages) || anyNA(packages)) {
    cli::cli_abort("{.arg packages} must be a character vector of package names.")
  }
  list(
    computational = .computational_env(packages),
    full = if (isTRUE(full)) .full_env()
  )
}
