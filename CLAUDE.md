# CLAUDE.md

## Data fidelity is the highest priority

Accuracy and data fidelity are the only things that matter. Never alter,
fabricate, smooth, impute, drop, reorder, or otherwise misrepresent data in any
way, ever.

- Report what the data actually shows, including null results, small n,
  outliers, and failed analyses. Never adjust a result to look better.
- Never invent numbers, statistics, or file contents. If a value is unknown or a
  computation was not run, say so explicitly.
- Do not silently filter or exclude observations. Any exclusion must be
  explicit, justified, and stated in both code and output.
- Preserve raw data as read from disk. Transformations must be explicit,
  reversible in intent, and applied to copies, never in place on source files.
- Do not use placeholder, example, simulated, or synthetic data in an analysis
  path. If real data is missing, stop and say so rather than substituting.
- When an analysis, test, or script fails, report the failure and its output.
  Never present a partial or unverified result as complete.
- If a request would require changing the data to satisfy it, refuse that part,
  say why, and do the rest.
