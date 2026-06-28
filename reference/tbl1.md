# Descriptive "Table 1" via gtsummary

Thin wrapper around
[`gtsummary::tbl_summary()`](https://www.danieldsjoberg.com/gtsummary/reference/tbl_summary.html)
that applies project defaults (median
[IQR](https://rdrr.io/r/stats/IQR.html) for continuous, n (%) for
categorical) and optionally adds an overall column and a by-group
p-value. Requires the `gtsummary` package.

## Usage

``` r
tbl1(
  data,
  by = NULL,
  include = NULL,
  add_overall = !is.null(by),
  add_p = FALSE
)
```

## Arguments

- data:

  A data frame.

- by:

  Optional grouping column, given as a string.

- include:

  Optional character vector of columns to include (default: all).

- add_overall:

  Logical; add an overall column (default `TRUE` when `by` is supplied).

- add_p:

  Logical; add a group comparison p-value (default `FALSE`).

## Value

A `gtsummary` table object.
