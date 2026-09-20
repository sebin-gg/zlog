# Changelog

## Unreleased (v1.7.0: symlink-safe, transactional, verified paths)

- POSIX scans no longer follow symlinks (`find -L` removed): symlinked dirs are never descended, symlinked files never match, verified by fixture (external file untouched).
- Empty-log purge now uses the full safety predicate (pruned location + 60s age + lock check) instead of bare `-delete`.
- Transactional compression everywhere: temp `.$$.tmp` output -> decompressor integrity test (`-t`) -> smaller-than-source check -> atomic rename -> source removal. Compressor exit codes checked; stale artifacts and size growth can no longer count as success.
- LM Studio current layout corrected to `~/.lmstudio/` (per LM Studio docs: `~/.lmstudio/bin`, `server-logs`); `~/.lm-studio` spelling removed everywhere.
- Codex `sqlite/logs_2.sqlite` (+WAL/SHM, observed 32MB live DB) documented as intentionally out of scope.
- `install.sh`: temp-file `trap` cleanup on exit/interrupt.
- Concurrency wording softened to best-effort throughout; deep scan labeled as known-location scan, not new-agent discovery.
- `allowed-tools` gains `rm`, `mv`.

## Unreleased (v1.6.0: Win11-verified, claim-free)

- Removed all unmeasured savings figures repo-wide (`~77%`, `4-5x`,
  `98%` demo): hero, highlights, frontmatter description, intro, and the
  dry-run estimator now report measured per-run numbers only (Win11
  measured: 20.0K -> 12.7K, 36% on random data).
- PowerShell verified on stock Windows 11 (PS 5.1), 9/9 + 5/5 sandbox
  checks: compress/skip/purge/lock/junk/space-in-path all pass. Fixed
  inline `(try {...} catch {...})` in `Where-Object` (statement not
  valid in 5.1 pipelines) via `zlogFree()` helper; tar args quoted;
  empty-artifact guard added.
- One canonical POSIX dir list in standard, dry-run, and deep scan
  (10 classic dirs + `.lm-studio`, `.aider`, macOS Library, Win Git Bash
  AppData); `*.txt` excluded everywhere by default; `-print0` +
  `read -d ''` and awk sizes everywhere (no `numfmt` dependency).
- Deep scan fixes: explicit lock-check block with `continue` (no more
  stale-artifact counting), pruned-dir count now counts pruned dirs
  only (was counting every walked node), purge `find` prunes junk dirs,
  `*/.aider/*` + `*/AppData/*` discovery paths added.
- `README.md` install section no longer references the removed
  `~/.local/bin/zlog` CLI wrapper; `install.sh` header fixed.
- `allowed-tools` gains `wc` (used by deep-scan prune count).

## Unreleased (docs-only, no version bump)

- Removed unverified claims repo-wide. Compatibility now states Linux-tested,
  other platforms untested. Unmeasured savings figures, the benchmark table,
  runtime counts, and absolute guarantee wording replaced with mechanism
  descriptions. Benchmark section now points at the dry-run preview.
- Social card rebuilt from fixed SVG: mechanism wording only, no hard
  numbers; PNG regenerated via rsvg/ImageMagick at 1200x630.

## 1.5.0 (2026-09-17)

- Scan `%LOCALAPPDATA%\Ollama` on Windows (app/server/upgrade logs) plus
  `~/AppData/Local/Ollama` under Git Bash; deep scan matches
  `*/AppData/Local/Ollama/*`. Linux service path (`/usr/share/ollama`)
  stays out of scope (root-owned, no sudo).
- Scan `%USERPROFILE%\.lm-studio` in PowerShell (current canonical layout);
  both LM Studio layouts now covered on all platforms.
- Demo output labeled illustrative.

## 1.4.0 (2026-09-17)

- macOS/Windows native paths: `~/Library/Application Support/Cursor`,
  `%APPDATA%\Cursor`, `~/.config/Windsurf`,
  `~/Library/Application Support/Windsurf`, `%APPDATA%\Windsurf`
  (standard, dry-run, deep scan, PowerShell).
- PowerShell reaches POSIX parity: 0-byte purge first, same single-line
  savings summary (`zlogFmt`, `raw>0` guard).
- `install.sh`: `ZLOG_REF` pin (default `main`), `.bak` backup of existing
  skill before overwrite.
- `allowed-tools` scoped to needed commands instead of `Bash(*)`.
- Documented `fuser`/`lsof` fallback (age buffer only without either).

## 1.3.0 (2026-09-16)

- One canonical `prune=(...)` list shared by every scan; `.git` added to
  standard scans.
- Frontmatter description tightened to one job + triggers.
- `install.sh` trigger strings match Execution Intents exactly.
- CI: `bash -n` on all snippets + `install.sh`, POSIX mirror check,
  PowerShell parse check.

## 1.2.0

- Deep scan: hybrid prune + `-maxdepth 12` for nested logs (Antigravity).
- Explicit `-print` on pruned finds, guarded empty-purge and Windows tar.
- NUL-delimited finds; deep-scan paths aligned with standard dirs.

## 1.0.0 (GA)

- Standard compression (`zstd -15` / `xz -9` / `gzip`), 0-byte purge,
  process-lock + 60s in-flight guards, dry-run preview, Windows 11
  PowerShell via `tar.exe`, `curl` installer, `skills.sh` listing.
