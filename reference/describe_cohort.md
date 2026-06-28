# One-call cohort QC description

Bundles a per-column overview with the QC screens (`check_colnames`,
`check_types`, `check_constant_cols`, `detect_missing_sentinels`,
`check_collinearity`) into a single structured report. Suitable for
diffing across data refreshes.

## Usage

``` r
describe_cohort(data)
```

## Arguments

- data:

  A data frame.

## Value

A named list: `dims`, `overview`, `colname_issues`, `type_issues`,
`constant_cols`, `missing_sentinels`, `collinearity`.
