# Flag problematic column names

Reports columns whose names are empty, non-syntactic, contain whitespace
or leading/trailing spaces, contain non-ASCII characters, are
duplicated, or collide with another name only by case.

## Usage

``` r
check_colnames(data)
```

## Arguments

- data:

  A data frame.

## Value

A data frame with `column` and a comma-separated `issues` string, one
row per problematic name (empty when all names are clean).
