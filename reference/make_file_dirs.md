# Create the standard project directory skeleton

Idempotent. Creates `code/`, `data/`, `output/`, `docs/`, and `tests/`
subtrees under `path` (only those requested), each with a `.gitkeep`
marker, and ensures `scratch/` is git-ignored.

## Usage

``` r
make_file_dirs(
  path = ".",
  code = TRUE,
  data = TRUE,
  output = TRUE,
  docs = TRUE,
  tests = TRUE,
  extra = NULL
)
```

## Arguments

- path:

  Project root (default current directory).

- code, data, output, docs, tests:

  Logical; create that subtree.

- extra:

  Optional character vector of additional relative dirs to create.

## Value

`path`, invisibly.
