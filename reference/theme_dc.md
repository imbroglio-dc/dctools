# House ggplot2 theme

A clean minimal theme used across project figures: no minor grid, muted
axis titles, left-aligned plot title.

## Usage

``` r
theme_dc(base_size = 12, base_family = "")
```

## Arguments

- base_size:

  Base font size (default 12).

- base_family:

  Base font family (default "").

## Value

A ggplot2 theme object.

## Examples

``` r
library(ggplot2)
ggplot(mtcars, aes(wt, mpg)) + geom_point() + theme_dc()
```
