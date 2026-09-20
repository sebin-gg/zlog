# zlog formats

## What the scripts produce

| Platform | Archive | How |
|---|---|---|
| POSIX (`zstd` present) | `file.log.zst` | `zstd -15`, integrity-tested with `zstd -t` |
| POSIX (`xz` fallback) | `file.log.xz` | `xz -9`, integrity-tested with `xz -t` |
| POSIX (`gzip` fallback) | `file.log.gz` | `gzip -9`, integrity-tested with `gzip -t` |
| Windows PowerShell | `file.log.tar.gz` | `tar.exe -czf`, single entry, size-checked |

Every archive is written to a temp name first (`.$PID.tmp.*`), tested,
required to be smaller than the source, then atomically renamed. The
source is deleted only after the rename succeeds.

## Read / search without restoring

- `.zst`: `zstdcat file.log.zst`, `zstdgrep "pattern" file.log.zst`
- `.gz`: `zcat file.log.gz`, `zgrep "pattern" file.log.gz`
- `.xz`: `xzcat file.log.xz`, `xzgrep "pattern" file.log.xz`
- Windows `.tar.gz`: `tar -tzf file.log.tar.gz` (list), `tar -xzf` (extract)

## Restore

Ask the agent ("restore my Cursor log") or run the helper directly:

- POSIX: `scripts/zlog.sh restore <archive>...`
- Windows: `scripts/zlog.ps1 restore <archive>...`

Rules: the destination must not already exist; multi-entry `.tar.gz`
files are refused; the archive is preserved unless you delete it.

## Deliberately unsupported

- **SQLite/WAL** (`logs_2.sqlite`, `*.sqlite-wal`, `*.shm`): live
  databases — compressing them while open risks corruption. Manage via
  the owning app (e.g. Codex itself); zlog reports them as
  intentionally untouched.
- **Caches** (`node_modules`, GPU caches, `.git`): never entered, never
  cleaned unless the user explicitly asks for cache cleanup (out of
  scope for this skill).
