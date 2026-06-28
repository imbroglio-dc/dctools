# Estimated GFR via the CKD-EPI 2021 (race-free) creatinine equation

Vectorised. Serum creatinine in mg/dL, age in years. Returns `NA` where
any input is `NA` or `scr <= 0`.

## Usage

``` r
ckd_epi_2021(scr, age, is_female)
```

## Arguments

- scr:

  Numeric. Serum creatinine (mg/dL).

- age:

  Numeric. Age (years).

- is_female:

  Logical. `TRUE` for female, `FALSE` for male.

## Value

Numeric vector of eGFR (mL/min/1.73 m^2).

## References

Inker LA, et al. NEJM 2021.
[doi:10.1056/NEJMoa2102953](https://doi.org/10.1056/NEJMoa2102953)

## Examples

``` r
ckd_epi_2021(scr = c(0.8, 1.4), age = c(60, 72), is_female = c(TRUE, FALSE))
#> [1] 84.29815 53.40146
```
