# Focused repository cleanup

This slice moves byte-identical runtime files into `Core/`, `Planning/`,
`Integrations/` and `UI/`. The TOC order is preserved. Tests and offline tools
use the new paths; the screenshot SPF loader tries the new nested paths and
falls back to the historical flat layout.

Evidence for this slice:

- SHA-256 comparisons against the pre-move blobs cover every moved runtime file.
- `tools/typecheck_coverage.py` scans each new runtime directory and has a
  regression test for an orphan file in every grouped directory.
- The SPF screenshot loader has an explicit basename fallback for old release
  sources.

This is a focused cleanup report, not a claim that the repository-wide Sift
candidate ledger has been independently reverified.
