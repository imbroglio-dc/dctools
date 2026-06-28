# Suppress small cells in a summary table

Replaces counts in `cols` that fall in `1:(threshold - 1)` with a
marker, so aggregate outputs cannot re-identify individuals. Zero is
left untouched (a true zero is not disclosive); use `mask_zero = TRUE`
to also blank zeros when complementary suppression is a concern.

## Usage

``` r
suppress_small_cells(
  data,
  cols = NULL,
  threshold = 11,
  marker = "<11",
  mask_zero = FALSE
)
```

## Arguments

- data:

  A data frame of *aggregate* counts (never individual-level data).

- cols:

  Columns to screen. Default: all numeric columns.

- threshold:

  Minimum safe cell count (default 11; cells `< threshold` and `> 0` are
  suppressed).

- marker:

  Replacement value for suppressed cells (default `"<11"`).

- mask_zero:

  Logical; also suppress exact zeros (default `FALSE`).

## Value

`data` with suppressed cells replaced by `marker` (affected columns
become character).

## Examples

``` r
tab <- data.frame(group = c("a", "b"), n = c(3, 42))
suppress_small_cells(tab, cols = "n")
#>   group   n
#> 1     a <11
#> 2     b  42
```
