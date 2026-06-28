# Check that a column (or set of columns) uniquely identifies rows

Check that a column (or set of columns) uniquely identifies rows

## Usage

``` r
check_unique_id(data, id, error = TRUE)
```

## Arguments

- data:

  A data frame.

- id:

  Character vector of key column name(s).

- error:

  Logical; if `TRUE` (default) abort on duplicates, otherwise warn and
  return the duplicated keys.

## Value

Invisibly, a data frame of duplicated keys with their counts (empty when
the key is unique).

## Examples

``` r
df <- data.frame(id = c(1, 1, 2), x = 1:3)
check_unique_id(df, "id", error = FALSE)
#> Warning: `id` ("id") does not uniquely identify rows: 1 duplicated key.
```
