# Parallel processing ---------------------------------------------------------

#' Configure a local crew parallel controller
#'
#' Creates a [crew::crew_controller_local()] capped by both the requested worker
#' count and available system RAM divided by `memory_per_worker`, so a pipeline
#' does not oversubscribe memory. Requires the `crew` and `ps` packages.
#'
#' @param max_workers Maximum workers to spawn (default `detectCores() - 1`).
#' @param memory_per_worker Target RAM per worker, in GB (default 4).
#' @param name Controller name (default `"dctools_local"`).
#' @return A `crew_controller_local` object for use in a `targets` pipeline.
#' @export
configure_parallel <- function(max_workers = parallel::detectCores() - 1,
                               memory_per_worker = 4,
                               name = "dctools_local") {
  if (!requireNamespace("crew", quietly = TRUE) ||
      !requireNamespace("ps", quietly = TRUE)) {
    cli::cli_abort("{.fn configure_parallel} requires the {.pkg crew} and {.pkg ps} packages.")
  }
  available_ram <- ps::ps_system_memory()$avail / 1024^3
  workers <- max(1L, min(max_workers, floor(available_ram / memory_per_worker)))

  cli::cli_inform(c(
    "i" = "Parallel controller {.val {name}}: {workers} worker{?s}.",
    " " = "~{floor(available_ram / workers)} GB RAM per worker."
  ))
  crew::crew_controller_local(
    name = name,
    workers = workers,
    tasks_max = 10,
    seconds_idle = 15,
    garbage_collection = FALSE
  )
}
