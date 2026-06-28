# Read R package names from a plain-text file

Lines beginning with `#` or `//` (after optional whitespace) are treated
as comments and ignored, as are blank lines. Implemented in base R so it
carries no dependencies.

## Usage

``` r
read_packages(path)
```

## Arguments

- path:

  Path to a text file with one package name per line.

## Value

A character vector of package names (de-duplicated, no blanks).

## Examples

``` r
tmp <- tempfile()
writeLines(c("dplyr", "# a comment", "", "ggplot2"), tmp)
read_packages(tmp)
#> [1] "dplyr"   "ggplot2"
```
