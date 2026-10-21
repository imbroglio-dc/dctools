# Run ledger and audit: design

**Date:** 2026-10-20 · **Status:** draft for review · **Home skill:** data-preparation (pipeline audit); ROADMAP section 8 (reproducibility / workflow) **First consumer:** `sepsis_burn` (its integration gets a separate spec once these interfaces are settled).

## 1. Purpose

A person who did not write a `targets` pipeline, and who does not trust whoever ran it (including an AI agent), should be able to check mechanically that:

1.  every number in a run's reports came from the committed code at a stated git SHA, run on inputs with stated hashes, from a store that was up to date;
2.  each number can be traced to the file, lines and function that computed it, so the code that produced it can be reviewed for correctness;
3.  the audit itself is not something the project or the agent wrote: every check is a fixed, tested function in `dctools`, and each check is proven able to fail.

**What this does not establish:** that the code is correct. It establishes *which* code produced each number, and points the reviewer at it. Correctness stays with code review and the project's own tests.

## 2. Trust model

| Piece | Written by | Trusted because |
|------------------------|------------------------|------------------------|
| Report objects (every printed number) | `dctools` report functions, called from project code | The only way to put a number in a report is `record_count()` / `add_count_table()`, which evaluate the expression themselves and record where they were called from |
| Machine ledger (`<RUN_ID>.json`) | `write_run_ledger()`, called by the project's runner after `tar_make()` | Tested code; holds hashes and locations only, no values; cross-checked against the store, git and the files on disk by the audit |
| Audit (`<RUN_ID>.md`, `<RUN_ID>.provenance.md`) | `audit_run()`, called by the runner right after the ledger | A fixed catalogue of checks (C1-C9) that the project cannot shorten; each check has a test with a corrupted input that must make it FAIL |
| `dctools` itself | This repo | Installed from a pushed commit (C9 prints its version and SHA); its tests include the corrupted-input suite |

**Not trusted, and not needed:** the agent's prose. An agent reports a number only by citing its location (`<RUN_ID> · <target> · <report id>`); the value is in the audit file, which the agent cannot write (enforced on the project side by a hook, and detectable here because the audit is reproducible from the store at run time).

**Run-time only.** The audit runs once, immediately after the run, against the store that run produced. Old runs are not re-audited; their committed audit file is the record. Non-determinism between runs is not detected.

## 3. Components

All exported functions follow package discipline (roxygen, `pkg::fn` calls, ASCII sources, a test each). `targets` and `gert` calls are guarded with `requireNamespace()` where the package is in Suggests.

### 3.1 Safe report (ported from `sepsis_burn/code/functions/disclosure_safe_report.R`)

The existing report object (an environment accumulating counts, relations, output steps; small-count masking with secondary suppression over declared linear relations) moves here unchanged in behaviour, with its 22 tests. Names follow "objects are nouns, functions are verbs" (`verb_noun()`); the object is a `report`:

| sepsis_burn | dctools |
|------------------------------------|------------------------------------|
| `new_disclosure_safe_report()` | `create_report(hide_small_counts = TRUE, error_sink = NULL)` |
| `register_count()` | `record_count(report, id, expr, protect = FALSE)` (3.2) |
| `register_unprinted_count()` | `record_unprinted_count(report, id, expr)` |
| `add_count_table()` / `add_tabulation()` | `add_count_table(report, id, expr, ...)` / `add_tabulation(report, id, expr, ...)` |
| `declare_sum_relation()` / `declare_linear_relation()` | unchanged |
| `add_line()` / `add_literal_line()` / `add_data_frame()` | unchanged |
| `run_section()` / `within_report_section()` | `run_section()` (absorbs `within_report_section()`) |
| `render_report()` / `print_report_section()` | unchanged |

The old `register_*` names are **not** kept as aliases: an alias would be a second entry point the provenance check could not see. Where a dctools name equals a sepsis_burn name, the project's definition must be deleted, not kept alongside: a sourced project function would mask the dctools one. C8 catches the result either way (a count registered through a masking function has no provenance).

Changes from the port beyond renaming:

- `error_sink` becomes a constructor argument (it is set on the object by project code today).
- Every report records `dctools_version` and `hide_small_counts` in the object, so the audit can refuse unmasked reports (3.4, hard stop).
- The relationship to the existing `suppress_small_cells()` is unchanged: that function masks a finished table; the report masks while building and models relations between counts.

A failed `run_section()` prints only the error's class.

### 3.2 Provenance capture

`record_count(report, id, expr, protect = FALSE)` evaluates `expr` in the caller's frame, registers the value exactly as `register_count()` did, and records:

| Field | Source |
|------------------------------------|------------------------------------|
| `id` | the registered id (after any `_2` suffixing) |
| `file`, `line_start`, `line_end` | the source reference of the `record_count()` call, from the call stack |
| `code` | the source lines of that call, verbatim |
| `function`, `function_file`, `function_lines` | the enclosing function's name and the source span of its definition |
| `target` | `targets::tar_name()` when called inside a running target, else `NA` |

`add_count_table()`, `add_tabulation()` and `record_unprinted_count()` record the same fields for every cell id they register.

**Missing source references are failures, not blanks.** R keeps source references only when code is sourced with `keep.source = TRUE` (`Rscript` turns it off by default). When the reference cannot be found, the field is `NA` and C8 fails for that value. A `record_count()` call outside a target records `target = NA`, which C8 also fails.

**Bare-number guard.** A number printed without going through `record_count()` would have no provenance, for example a value pasted into a string passed to `add_line()`. The guard runs only on text added through `add_line()`, `add_literal_line()`, `add_data_frame()` and `run_section()` titles. At render time, every maximal digit run in that text that is not part of an identifier-like token (adjacent letters or underscores, as in `J7`, `death_28d`, `D13`) is checked: it must either come from a resolved placeholder, or appear literally in the recorded source code of the call that added that text (a constant written in the code, whose provenance is that line). Anything else is recorded as an unprovenanced number, and C8 fails. **Limit:** a computed value that happens to equal a literal on the same line passes the guard.

**Feasibility gate.** The first implementation task is a spike confirming that, in R 4.6 under `targets` (callr worker) and `Rscript`, the source reference of the `record_count()` call and the enclosing function's span can be read from the call stack when files are sourced with `keep.source = TRUE`. If they cannot, this spec returns to review before anything else is built.

### 3.3 Machine ledger

`write_run_ledger(path, run_id, store, script, reportable, links, extra_inputs, documents, records)` writes `<path>/<run_id>.json` (schema version 1) and returns its path.

| Block | Contents |
|------------------------------------|------------------------------------|
| `schema_version`, `run` | `1`; run id, start and finish times, targets requested, runner exit code (passed in) |
| `code` | git SHA, remote URL, `clean` (from `git status --porcelain`, ignoring the ledger directory), R version, SHA-256 of `renv.lock` if present, `dctools` version and `RemoteSha` |
| `inputs` | every `format = "file"` target: path, independent SHA-256, `targets` data hash; plus `extra_inputs` (files the pipeline reads that are not file targets): path and SHA-256 |
| `documents` | decision and configuration files the project names: path and SHA-256 |
| `targets` | per target: name, status (built / skipped / errored / canceled), command, depend and data hashes, upstream targets, and the project functions its command calls, each with file and line span |
| `outdated` | `targets::tar_outdated()` after the run |
| `links` | the project's decision-to-target table, passed in as a data frame (`decision_id`, `decision_status`, `target`, `role` = `args` / `evidence`) |
| `reportable` | the allowlist of targets the audit may load, with the SHA-256 of each stored object file (`<store>/objects/<name>`) |
| `records` | rendered record files: path, SHA-256, and the stamp parsed from each (3.5) |
| `provenance` | one entry per reported value, fields as in 3.2; no values |

Never written: error or warning messages (they can carry row-level values), object contents, anything from non-reportable targets. Function spans come from parsing the sourced files (`parse(keep.source = TRUE)` + `getParseData()`), not from executing them.

`dctools` does not know any project's decision-file format; the project derives `links` and passes them in.

### 3.4 Audit

`audit_run(ledger_path, store, script)` reads the ledger, the store's metadata, the allowlisted reports and git, runs C1-C9, writes `<RUN_ID>.md` and `<RUN_ID>.provenance.md` next to the ledger, and returns a data frame (`check`, `name`, `status`, `n_evaluated`, `n_failed`, `detail`).

**Hard stops (before any check):** a reportable target whose object is not a `dctools` report, or a report with `hide_small_counts = FALSE`, stops the audit with an error and writes nothing. These protect the files that will be committed.

| Check | Passes when |
|------------------------------------|------------------------------------|
| C1 Code | the SHA exists in git; the ledger says `clean`; every provenance `code` snippet and function span equals `git show <sha>:<file>` at the stated lines; every file named in provenance is tracked at the SHA |
| C2 Ledger matches store | each target's command, depend and data hashes in the ledger equal the store's metadata, and its status equals `tar_progress()`; each reportable object file's SHA-256 equals the ledger's |
| C3 Fresh | `outdated` in the ledger is empty, and a recomputed `tar_outdated()` is empty |
| C4 Complete | no target errored or was canceled |
| C5 Inputs | recomputed SHA-256 of every input and document equals the ledger's |
| C6 Decisions | every decision in `links` has at least one target; every linked target exists in the ledger and is built or up to date |
| C7 Records | every record file's SHA-256 equals the ledger's; each record's stamp names this run id and SHA, and its object hashes equal the ledger's `reportable` hashes |
| C8 Provenance | every printed value in every reportable report has complete provenance (3.2); no unprovenanced numbers |
| C9 Engine | `dctools` has a `RemoteSha` (installed from a pushed commit) and its version and SHA are printed |

**Status per check:** `PASS`, `FAIL`, or `NOT EVALUATED` (nothing to evaluate, or a prerequisite failed; the reason is in `detail`). A check never passes vacuously. **Verdict:** `PASS` only when all nine pass; otherwise `FAIL` if any failed, else `INCOMPLETE`.

### 3.5 Record stamp

`stamp_record(store, targets_read)` is called in a project's Quarto record. It prints a short human-readable block (run id from the `DCTOOLS_RUN_ID` environment variable, git SHA, `dctools` version) and embeds the same data, plus the SHA-256 of each stored object file it read, in a machine-readable HTML comment (`<!-- dctools-stamp {json} -->`) that `write_run_ledger()` parses into `records` and C7 checks.

### 3.6 Human-readable output

`<RUN_ID>.md`, about one page:

1.  Header: run id, SHA (linked to the remote at that commit), `dctools` version and SHA, verdict.
2.  Check table: one row per C1-C9 with status and counts.
3.  Failures: for each failing check, up to 10 offending items, then a count of the rest.
4.  Verify by hand: the three commands that reproduce C1, C5 and C9 from a shell (`git rev-parse`, `sha256sum` on the listed files, `git show <sha>:<file>`).

`<RUN_ID>.provenance.md`, grouped by source file, then by function: each value as `target · id = <masked value>`, followed by its code lines and a permalink to `<remote>/blob/<sha>/<file>#L<start>-L<end>`. Values are rendered through each report's own masking.

## 4. Testing

- **Port:** the 22 existing report tests, renamed.
- **Unit:** every exported function.
- **Fixture pipeline:** a small `targets` project built in a temp directory with its own git repo (`gert`), run with `callr`, used by the ledger and audit tests. No PHI, no real data. Skipped when `targets` is not installed.
- **Corrupted-input suite (the core trust test):** for each of C1-C9, a function that corrupts a passing fixture in one targeted way (edit a source line after the run, alter a hash in the ledger, touch an input file, leave a target outdated, error a target, delete a decision link, edit a rendered record, print a bare number, install `dctools` without `RemoteSha`). Each corruption must make its check `FAIL`, and the passing fixture must `PASS` all nine.
- **Vacuous-input tests:** empty `links`, empty `reportable`, no records: the affected checks report `NOT EVALUATED`, never `PASS`.
- **Hard-stop tests:** an unmasked report and a non-report object in `reportable` each stop the audit and write no files.
- **Snapshot tests:** `<RUN_ID>.md` and `<RUN_ID>.provenance.md` for the fixture.

## 5. Dependencies

- `jsonlite` and `digest` are in Suggests, guarded like the rest of `R/pipeline.R`; `quarto` is not needed. (`digest` is used for SHA-256; `tools::sha256sum()` would need `Depends: R (>= 4.5.0)`.)
- Suggests also: `targets`, `callr`.

## 5a. Decisions made during implementation

- Provenance for a call evaluated as an argument or lazily (for example inside `run_section()`) is the statement the caller's own function is executing, verified inside that function's file and span; otherwise `NA`, never guessed.
- C1 requires a full 40-hex commit SHA; C3 fails when the ledger has no `outdated` record; C6 accepts only completed, skipped or built target statuses; C7 requires at least one stamped object and a non-missing run id, commit and hashes. A check with nothing to evaluate is NOT EVALUATED.
- The ledger whitelists stamp fields (`run_id`, `sha`, `dctools_version`, `objects`). The audit page shows masked values in backticks and prints git commands and links only for a valid 40-hex SHA; the verify block includes a `git show <sha>:<file> | sed -n` command for C1.
- `run_targets_safe(ledger = )` exit precedence: 2 > 1 > 3 > 0.

## 6. Out of scope

- Re-auditing or replaying old runs; detecting non-determinism.
- Parsing any project's decision files (the project passes `links`).
- The sepsis_burn hook, record changes and call-site migration (its own spec). The runner integration is `run_targets_safe(ledger = )` in dctools.
- Proving code correctness.

## 7. Implementation order

1.  Spike: source-reference capture under `targets` and `Rscript` (feasibility gate, 3.2).
2.  Port the safe report with its tests (3.1).
3.  `record_count()` family and provenance (3.2), then the bare-number guard.
4.  `stamp_record()` (3.5).
5.  `write_run_ledger()` (3.3) with the fixture pipeline.
6.  `audit_run()` checks C1-C9 and hard stops (3.4), with the corrupted-input suite.
7.  Renderers (3.6) and snapshot tests.
8.  `ROADMAP.md` section 8 entry, `memos/decisions.md` entry, `devtools::check()` clean.