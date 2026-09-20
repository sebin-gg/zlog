# Changelog

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
