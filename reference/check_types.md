# Heuristically flag likely column-type problems

Conservative checks that surface common typing issues for review: text
that parses as numeric or as dates, two-valued text that is really
logical, high-cardinality text, and numeric columns that are really
binary.

## Usage

``` r
check_types(data, max_factor_levels = 50)
```

## Arguments

- data:

  A data frame.

- max_factor_levels:

  Above this many unique values, text is flagged as high-cardinality
  (default 50).

## Value

A data frame: `column`, `stored_type`, `issue`, `detail` (one row per
finding; empty when nothing is flagged).
