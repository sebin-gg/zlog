# AGENTS.md — zlog contributor workflow

## PR workflow (mandatory for every PR)

1. Work on a feature branch, never commit directly to `main`.
2. Open a PR with test evidence in the body (repro before/after).
3. Wait for reviewer comments, then address every comment with a new commit.
4. Wait for the next review round. Repeat until all reviews are addressed.
   If agent review capacity runs out with threads still unresolved, stop and
   leave the PR open — capacity exhaustion never overrides rule 5.
5. Never merge with unresolved review threads or failing checks.

## Verification before every PR

- `bash -n` on all bash snippets extracted from `SKILL.md` and `README.md`.
- Frontmatter check: `SKILL.md` must start with `---` and contain
  `name`, `description`, `license`, `compatibility`, `allowed-tools`.
- Functional repro of the changed `find` logic in `/tmp` (pruned dirs must
  never leak into the compression list).

## Sync rule

`SKILL.md` is the source of truth. Every snippet change must be mirrored
in `README.md` (POSIX standard + PowerShell sections) in the same PR.
The Dry-Run preview snippet lives only in `SKILL.md` and is exempt.
