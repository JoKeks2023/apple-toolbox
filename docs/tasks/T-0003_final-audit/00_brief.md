# T-0003 — Final audit and remaining SPEC gaps

**Request (2026-09-29):** "mach doch mal #41 … und guck nochmal ob code wise sonst alles fertig ist". The owner then chose **no local builds** ("Nein, nur Code-Audit"), so #41 (device runtime verification) stays open, and "fix what the audits find".

**Audits (read-only, on 574801a):**
1. SPEC completeness: every SPEC.md section against the code. Result: broad and honest, but **not code-complete**. About 25 public-API gaps remain (grouped into #87–#101). The T-0002 definition of done ("every §4–§41 has real code where Apple offers a public API") was not fully met.
2. Runtime traps that static compilation misses (Swift 6 main-actor callbacks, missing Info.plist keys, force unwraps and similar). Results go to `04_impl_report.md`.

Sampled T-0002 claims were all backed by code; nothing was built or run (#41).
