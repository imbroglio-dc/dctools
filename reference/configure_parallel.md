# Configure a local crew parallel controller

Creates a
[`crew::crew_controller_local()`](https://wlandau.github.io/crew/reference/crew_controller_local.html)
capped by both the requested worker count and available system RAM
divided by `memory_per_worker`, so a pipeline does not oversubscribe
memory. Requires the `crew` and `ps` packages.

## Usage

``` r
configure_parallel(
  max_workers = parallel::detectCores() - 1,
  memory_per_worker = 4,
  name = "dctools_local"
)
```

## Arguments

- max_workers:

  Maximum workers to spawn (default `detectCores() - 1`).

- memory_per_worker:

  Target RAM per worker, in GB (default 4).

- name:

  Controller name (default `"dctools_local"`).

## Value

A `crew_controller_local` object for use in a `targets` pipeline.
