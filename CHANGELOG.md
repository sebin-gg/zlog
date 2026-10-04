# Changelog

## Unreleased

Fixed:

- `restore` no longer deletes a pre-existing **dangling symlink** sitting at the
  destination. The guard used `[ -e ]`, which follows symlinks and is therefore
  false for a symlink whose target is missing, so the restore proceeded and the
  failure path's `rm -f "$out"` destroyed a file zlog never created — while
  printing "nothing written". The guard now also tests `[ -L ]`, and the
  cleanup only runs when this invocation actually published the destination.
- The empty-file **purge path no longer has a TOCTOU window**. `find -empty`
  decided a file was empty, then a bare `rm -f` deleted it with no identity
  re-check, so a process that appended in between lost its data — and the run
  was reported as `purged=1 failed=0`, making the loss invisible. The purge
  loop now re-reads the inode/size/mtime and re-tests emptiness immediately
  before deleting, mirroring the two checks the compression path already made.
  `lsof`/`fuser` is not a substitute: it misses a writer that opened, wrote and
  closed inside the window.
- `clean` and `deep` now **exit non-zero when any file fails**. Both counted
  failures into the report line but ended on a `du`/`echo` statement, so a run
  where every file errored still exited 0 and any caller gating on the exit
  status read total failure as success.
- `zlog.sh` installs `EXIT`/`INT`/`TERM` traps. Temp artifacts are written next
  to their source and only existed inside a compressor child, so a Ctrl-C or a
  `kill` left a truncated `*.tmp.zst` in the user's log directory. Temps are now
  tracked and removed on any exit path. (Bash defers `SIGINT` while a
  foreground child runs, so the observable case is a process-group `SIGTERM`.)
- `zlog.sh` no longer walks the entire home directory **twice** in `deep` /
  `deep-preview`. The prune count was a second full `find ~` traversal purely to
  print a number; the single traversal now emits both record kinds and callers
  distinguish them with `[ -d ]`.
- `install.sh` no longer destroys a backup when two upgrades land in the same
  second. `date +%Y%m%d%H%M%S` has one-second granularity, so both computed the
  same backup name and the unconditional `rm -rf "$BACKUP"` deleted the only
  good copy. The name now carries `$$` as well.
- `install.sh` no longer claims "previous version restored" when the rollback
  failed. The `mv "$BACKUP" "$SKILL_DIR" || true` swallowed the failure and the
  message was printed unconditionally, leaving a user with no installed skill
  and a reassuring log line. The rollback result is now checked, and on failure
  the backup path is printed with a manual recovery command.
- `zlog_publish` treats any pre-existing destination entry as a conflict.
  Besides the `-e`/`-L` fix above, the `mv -n` fallback now also requires the
  destination to be a visible regular file that is not a symlink, since `mv -n`
  exits 0 even when it declines to overwrite.

Changed:

- `install.sh` iterates `SKILL_FILES` as a bash array instead of a space-joined
  string. `for f in $SKILL_FILES` relied on word splitting, so any future entry
  containing a space or a glob character would silently split into bogus paths.
  `tests/test-install.sh` mirrors the same array so the fixture cannot drift
  from what the installer actually installs.
- The unused `TMP_FILE="$(mktemp)"` in `install.sh` is gone; it was created and
  trapped for cleanup on every run but never used.
- `restore` declares its loop variables (`out`, `rc`, `tmp`, `tmpd`, `tmpf`)
  `local` instead of leaking them into the global scope.

Tests:

- `tests/test-posix.sh` asserts on `lexists`, not `[ -e ]`, for the
  dangling-symlink cases — `-e` is exactly the test that used to lie.
- `install.sh` never deletes an existing backup to make room. The backup path
  is allocated with `mktemp -d` (atomic, so it cannot collide) and the name is
  then freed for the `mv`; a forward-only counter is the fallback. Previously a
  same-second collision was "resolved" by `rm -rf "$BACKUP"`, which destroyed
  the only good copy. Adding `$$` alone was not sufficient: separate PID
  namespaces sharing a home directory can reuse a PID within the same second.
- `tests/test-install.sh` asserts the rollback-failure test against the
  **specific** backup path the installer printed. `ls -d "$DEST".bak.* | head -1`
  could match a backup left by an earlier test, so the assertion could pass
  without the one under test existing at all.
- `tests/test-posix.sh` no longer contains doubled `""` inside `eval`'d strings.
  A mechanical rewrite had produced `\"\"$ZLOG_TEST_ROOT\"/x\"`, which bash reads
  as `""` followed by an *unquoted* path — so the traversal/mismatch/corrupt
  restore checks passed for the wrong reason and `newline archived` failed
  outright whenever the fixture path contained a space. Verified by running the
  whole suite under a `TMPDIR` containing a space.
- `tests/test-posix.sh` quotes every variable that reaches `check`'s `eval`.
  The "deep-preview changes nothing" checks passed `$HOME` unquoted, so they
  word-split and silently **failed** (not skipped) on any path containing a
  space, in a suite whose purpose is portability. 68 unquoted expansions across
  the file are now quoted inside the `eval`'d string.
- `tests/test-posix.sh`'s `tree_sum` now fingerprints path, entry type, size,
  mtime **and content hash**. It previously hashed only the path list, so the
  "deep-preview changes nothing" assertions could not see an in-place rewrite or
  a truncation at all — a same-length content change produced an identical
  fingerprint. NUL-separated throughout and deliberately unsorted: the fixture
  contains a newline-bearing filename, and `sort -z` does not exist on BSD.
- `tests/test-posix.sh` gains a self-test for the fingerprint itself, since a
  helper that silently stops detecting changes would leave the two read-only
  assertions looking green while proving nothing.
- `tests/test-posix.sh` uses `SIGTERM` to the compressor's process group, not
  `SIGINT`. Bash defers `SIGINT` while a foreground child runs, so the script
  survives, takes its normal "compressor failed" branch and removes the temp
  itself — which made an earlier version of the interrupt test pass vacuously
  against the unfixed script. The compressor stub also has to create the temp
  *before* stalling, exactly as `zstd -o` does.
- `tests/test-install.sh` pins `date` to a frozen timestamp so the same-second
  backup collision is deterministic instead of a race, and stubs `mv` to fail
  the promote *and* the rollback while still allowing the backup step.
- `tests/test-powershell.ps1` covers empty-archive restore, glob-metacharacter
  destination names, the restore ownership flag, and the `clean` exit status.
- `tests/test-powershell.ps1` `Check` now wraps each assertion in try/catch. A
  single assertion that threw (for example reading a file a previous failure had
  deleted) aborted the whole suite, hiding every later regression behind the
  first one.
- `tests/test-powershell.ps1` measures the `clean` exit status from a **child
  process**. `& $Script` does not put a PowerShell script's exit status in
  `$LASTEXITCODE`, which still holds whatever the last native command returned —
  in that test, the stub compressor's own `1`. The assertion therefore passed
  against the unfixed script for entirely the wrong reason.
- `tests/test-powershell.ps1` now exits `0` explicitly on success. Without it
  pwsh falls back to `$LASTEXITCODE`, which the corrupt-archive fixtures have
  already set to `1` from their deliberately-failing `gzip -d -c` calls — a
  fully passing run printed "POWERSHELL TESTS ALL PASS" and still failed CI.
- `tests/test-powershell.ps1` skips the `clean` exit-status check on Windows.
  The failure is injected by shadowing the compressor, and PowerShell refuses to
  run a text file named `tar.exe` as a native command, while in-process function
  shadowing cannot reach a child process.

Also fixed in this cycle:

- `scripts/zlog.ps1` had drifted from `scripts/zlog.sh` and carried the same
  class of bugs. All four are fixed in the twin:
  - The empty-file **purge path had no identity re-check**, unlike the
    compression path right below it, which makes three. It now re-reads
    identity and emptiness immediately before deleting.
  - **`restore` accepted a legitimately empty archive**, matching the POSIX
    side. The `.Length -gt 0` test rejected a 0-byte decompression, so
    restoring an empty `.log` reported FAILED. (This fix had landed for
    `zlog.sh` previously and was never ported.)
  - **`restore` no longer deletes a file it did not write.** The failure path
    ran `Remove-Item $out` unconditionally; a `$wrote` flag now records that
    this run published the destination, so cleanup can only remove our own
    artifact.
  - **`clean`/`deep` now exit non-zero when any file fails.** `DoClean` ended on
    the report line, so a run where every file errored still exited 0.
- `scripts/zlog.ps1` uses `-LiteralPath` for every path derived from user input.
  Plain `Test-Path`/`Remove-Item`/`Get-Item` treat `[` and `]` as wildcard
  character classes, so a destination literally named `srv[1].log` **bypassed
  the "destination exists" guard and the failure-path cleanup entirely** — the
  protection silently did nothing for those names. Reproduced, then fixed.
- `--older-than` now validates its argument. A non-numeric value aborted the
  script under `set -u` with `abc: unbound variable`, and a negative value
  built a nonsense `find -mmin "+-7199"` that reported zero candidates — a
  silent "nothing to do" on a destructive path. Both now exit 2 with a clear
  message; `0` and positive values are unaffected.
- `--older-than` is read as decimal, not octal. Bash treats a leading-zero
  literal as octal, so `010` silently meant 8 days instead of 10, and `08`
  was a hard "value too great for base" error that was swallowed. Leading
  zeros are now stripped, an all-zero value is preserved as `0`, and the
  result is forced to base 10.
- `--older-than` is bounded to 36500 days, checked on the digit string *before*
  any arithmetic. Converting first let `18446744073709551616` wrap to 0 during
  the conversion and slip past the bound, and `days * 1440` overflows 64-bit
  arithmetic well before that.
- `restore` accepts a legitimately empty archive. The `-s` (non-empty) guard
  rejected a 0-byte decompression, so restoring an empty `.log`/`.out`
  reported FAILED and deleted its own output. Corrupt archives are still
  rejected with nothing written, because the decoders themselves exit non-zero.

Tests:

- `tests/test-posix.sh` covers `--older-than` rejection (non-numeric, negative,
  fractional, empty, whitespace, exponent) and acceptance of `0`/positive, plus
  empty-archive restore and corrupt-archive rejection with no partial write.

## Unreleased (hardening: collision, TOCTOU, restore, deep-scan, installer, CI)

- Compression no longer overwrites an existing archive: the destination
  must be absent before publish (POSIX hardlink / no-clobber move,
  .NET `File.Move` on PowerShell); otherwise `UNSAFE-SKIP` with the
  source preserved. Covered by collision fixtures (existing
  `.zst`/`.gz`/`.xz`/`.tar.gz`).
- TOCTOU gap closed: the source's inode/size/mtime is captured before
  compression and verified after (and once more after publish, before
  deletion). A source that changed mid-run is preserved and reported
  `FAILED`. Covered by a racy-compressor fixture.
- TAR restore validates the member name: single-entry archives whose
  member does not exactly equal the intended basename (traversal,
  absolute, or wrong-name entries) are refused as `UNSAFE-SKIP`, and
  extraction always goes to a temp dir first (both platforms).
- POSIX deep scan narrowed from broad `*/AppData/*` to the approved
  `*/AppData/Local/Ollama/*`.
- Removed the duplicate `zlog_candidates()` definition (one shared
  candidate engine; CI now enforces singularity).
- Regression tests expanded: destination collision, empty protected
  files, mid-run modification, malicious/path-traversal TAR, corrupt
  archives, missing compressors, newline filenames, hardlinks,
  permission failures, space-in-path (PowerShell).
- CI runs PowerShell behavioral fixtures on `windows-latest` (was
  `ubuntu-latest`); POSIX fixtures stay on `ubuntu-latest`.
- `install.sh` is atomic: stages the complete skill, validates it, then
  renames into place; the whole previous skill dir is backed up
  (`*.bak.TIMESTAMP`) with rollback on failure.
- README claims aligned with evidence: transcript protection described
  as best-effort filtering; platform support states Linux + Windows 11
  tested, macOS/WSL fallbacks untested.
- Note: earlier entries below described the purge predicate and
  transactional compression as complete before the collision/TOCTOU
  gaps were closed; this entry documents the actual fix.

## Unreleased (review follow-up: deep alias, stronger identity, restore)

- Windows `deep-preview`/`deep` are now an explicit documented alias:
  the standard roots already recurse fully, so there is no separate
  wider scan; the scripts announce this in their output, and `SKILL.md`
  plus `references/safety.md` record it. Covered by deep-alias
  fixtures (read-only preview, end-to-end deep clean).
- PowerShell source identity strengthened from size+mtime to
  size+timestamps+partial-content hash (first/last 64KB SHA-256),
  closer to the POSIX inode/size/mtime check.
- Non-TAR restores (`.gz`/`.zst`/`.xz`) decode to a temp file and move
  it into place on both platforms, so a failed decompression never
  leaves a partial file at the destination. Covered by corrupt-`.gz`
  fixtures asserting no output and no temp leftovers.
- POSIX `deep` end-to-end fixture added (fake HOME).

## Unreleased (review follow-up 2: identity, no-clobber restore, race test)

- PowerShell source identity is now length + timestamps + full-content
  SHA-256 (was first/last-64KB partial hash): a same-size in-place
  rewrite with restored timestamps is detected. Content hashing is the
  right identity here — the danger is changed bytes, not a changed
  inode, and identical bytes are safe to archive either way.
- POSIX TAR restore publishes via hardlink instead of `mv -f`, so no
  `mv -f` remains anywhere in `scripts/zlog.sh`; the CI invariant now
  bans clobbering moves codebase-wide. One rule: never overwrite an
  existing path.
- `references/formats.md` no longer says "atomically renamed": publish
  is described as without-overwrite (POSIX hardlink/no-clobber,
  Windows .NET move), with member validation and temp-file decode.
- Windows race fixture added: a shadowing `tar.exe` function flips one
  middle byte mid-compression while preserving size and timestamps —
  the exact case size+mtime checks miss — and asserts the source is
  preserved with `FAILED (source changed during compression)`. A probe
  gate skips cleanly where function shadowing is unavailable.

## Unreleased (review follow-up 3: single publish helper)

- All POSIX publishes (compression, TAR restore, stream restores) go
  through one `zlog_publish()` helper: destination re-check, atomic
  hardlink, `mv -n` fallback for filesystems without hardlinks. No
  bare `mv` remains on any destructive path; CI asserts the helper is
  used and bans `mv -f` codebase-wide.

## Unreleased (review follow-up 4: wording + skip-proof race CI)

- `SKILL.md` no longer says "byte-identical (inode/size/mtime)": the
  invariant is "source identity unchanged", with the platform
  mechanisms spelled out (POSIX inode/size/mtime, Windows
  length/timestamps/full-content SHA-256).
- CI now requires the TOCTOU race regressions to actually run, not
  skip: both behavior jobs grep their fixture output for
  `PASS: race source preserved` and fail otherwise (ubuntu provides
  `zstd`; `windows-latest` provides function shadowing).

## Unreleased (review follow-up 5: installer tests, metadata, edges)
- `SKILL.md` `last_verified` touched to 2026-09-21.
- `install.sh` accepts a `ZLOG_REPO_RAW` override (default unchanged)
  so integration tests can install from a local `file://` repo.
- New `tests/test-install.sh` (runs in CI): fresh install completeness,
  upgrade backs up the whole previous skill dir, invalid skill aborts
  with the live install untouched, `mv` failure aborts with no
  half-installed stage, and promote failure rolls the previous skill
  back. macOS/WSL execution remains uncovered (no host here) and is
  still documented as untested in the README.
- Leading-dash filename fixture (`-dash.log`): asserts the file is
  never lost without an archive, whatever the platform `tar` decides
  to do with a dash-prefixed member name.
- WSL runtime-tested: the full POSIX suite (zero skips, incl. the
  `zstd` race section via a rootless install) and the installer suite
  pass on Debian WSL2. That box has no `fuser`/`lsof`, so the run also
  covers the age-buffer fallback. README/SKILL.md now list WSL as
  tested; macOS remains untested (no host).
- macOS runtime-tested: new `behavior-macos` CI job on
  `macos-latest` runs the full POSIX + installer suites plus the race
  gate, all green. `tests/test-posix.sh` is now portable (python-based
  mtime helper instead of GNU `touch -d`, `md5` fallback for missing
  `md5sum`); the implementation needed no changes. README/SKILL.md
  now list macOS as tested — every supported platform is covered.
- Social card refreshed: stale "tested on Linux" claims replaced with
  all four platforms, "High-Ratio" replaced with verified-compression
  wording, all 8 runtimes named, safety card reflects protected data;
  compatibility badge now lists Linux, macOS, Windows 11. PNG
  re-rendered from the SVG at 1200x630.

## Unreleased (v2.0.0: skill architecture — brain + scripts + references + tests)

- `SKILL.md` rewritten as the decision brain (Purpose, Use When,
  Don't Use When, Workflow, Safety Rules, Reporting, Edge Cases);
  all shell implementation moved out.
- New `scripts/zlog.sh` / `scripts/zlog.ps1` helpers with modes
  `preview|clean|deep-preview|deep|restore` and `--older-than DAYS`
  retention (`-OlderThanDays` on PowerShell). One shared candidate
  engine serves preview and clean, so previews never disagree.
- New `references/` (`agent-paths.md` with verification dates,
  `safety.md` data classes A-D, `formats.md` incl. restore).
- New `tests/` (`test-posix.sh`, `test-powershell.ps1`): prune,
  symlink escape, purge age/lock, stale artifacts, size guard,
  locks, restore, read-only deep-preview — all passing on Win11
  (PS 5.1) and Git Bash; CI runs them.
- Protected classes extended: `transcript*`, `conversation*`,
  `history*`, `*.sqlite*`, `*.db`, `*.wal`, `*.shm`.
- Fixed PS positional param bug (`restore <path>` bound to the wrong
  parameter) and `tar.exe`-only invocation (now per-platform).
- `install.sh` installs the full skill set; `README.md` shows usage
  only; CI validates behavior, not Markdown sync.

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
