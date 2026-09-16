# AGENTS.md — zlog contributor workflow

## Commit & merge workflow

1. Verify before every commit (see below).
2. Agent merges to `main` itself once verification passes — no review wait, no PR gate.
3. After merge, report back to the user with what changed and the verification evidence.

## Verification before every commit

- `bash -n` on all bash snippets extracted from `SKILL.md` and `README.md`.
- `bash -n install.sh` to verify installer syntax.
- Frontmatter check: `SKILL.md` must start with `---` and contain
  `name`, `description`, `license`, `compatibility`, `allowed-tools`.
- Functional repro of the changed `find` logic in `/tmp` (pruned dirs must
  never leak into the compression list).

## Sync rule

`SKILL.md` is the source of truth. Every snippet change must be mirrored
in `README.md` (POSIX standard + PowerShell sections) in the same commit.
The Dry-Run preview snippet lives only in `SKILL.md` and is exempt.
