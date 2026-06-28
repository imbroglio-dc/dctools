# Detect disguised-missing sentinel values

Scans for values that commonly encode missingness but are not stored as
`NA`: numeric codes (e.g. `-9`, `999`) and string tokens (e.g. `""`,
`"N/A"`, `"unknown"`, whitespace-only). Never modifies the data; returns
a report so you can decide what to convert.

## Usage

``` r
detect_missing_sentinels(
  data,
  numeric_codes = c(-9, -99, -999, -9999, 99, 999, 9999),
  string_tokens = c("", "NA", "N/A", ".", "null", "none", "missing", "unknown", "-",
    "--"),
  ignore_case = TRUE
)
```

## Arguments

- data:

  A data frame.

- numeric_codes:

  Numeric vector of suspect codes.

- string_tokens:

  Character vector of suspect tokens (compared after trimming
  whitespace).

- ignore_case:

  Logical; case-insensitive token matching (default `TRUE`).

## Value

A data frame with one row per column/sentinel found: `column`, `type`,
`sentinel`, `n`, `prop`.
