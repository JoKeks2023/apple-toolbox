# T-0001 Gap closure — Brief

**Request (2026-09-28):** Review what is missing in Apple Toolbox, file everything as GitHub issues, then implement it and push to `main` with one commit per item.

**Input:** gap analysis of the repository against `SPEC.md` (bugs, suspected bugs, spec gaps, repo hygiene).

**Output:** 37 GitHub issues (#1–#37) and one commit per issue on `main` (`Fixes #N`).

**Decisions from the owner**
- No Huly project (small personal tool).
- No GitHub CI. Verification is local and lightweight (no Xcode builds, no simulators on the 8 GB machine).
- Agents may be used; each works in its own git worktree and delivers one commit per issue.
