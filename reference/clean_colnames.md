# Clean column names to snake_case

Wraps
[`janitor::make_clean_names()`](https://sfirke.github.io/janitor/reference/make_clean_names.html)
to convert names to snake_case: transliterates non-ASCII characters,
splits camelCase, replaces runs of non-alphanumeric characters with `_`,
lower-cases, and de-duplicates with a numeric suffix. The before/after
map is attached as the `"colname_map"` attribute.

## Usage

``` r
clean_colnames(data)
```

## Arguments

- data:

  A data frame.

## Value

`data` with cleaned names and a `"colname_map"` attribute (a data frame
with `old` and `new` columns).
