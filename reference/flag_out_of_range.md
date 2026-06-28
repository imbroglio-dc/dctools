# Flag values outside an expected numeric range

Returns the indices (and values) of `x` that fall below `lo` or above
`hi`. Useful for codebook range checks during data cleaning. `NA` values
are ignored.

## Usage

``` r
flag_out_of_range(x, lo = -Inf, hi = Inf, label = NULL)
```

## Arguments

- x:

  Numeric vector.

- lo, hi:

  Inclusive lower/upper bounds. Use `-Inf`/`Inf` to disable a side.

- label:

  Optional name for messaging.

## Value

Invisibly, a data frame with columns `index` and `value` for each
out-of-range element (empty when all in range).

## Examples

``` r
flag_out_of_range(c(5, 200, NA, -1), lo = 0, hi = 100, label = "sbp")
#> Warning: 2 sbp outside [0, 100].
```
