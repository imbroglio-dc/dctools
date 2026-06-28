# Assert that required columns are present

Errors (via
[`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)) if
any of `cols` is missing from `data`, naming the offenders. Invisibly
returns `data` so it can be used inline in a pipe.

## Usage

``` r
assert_columns(data, cols)
```

## Arguments

- data:

  A data frame.

- cols:

  Character vector of required column names.

## Value

`data`, invisibly.

## Examples

``` r
df <- data.frame(id = 1:3, age = c(40, 50, 60))
assert_columns(df, c("id", "age"))
```
