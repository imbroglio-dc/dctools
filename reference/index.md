# Package index

## Project scaffolding

- [`create_project()`](https://imbroglio-dc.github.io/helpers/reference/create_project.md)
  : Scaffold a new research project
- [`make_file_dirs()`](https://imbroglio-dc.github.io/helpers/reference/make_file_dirs.md)
  : Create the standard project directory skeleton

## Packages & environment

- [`read_packages()`](https://imbroglio-dc.github.io/helpers/reference/read_packages.md)
  : Read R package names from a plain-text file
- [`load_packages()`](https://imbroglio-dc.github.io/helpers/reference/load_packages.md)
  : Load (and optionally install) a vector of R packages
- [`configure_parallel()`](https://imbroglio-dc.github.io/helpers/reference/configure_parallel.md)
  : Configure a local crew parallel controller

## Data validation

- [`assert_columns()`](https://imbroglio-dc.github.io/helpers/reference/assert_columns.md)
  : Assert that required columns are present
- [`check_unique_id()`](https://imbroglio-dc.github.io/helpers/reference/check_unique_id.md)
  : Check that a column (or set of columns) uniquely identifies rows
- [`flag_out_of_range()`](https://imbroglio-dc.github.io/helpers/reference/flag_out_of_range.md)
  : Flag values outside an expected numeric range

## Data-intake QC

- [`describe_cohort()`](https://imbroglio-dc.github.io/helpers/reference/describe_cohort.md)
  : One-call cohort QC description
- [`detect_missing_sentinels()`](https://imbroglio-dc.github.io/helpers/reference/detect_missing_sentinels.md)
  : Detect disguised-missing sentinel values
- [`check_colnames()`](https://imbroglio-dc.github.io/helpers/reference/check_colnames.md)
  : Flag problematic column names
- [`clean_colnames()`](https://imbroglio-dc.github.io/helpers/reference/clean_colnames.md)
  : Clean column names to snake_case
- [`check_types()`](https://imbroglio-dc.github.io/helpers/reference/check_types.md)
  : Heuristically flag likely column-type problems
- [`check_constant_cols()`](https://imbroglio-dc.github.io/helpers/reference/check_constant_cols.md)
  : Identify constant or all-missing columns
- [`check_collinearity()`](https://imbroglio-dc.github.io/helpers/reference/check_collinearity.md)
  : Find highly correlated numeric column pairs

## PHI-safe output

- [`suppress_small_cells()`](https://imbroglio-dc.github.io/helpers/reference/suppress_small_cells.md)
  : Suppress small cells in a summary table

## Clinical formulas

- [`ckd_epi_2021()`](https://imbroglio-dc.github.io/helpers/reference/ckd_epi_2021.md)
  : Estimated GFR via the CKD-EPI 2021 (race-free) creatinine equation

## Visualization & tables

- [`theme_dc()`](https://imbroglio-dc.github.io/helpers/reference/theme_dc.md)
  : House ggplot2 theme
- [`tbl1()`](https://imbroglio-dc.github.io/helpers/reference/tbl1.md) :
  Descriptive "Table 1" via gtsummary
