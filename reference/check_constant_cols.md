# Identify constant or all-missing columns

Identify constant or all-missing columns

## Usage

``` r
check_constant_cols(data)
```

## Arguments

- data:

  A data frame.

## Value

A data frame: `column`, `issue` ("all missing" or "constant"),
`n_unique` (non-missing unique values). Empty when none.
