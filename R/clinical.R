# Clinical formulas -----------------------------------------------------------

#' Estimated GFR via the CKD-EPI 2021 (race-free) creatinine equation
#'
#' Vectorised. Serum creatinine in mg/dL, age in years. Returns `NA` where any
#' input is `NA` or `scr <= 0`.
#'
#' @param scr Numeric. Serum creatinine (mg/dL).
#' @param age Numeric. Age (years).
#' @param is_female Logical. `TRUE` for female, `FALSE` for male.
#' @return Numeric vector of eGFR (mL/min/1.73 m^2).
#' @references Inker LA, et al. NEJM 2021. \doi{10.1056/NEJMoa2102953}
#' @examples
#' ckd_epi_2021(scr = c(0.8, 1.4), age = c(60, 72), is_female = c(TRUE, FALSE))
#' @export
ckd_epi_2021 <- function(scr, age, is_female) {
  kappa <- dplyr::if_else(is_female, 0.7, 0.9)
  alpha <- dplyr::if_else(is_female, -0.241, -0.302)
  sex_factor <- dplyr::if_else(is_female, 1.012, 1.000)
  valid <- !is.na(scr) & !is.na(age) & !is.na(is_female) & scr > 0

  dplyr::if_else(
    valid,
    142 *
      (pmin(scr / kappa, 1)^alpha) *
      (pmax(scr / kappa, 1)^-1.2) *
      (0.9938^age) *
      sex_factor,
    NA_real_
  )
}
