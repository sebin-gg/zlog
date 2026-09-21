# AGENTS.md — zlog contributor workflow

## Commit & merge workflow

1. Verify before every commit (see below).
2. Agent merges to `main` itself once verification passes — no review wait, no PR gate.
3. After merge, report back to the user with what changed and the verification evidence.

## Verification before every commit

- `bash -n scripts/zlog.sh`, `bash -n install.sh`, `bash -n tests/test-posix.sh`,
  `bash -n tests/test-install.sh`.
- PowerShell parse check on `scripts/zlog.ps1` and `tests/test-powershell.ps1`
  (must report 0 errors, including on stock PS 5.1 syntax rules).
- Frontmatter check: `SKILL.md` must start with `---` and contain
  `name`, `description`, `license`, `compatibility`, `allowed-tools`.
- Behavioral tests (not just syntax): `bash tests/test-posix.sh`,
  `bash tests/test-install.sh`, and `tests/test-powershell.ps1` must
  pass — they cover prune, symlink escape, purge age/lock, stale
  artifacts, size guard, locks, restore, installer backup/rollback.
- Any `find` predicate change must keep the symlink-escape fixture green.

## Sync rule (v2 architecture)

- `scripts/` is the source of truth for implementation. `SKILL.md` is the
  decision brain (no shell implementation inside it). `references/` holds
  path/safety/format knowledge. `tests/` proves destructive behavior.
- `README.md` shows script *usage* only — never paste implementation
  snippets into it.
- `install.sh` must install the full skill set (`SKILL.md`, `scripts/`,
  `references/`) listed in its `SKILL_FILES`.
- `references/agent-paths.md` verification dates must be touched whenever
  a root path changes.
