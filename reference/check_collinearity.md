# Find highly correlated numeric column pairs

Pairwise Pearson correlation across numeric columns, returning pairs at
or above `threshold` in absolute value, sorted by strength. A first-pass
redundancy screen (extend with VIF / Cramer's V as needed).

## Usage

``` r
check_collinearity(data, threshold = 0.9)
```

## Arguments

- data:

  A data frame.

- threshold:

  Absolute correlation cutoff (default 0.9).

## Value

A data frame: `col1`, `col2`, `correlation`, sorted by
[`abs()`](https://rdrr.io/r/base/MathFun.html). Empty when fewer than
two numeric columns or no pair qualifies.
