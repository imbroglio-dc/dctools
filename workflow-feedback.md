# Workflow feedback - dctools

**Tooling friction only** - devtools/R CMD check quirks, CI problems, formatting-tool
issues. Kept distinct from `memos/decisions.md` (decisions).

Format: `YYYY-MM-DD - <tool> - friction - -> action`

---

2026-07-10 - air - `air` binary not on PATH in this environment; could not run `air format .` before commit -> hand-matched surrounding style; install air (cargo/binary) to restore the format step.
