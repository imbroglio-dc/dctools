# dctools (development version)

* Initial package scaffold (renamed from the `helpers` script collection).
* Project scaffolding: `create_project()` (analysis + package archetypes) and
  `make_file_dirs()`.
* Package & environment helpers: `read_packages()`, `load_packages()`,
  `configure_parallel()`.
* Data validation: `assert_columns()`, `check_unique_id()`, `flag_out_of_range()`.
* PHI-safe output: `suppress_small_cells()`.
* Clinical formulas: `ckd_epi_2021()`.
* House plotting / tables: `theme_dc()`, `tbl1()`.
