# dctools roadmap

Repeated data-science tasks to package as functions. `[x]` = shipped, `[ ]` = planned.
Grouped by analysis-pipeline stage. Conventions: dplyr surface grammar; arrow/dbplyr
for large data; base R where it keeps dependencies low.

## 1. Ingestion & typing
- [x] `check_types()` — text-as-numeric/date, logical-as-text, high-cardinality, binary-as-numeric
- [x] `check_colnames()` / `clean_colnames()` — non-syntactic, dupes, case-collisions, spaces
- [x] refactor `clean_colnames()` to wrap `janitor::make_clean_names()` (more robust than the hand-rolled gsub chain) while keeping the `colname_map` before/after attribute; `check_colnames()` stays custom (report-only). `janitor` in Suggests, guarded (errors if absent) - see `memos/decisions.md` 2026-07-10.
- [ ] `coerce_types(data, spec)` — apply a declarative/codebook type spec, report coercions + NAs introduced
- [ ] `read_any(path)` — extension dispatch (csv/xlsx/sas7bdat/dta/parquet/rds) + encoding/locale guard

## 2. Missingness & sentinels
- [x] `detect_missing_sentinels()` — disguised-missing numeric codes & string tokens
- [ ] `convert_sentinels(data, rules)` — apply confirmed sentinels -> NA with before/after audit
- [ ] `missingness_report(data, by)` — per-column %, co-occurrence, MCAR/MAR signal
- [ ] `plot_missingness(data)` — vis_miss-style figure on `theme_dc()`

## 3. Validation & QC
- [x] `assert_columns()`, `check_unique_id()`, `flag_out_of_range()`
- [x] `check_constant_cols()` — zero-variance / all-NA
- [x] `describe_cohort()` — one-call structured QC report (diff across data refreshes)
- [ ] `validate_schema(data, spec)` — codebook-driven: columns + types + ranges + key uniqueness
- [ ] `check_duplicate_cols(data)` — identical content under a different name
- [ ] `check_id_consistency(data, id, time)` — panel: ragged IDs, dup (id,time), gaps, non-monotonic
- [ ] `check_dates(data)` — implausible/future dates, end-before-start, DOB/age mismatch

## 4. Redundancy & collinearity
- [x] `check_collinearity()` — numeric correlation pairs (first pass)
- [ ] extend `check_collinearity()` — Cramer's V (categorical), VIF, perfect-alias detection
- [ ] `near_zero_var(data)` — caret-style near-constant predictors (no caret dependency)
- [ ] `correlation_heatmap(data)` — themed, clustered

## 5. Cleaning & transformation
- [ ] `winsorize()` / `clamp()` — cap at percentiles or clinical bounds, count affected
- [ ] `standardize_factors(data)` — trim/case-normalize/collapse rare levels, report level map
- [ ] `recode_from_dict(data, dict)` — apply a value-label dictionary (Stata/SAS-style)
- [ ] `unit_convert()` — clinical conversions registry (creatinine, weight, temperature)
- [ ] `dedupe(data, id, keep)` — principled de-duplication with a kept/dropped log

## 6. Outcome & analysis prep
- [ ] `make_binary()` / `make_surv()` / `make_composite()` — consistent outcome construction
- [ ] `make_splits(data, strata, prop|folds, seed)` — stratified split/CV folds with leakage guard
- [ ] `build_recipe_skeleton()` — tidymodels/recipes starting point from a codebook

## 7. Diagnostics & reporting
- [x] `theme_dc()`, `tbl1()`, `suppress_small_cells()`
- [ ] `plot_roc()`, `plot_calibration()`, `plot_decision_curve()`, `plot_forest()` (generalize panel_diagnostics.R)
- [ ] `safe_write(x, path)` — refuse to write individual-level data outside data/; auto-suppress small cells

## 8. Reproducibility / workflow
- [ ] `session_fingerprint()` — R version, package versions, seed, git SHA into output/
- [ ] `tar_template()` helpers — common targets patterns (map-over-outcomes, CV branching)
- [ ] `compare_targets(results, targets, tolerances)` — replication-target verification: per-target diff vs documented tolerance, PASS/FAIL table; home skill: `estimation-diagnostics` (references/replication.md; external-mining ledger #22). The `audit-reproducibility` skill consumes the same comparison for manuscript claims (#23)

## 9. Model assumptions & diagnostics (regression / GLM)
- [ ] `check_residuals(model)` — normality (QQ + Shapiro/KS), homoscedasticity (Breusch-Pagan, scale-location), residual-vs-fitted, autocorrelation (Durbin-Watson)
- [ ] `check_influence(model)` — Cook's distance, leverage, DFFITS, outlier flags
- [ ] `check_multicollinearity(model)` — VIF / generalized VIF on a fitted model
- [ ] `check_linearity(model)` — partial-residual / component+residual checks for continuous terms
- [ ] `check_overdispersion(model)` — Poisson/NB dispersion ratio + test
- [ ] `check_separation(model)` — (quasi-)complete separation in logistic models
- [ ] `model_assumption_report(model)` — one-call bundle of the above (guarded `performance`/`see`)

## 10. Causal & semiparametric diagnostics
- [ ] `check_positivity(data, treatment, covariates)` — propensity overlap: PS distribution by arm, % near 0/1, suggested trimming, effective sample size
- [ ] `check_balance(data, treatment, covariates, weights = NULL)` — standardized mean differences pre/post weighting + Love plot
- [ ] `check_weights(weights)` — IPW diagnostics: max weight, ESS, coefficient of variation, share of total weight in top-k
- [ ] `check_eic_convergence(eic, n, se, threshold = NULL)` — TMLE: |mean(EIC)| vs se/sqrt(n); flag non-convergence (default threshold se/(sqrt(n)*log(n)))
- [ ] `check_ps_calibration(ps, treatment)` — is the propensity model itself calibrated?
- [ ] `summarize_eic(eic)` — plug-in vs one-step, influence-curve-based SE and CIs

## 11. Prediction-model performance & validation
- [ ] `eval_discrimination(pred, obs)` — AUC (+ DeLong CI), AUPRC, Brier
- [ ] `eval_calibration(pred, obs)` — calibration slope/intercept, ICI / E50 / E90, calibration curve
- [ ] `eval_clinical_utility(pred, obs)` — decision-curve / net-benefit across thresholds
- [ ] `bootstrap_optimism(fit_fun, data)` — Harrell optimism-corrected performance + shrinkage factor
- [ ] `crossfit_performance(...)` — honest CV / cross-fit metrics with CIs (leakage-guarded splits)
- [ ] `compare_auc(pred1, pred2, obs)` — DeLong paired test (NRI/IDI with caveats)

## 12. Simulation & inference utilities
- [ ] `coverage_report(estimates, ses, truth)` — bias, RMSE, CI coverage, Monte-Carlo SE (feeds the simulation-study skill)
- [ ] `summarize_sim(results)` — tidy aggregation of estimator runs by scenario
- [ ] `check_ci_coverage(ci_lo, ci_hi, truth)` — nominal vs empirical coverage with MC error bars
