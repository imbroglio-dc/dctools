# dctools roadmap

Repeated data-science tasks to package as functions. `[x]` = shipped, `[ ]` = planned.
Grouped by analysis-pipeline stage. Conventions: dplyr surface grammar; arrow/dbplyr
for large data; base R where it keeps dependencies low.

## 1. Ingestion & typing
- [x] `check_types()` — text-as-numeric/date, logical-as-text, high-cardinality, binary-as-numeric
- [x] `check_colnames()` / `clean_colnames()` — non-syntactic, dupes, case-collisions, spaces
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
