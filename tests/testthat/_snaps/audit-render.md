# the audit page shows the verdict, one row per check and how to verify by hand

    Code
      cat(scrub(md), sep = "\n")
    Output
      # Run 20260101-000000 audit: PASS
      
      - Commit: [`<sha>`](https://example.com/o/r/tree/<sha>) (clean)
      - dctools: 9.9.9 (commit unknown)
      - Ledger: `20260101-000000.json`; provenance: `20260101-000000.provenance.md`
      
      | Check | Name | Status | Evaluated | Failed |
      |---|---|---|---|---|
      | C1 | Code | PASS | 4 | 0 |
      | C2 | Ledger matches store | PASS | 4 | 0 |
      | C3 | Fresh | PASS | 2 | 0 |
      | C4 | Complete | PASS | 4 | 0 |
      | C5 | Inputs | PASS | 3 | 0 |
      | C6 | Decisions | PASS | 2 | 0 |
      | C7 | Records | PASS | 1 | 0 |
      | C8 | Provenance | PASS | 2 | 0 |
      | C9 | Engine | PASS | 2 | 0 |
      
      ## Verify by hand
      
      From the project root:
      
      ```sh
      git cat-file -e <sha>^{commit} && echo 'C1: the commit exists'
      git show '<sha>:R/evidence.R' | sed -n '4,4p'   # C1: compare with the code in 20260101-000000.provenance.md
      sha256sum 'data/raw/input values.csv' 'output/record.html' 'decisions.yml'   # C5: compare with "sha256" in 20260101-000000.json
      Rscript -e 'utils::packageDescription("dctools")$RemoteSha'   # C9: compare with the dctools commit above
      ```

# the provenance page shows each masked value with its code and a permalink

    Code
      cat(scrub(pm), sep = "\n")
    Output
      # Run 20260101-000000: where each reported value came from
      
      Code at commit `<sha>`. Values are masked as in their reports.
      
      ## R/evidence.R
      
      ### build_evidence() (lines 1-8)
      
      - `evidence` / `n_values` = `12` ([L4-L4](https://example.com/o/r/blob/<sha>/R/evidence.R#L4-L4))
      
        ```r
        4 |     dctools::add_line(r, "values: ", dctools::record_count(r, "n_values", length(values)))
        ```
      
      - `evidence` / `n_large` = `10` ([L5-L5](https://example.com/o/r/blob/<sha>/R/evidence.R#L5-L5))
      
        ```r
        5 |     dctools::add_line(r, "large: ", dctools::record_count(r, "n_large", sum(values > 2)))
        ```

