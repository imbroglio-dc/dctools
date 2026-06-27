test_that("ckd_epi_2021 returns NA for invalid inputs", {
  expect_true(is.na(ckd_epi_2021(NA, 60, TRUE)))
  expect_true(is.na(ckd_epi_2021(1.0, NA, TRUE)))
  expect_true(is.na(ckd_epi_2021(1.0, 60, NA)))
  expect_true(is.na(ckd_epi_2021(0, 60, TRUE)))
  expect_true(is.na(ckd_epi_2021(-1, 60, TRUE)))
})

test_that("ckd_epi_2021 is vectorised and preserves length", {
  out <- ckd_epi_2021(c(0.8, 1.4, NA), c(60, 72, 50), c(TRUE, FALSE, TRUE))
  expect_length(out, 3)
  expect_true(is.na(out[3]))
})

test_that("ckd_epi_2021 lands in a plausible clinical range", {
  # healthy 60yo woman, Scr 0.8 -> roughly 80s mL/min/1.73m^2
  egfr <- ckd_epi_2021(0.8, 60, TRUE)
  expect_gt(egfr, 70)
  expect_lt(egfr, 95)
})
