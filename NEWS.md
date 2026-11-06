# dctools (development version)

* Release kit, part 3 (P9c): controlled insertion. `show_count()` inserts a
  report's count into a Quarto document exactly as the report masks it
  (masking recomputed by dctools), inside a span naming the target, count id
  and display rule, so the rendered HTML carries its own insertion records.
  `check_rendered_values()` checks every span against the stored reports
  and flags any number in the visible text printed another way (exemptions
  explicit; years by default). `build_release_bundle()` now computes
  `render_checked` from it for each deliverable and writes the insertion
  records under `render/`; non-HTML deliverables are `not_established`.

* Release kit, part 2 (P9b): `verify_release()` and `verify_release_pr()`
  check a release PR: V1 the bundle at E matches the manifest byte for
  byte; V2 A is an ancestor of E, with no merges and only bundle changes
  between them, and the requirements and inventory at A match the
  manifest; V3 the release approver's latest decisive review approves E and
  its `release-approval` block names the release and the manifest digest;
  V4 no nonwaivable blocker, and every waivable one accepted with a
  rationale. `release_approval_template()` writes the PR comment (waivable
  blockers commented out, so nothing is accepted by default).
  `archive_release_approval()` writes the binding review verbatim to
  `evidence/approvals/<release ID>.json`, and `check_approval_archive()`
  flags a review edited or dismissed since. Bundles now carry a
  `.gitattributes` (`* -text`), and the manifest's requirements and
  inventory digests come from git, so digests hold on every platform.

* Release kit, part 1 (P9a): `allocate_release_id()` and
  `build_release_bundle()`. The bundle (`evidence/releases/<release ID>/`)
  holds the release run's exported evidence, receipts computed by dctools
  (`execution_recorded` from the run audit, `contract_checked` from the
  computation lock, `known_answer_checked` from testthat in a separate
  process; the rest `not_established` or `not_run` with a reason), the
  candidate checklist (`checklist.json`, `checklist.md`: requirements,
  outcomes, unresolved items and blockers, waivable or nonwaivable, with no
  acceptances proposed), byte copies of the deliverables, and the manifest,
  written last (schema 1; plain SHA-256; no self-hash, evidence commit,
  approval or tag). It reads `contracts/requirements.yml` and
  `records/unresolved.yml`, and refuses a dirty tree, a run not ledgered from
  a clean tree at HEAD, and an existing bundle directory.

* Computation lock v0 (schema version 1): `computation_lock()`,
  `write_computation_lock()`, `read_computation_lock()` (also at a git ref),
  `check_computation_lock()` and `lock_review_table()`. For each
  decision-linked target, the lock records the top-level call of its command
  and each argument as a `literal`, a `config` value (from a declared YAML
  file), a `reference` or `unresolved` with the expression and reason, plus
  the `tar_target()` location. Project code is parsed, never run, and helpers
  are not followed. The JSON carries no timestamp, commit or version, so the
  check regenerates it from source and fails (`dctools_lock_mismatch`) on any
  byte difference. The review table shows changes against a baseline lock.
  `yaml` joins Suggests.

# dctools 0.1.0

First release: the first verifier pin for analysis projects (the run ledger,
audit, evidence export and disclosure-safe runner below).

* `run_targets_safe()` brackets its output with
  `== dctools runner output schema 1 ==` and `== end of runner output ==`, so a
  wrapper can drop what R, renv, an `.Rprofile` or package loading print
  before the runner starts, and R's exit-time warnings after it. While the
  runner works, anything printed in its own process goes to `stdout.log` in
  the debug directory; the summary is printed after.
* `export_run_evidence()` writes the committable copy of a run's evidence
  (`ledger.json`, `audit.md`, `provenance.md`; export schema version 1).
  The copy is built field by field, so unknown fields are dropped. Targets,
  reports, count ids and function names must come from the committed
  source (dynamic branches are dropped); undeclared paths become `null`;
  decision ids must appear in a declared document. Digests are kept only for
  files (inputs, documents, records); store-object digests, data and
  dependency hashes, library paths and dirty file names stay private.
  `export$withheld` counts what was dropped, and the audit page keeps each
  check's status but not its details.
* `run_targets_safe()` applies a closed output schema (version 1, recorded
  in the ledger as `run$output_schema_version`). Printed strings must come
  from an allowlist built from the committed source (target names from
  `tar_manifest()`, symbols and identifier-shaped words of string constants
  in the project's R files). Dynamic branches, whose names hash their data,
  print only as `<pattern>: <n> branches <progress>` with the count masked.
  Sidecar targets, codes and count names outside the allowlist are withheld.
  `== run status ==` lines must read `<identifier>: <value>`, with integers
  masked below `mask_below`; other lines are replaced by a placeholder and
  logged privately, and a `withheld:` line counts them. An unreadable
  manifest withholds every target line.
* Run ledger schema 2. `capture_environment()` records the computational
  tier (R, BLAS/LAPACK, RNG kind, collation locale, thread settings, and
  versions plus `RemoteSha` of named packages) and the full tier (OS and
  kernel, locales, time zone, library paths, every installed package);
  assigning the computational tier to a global in `_targets.R` makes the
  targets that reference it rebuild when it drifts. `run_targets_safe()`
  hashes inputs before the run (declared inputs, literal file-target paths,
  files under the new `input_dirs`), and `write_run_ledger()` records them
  with their post-run digests; undeclared files are recorded by number, not
  name. Each target records `built` and, when reused, the earlier run that
  built it (`origin_run_id`, or unknown). `audit_run()` adds C10 Input
  stability and C11 Environment (installed packages and R against
  `renv.lock`), and C2 now fails a target whose built label disagrees with
  the store.
* Disclosure-safe reports, ported from sepsis_burn: `create_report()`,
  `record_count()`, `record_unprinted_count()`, `add_line()`,
  `add_literal_line()`, `add_data_frame()`, `add_count_table()`,
  `add_tabulation()`, `declare_linear_relation()`, `declare_sum_relation()`,
  `run_section()`, `render_report()`, `print_report_section()`. Every count
  records the source lines and function that computed it; count ids must be
  identifier-like. Digit runs in text added by `add_line()`,
  `add_literal_line()`, `add_data_frame()` (cells and column names) and
  `run_section()` titles that come neither from `record_count()` nor from a
  literal written in the call are recorded by location, and audit check C8
  fails. Only digits right after a letter or underscore (`J7`, `death_28d`,
  `n42`) are exempt; `64d`, `45min` and `.031` count as bare numbers.
  Count-table labels from data that hold a bare number print as `<other>`
  (`labels_from_code = TRUE` labels are printed as given). Numbers enter a
  report through `record_count()` and its siblings; direct edits of a
  report's internal fields are not detected and are a code-review matter.
* Run ledger and audit: `write_run_ledger()` writes a PHI-free JSON index of a
  targets run; `audit_run()` checks it (C1-C9: code, store, freshness,
  completeness, inputs, decisions, records, provenance, engine) and writes a
  one-page verdict and a provenance page; `stamp_record()` stamps rendered
  records. `run_targets_safe(ledger = )` refuses a dirty working tree
  (ignoring the ledger directory and the declared records; the targets store
  and debug output must be git-ignored), then writes and audits a ledger
  after every run (new exit status 3: the audit did not pass). C7 accepts
  only stamped objects that are available reportable reports, and C8 fails a
  reportable target that is not available. Record content outside dctools
  reports (anything a record reads without stamping it) is not covered by
  the audit.
* Initial package scaffold (renamed from the `helpers` script collection).
* The scaffolded `.gitignore` now un-ignores `data/raw/README.md` and
  `data/processed/README.md` (the private zones keep only a tracked README),
  and the `.gitignore` comment and README layout line describe `data/metadata/`
  as publishable, paper-shaped codebooks and dictionaries.
* Project scaffolding: `create_project()` (analysis + package archetypes) and
  `make_file_dirs()`.
* `create_project(type = "analysis")`'s README now pins the R version the
  scaffold ran under in `## Reproducibility`, with a matching
  [`rig`](https://github.com/r-lib/rig) command when `rig` is on `PATH` —
  `renv` pins packages but not the R version itself, and this fires whether
  or not the project was set up through a Claude session.
* `create_project(type = "analysis")` now builds the project directly instead of
  cloning an external template: a PHI-aware `.gitignore`, `.Rprofile`, `.Rproj`,
  a README stub, and the `memos/` + `workflow-feedback.md` state stack. It no
  longer writes a `CLAUDE.md` or `.claude/` — the router is generated by the
  `project-setup` skill and safety hooks live in the installed kernel. Removes
  the runtime network dependency (the analysis archetype is now unit-tested) and
  the `template_repo` argument.
* `create_project(type = "analysis")` now initialises `renv` (skipped with a
  warning when `renv` isn't installed), so `renv.lock` pins the package and R
  versions from the start; `.Rprofile` keeps the guarded activation line.
* Package & environment helpers: `read_packages()`, `load_packages()`,
  `configure_parallel()`.
* Data validation: `assert_columns()`, `check_unique_id()`, `flag_out_of_range()`.
* Join integrity: `join_audit()` — strict-join wrapper that declares the
  `relationship`/`unmatched`/`na_matches` contract (`na_matches` defaults to
  `"never"`), returns the joined data with a before/after row-count + match-rate
  audit trail attached, and warns on row inflation. Home skill: `data-qc`.
* Data-intake QC: `describe_cohort()`, `detect_missing_sentinels()`,
  `check_colnames()`, `clean_colnames()`, `check_types()`,
  `check_constant_cols()`, `check_collinearity()`.
* PHI-safe output: `suppress_small_cells()`.
* Disclosure-safe targets pipelines: `run_targets_safe()` runs `tar_make()` with
  every byte of pipeline output sent to `data/processed/debug/<run_id>/` and prints
  only an allowlist (target progress, pattern-checked error codes, small counts
  masked, caller-owned run-status lines), exiting 0/1/2. Inside targets,
  `capture_target_debug()` writes full error detail to a private bundle plus a
  pattern-checked status sidecar; `abort_safe()` raises errors whose code and
  counts may be printed; `create_debug_sink()` and `read_debug_status()` round it
  out. Generalized from sepsis_burn's safe runner.
* Replication / reproducibility: `compare_targets()` — per-target
  PASS/FAIL/UNMATCHED comparison of computed results against documented targets
  at kind-based tolerances (integers exact, estimates < 0.01, SEs < 0.05,
  percentages < 0.1, p-values by significance level). Home skill:
  `estimation-diagnostics`; also used by the `audit-reproducibility` skill.
* Clinical formulas: `ckd_epi_2021()`.
* House plotting / tables: `theme_dc()`, `tbl1()`.
