# Clean column names to snake_case

Splits camelCase, lower-cases, replaces runs of non-alphanumeric
characters with `_`, trims, and de-duplicates. The before/after map is
attached as the `"colname_map"` attribute.

## Usage

``` r
clean_colnames(data)
```

## Arguments

- data:

  A data frame.

## Value

`data` with cleaned names and a `"colname_map"` attribute.
