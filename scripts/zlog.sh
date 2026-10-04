#!/bin/bash
# zlog.sh — POSIX implementation helper for the zlog Agent Skill.
# This is NOT a standalone product CLI. The skill invokes it; humans may
# run it by hand for testing. All destructive behavior lives here so it
# can be tested without parsing Markdown.
#
# Usage: zlog.sh preview|clean|deep-preview|deep|restore [--older-than DAYS] [FILE...]
#   preview       list compression candidates, change nothing
#   clean         compress candidates in known agent roots
#   deep-preview  list candidates under known locations (read-only, no changes)
#   deep          compress candidates under known locations
#   restore FILE...  decompress archives back next to the original name
#   --older-than DAYS  only touch files older than DAYS (default: 0 = 60s age buffer)
set -u

# Temp artifacts are written next to their source (same filesystem, so publish
# can hardlink them into place) and named with $$. Record every one so an
# interrupt cannot leave them behind: the suite asserts "no tmp leftovers", but
# only ever after a clean exit.
ZLOG_TEMPS=()
zlog_track() { ZLOG_TEMPS+=("$1"); }
zlog_cleanup() {
  local t
  for t in ${ZLOG_TEMPS[@]+"${ZLOG_TEMPS[@]}"}; do
    [ -n "$t" ] && rm -rf "$t" 2>/dev/null
  done
  return 0
}
trap 'zlog_cleanup' EXIT
trap 'zlog_cleanup; exit 130' INT
trap 'zlog_cleanup; exit 143' TERM

ZLOG_MMIN="+1"
MODE="${1:-}"
shift || true
if [ "${1:-}" = "--older-than" ]; then
  # Validate before using the value in arithmetic. An unvalidated value either
  # aborts the whole script with `set -u` ("abc: unbound variable") or, when
  # negative, builds a nonsense `find -mmin "+-7199"` that silently reports
  # zero candidates — a false "nothing to do" on a destructive path.
  ZLOG_DAYS="${2:-}"
  shift 2 2>/dev/null || shift $# 2>/dev/null || true
  case "$ZLOG_DAYS" in
    ''|*[!0-9]*)
      echo "zlog: --older-than needs a non-negative whole number of days, got: '${ZLOG_DAYS}'" >&2
      exit 2
      ;;
  esac
  # Normalise as a *string* first. Bash reads a leading-zero literal as octal,
  # so `010` would silently mean 8 days and `08` is a hard "value too great for
  # base" error. Stripping the zeros from `0`/`00`/`000` yields an empty string,
  # so restore a single `0` before the arithmetic ever runs.
  ZLOG_DAYS="${ZLOG_DAYS#"${ZLOG_DAYS%%[!0]*}"}"
  [ -n "$ZLOG_DAYS" ] || ZLOG_DAYS="0"
  # Range-check as a string, *before* arithmetic. Converting first lets a value
  # such as 18446744073709551616 wrap to 0 during the conversion and slip past
  # the bound, and `days * 1440` overflows 64-bit arithmetic well before that.
  if [ "${#ZLOG_DAYS}" -gt 5 ] || { [ "${#ZLOG_DAYS}" -eq 5 ] && [ "$ZLOG_DAYS" -gt 36500 ]; }; then
    echo "zlog: --older-than must be 36500 days (100 years) or less, got: '${ZLOG_DAYS}'" >&2
    exit 2
  fi
  ZLOG_MMIN="+$(( 10#$ZLOG_DAYS * 1440 + 1 ))"
fi

PRUNE=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" \
  -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache \
  -o -name DawnWebGPUCache -o -name .git)

zlog_roots() {
  if [ -n "${ZLOG_TEST_ROOT:-}" ]; then
    [ -d "$ZLOG_TEST_ROOT" ] && printf '%s\0' "$ZLOG_TEST_ROOT"
    return
  fi
  for d in ~/.claude ~/.config/claude-code ~/.config/Cursor ~/.cursor \
      ~/.gemini ~/.ollama ~/.windsurf ~/.codex ~/.cache/lm-studio \
      ~/.lmstudio ~/.aider \
      "$HOME/Library/Application Support/Cursor" \
      "$HOME/Library/Application Support/Windsurf" \
      ~/.config/Windsurf "$HOME/AppData/Local/Ollama"; do
    [ -d "$d" ] && [ ! -L "$d" ] && printf '%s\0' "$d"
  done
}

# Shared candidate engine: one predicate used by preview AND clean, so the
# preview can never disagree with cleanup. (Never follows symlinks: no -L
# anywhere in this script, so scans cannot escape the listed roots.)

zlog_candidates() {
  find "$1" \( -type d \( "${PRUNE[@]}" \) -prune \) -o \( -type f \
    \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) \
    -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" \
    -not -name "*.tmp.*" -not -name "*.jsonl" \
    -not -name "transcript*" -not -name "conversation*" -not -name "history*" \
    -not -name "*.sqlite*" -not -name "*.db" -not -name "*.wal" -not -name "*.shm" \
    -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" \
    -size +10k -mmin "$ZLOG_MMIN" -print0 \) 2>/dev/null
}

zlog_purge_candidates() {
  # Same protected-file rules as zlog_candidates (Class B always excluded),
  # only the size test differs: empty files instead of +10k.
  find "$1" \( -type d \( "${PRUNE[@]}" \) -prune \) -o \( -type f \
    \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) \
    -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" \
    -not -name "*.tmp.*" -not -name "*.jsonl" \
    -not -name "transcript*" -not -name "conversation*" -not -name "history*" \
    -not -name "*.sqlite*" -not -name "*.db" -not -name "*.wal" -not -name "*.shm" \
    -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" \
    -empty -mmin "$ZLOG_MMIN" -print0 \) 2>/dev/null
}

zlog_locked() {
  # returns 0 when another process holds the file (skip it)
  if command -v fuser >/dev/null 2>&1 && fuser -s "$1" 2>/dev/null; then return 0; fi
  if command -v lsof >/dev/null 2>&1 && lsof "$1" >/dev/null 2>&1; then return 0; fi
  return 1
}

zlog_hum() {
  echo "$1" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}'
}

# Shared candidate engine. Prints NUL-delimited candidates for one root.
# (Used by BOTH preview and clean — one engine, preview never disagrees.)

# Portable file identity: "inode size mtime" (Linux stat -c, macOS stat -f).
zlog_ident() {
  local i="" s="" m=""
  if i=$(stat -c '%i %s %Y' "$1" 2>/dev/null); then printf '%s' "$i"; return 0; fi
  if i=$(stat -f '%i %z %m' "$1" 2>/dev/null); then printf '%s' "$i"; return 0; fi
  return 1
}

# Publish a temp file as its final name without overwriting anything.
# Temp and dest are always in the same directory (same filesystem), so a
# hardlink fails atomically when the destination exists; the mv -n
# fallback covers filesystems without hardlink support. Returns 0 only
# when dest now holds the content and tmp is gone. This is the single
# publish path for every destructive operation in this script.
zlog_publish() {
  # `[ -e ]` follows symlinks, so it is FALSE for a *dangling* symlink sitting
  # at the destination. A bare `-e` guard waves that case through, and the
  # caller's failure-path `rm -f` then deletes a pre-existing file this script
  # never created and never owned. Test for any pre-existing entry, symlink or
  # not, at both the pre-check and the post-ln re-check.
  if [ -e "$2" ] || [ -L "$2" ]; then return 1; fi
  if ln "$1" "$2" 2>/dev/null; then rm -f "$1" 2>/dev/null; return 0; fi
  if [ -e "$2" ] || [ -L "$2" ]; then return 1; fi
  # `mv -n` exits 0 even when it declines to overwrite, so success means: tmp is
  # gone AND dest is a visible regular file that is not a symlink.
  if mv -n "$1" "$2" 2>/dev/null && [ ! -e "$1" ] && [ ! -L "$1" ] \
     && [ -f "$2" ] && [ ! -L "$2" ]; then return 0; fi
  return 1
}

# Transactional compression of one file.
# Sets ZLOG_STATUS to: COMPRESSED | UNSAFE-SKIP | FAILED | NOT_BENEFICIAL
# and ZLOG_NEW / ZLOG_NEWSIZE on success. Never overwrites an existing
# archive; never deletes a source that changed during compression.
zlog_compress_one() {
  local f="$1" size="$2" tmp="" ext="" ok=0 dest="" newsize="" pre="" cur=""
  ZLOG_STATUS="FAILED"; ZLOG_NEW=""; ZLOG_NEWSIZE=0
  pre=$(zlog_ident "$f" 2>/dev/null) || { echo "[zlog] FAILED (source unreadable): $f (original preserved)"; return 0; }
  if command -v zstd >/dev/null 2>&1; then
    tmp="$f.$$.tmp.zst"; zlog_track "$tmp"
    if zstd -15 -q "$f" -o "$tmp" 2>/dev/null && zstd -t -q "$tmp" 2>/dev/null; then ext=zst; ok=1; else rm -f "$tmp" 2>/dev/null; fi
  fi
  if [ "$ok" -eq 0 ] && command -v xz >/dev/null 2>&1; then
    tmp="$f.$$.tmp.xz"; zlog_track "$tmp"
    if xz -9 -c "$f" > "$tmp" 2>/dev/null && xz -t "$tmp" 2>/dev/null; then ext=xz; ok=1; else rm -f "$tmp" 2>/dev/null; fi
  fi
  if [ "$ok" -eq 0 ]; then
    tmp="$f.$$.tmp.gz"; zlog_track "$tmp"
    if gzip -9 -c "$f" > "$tmp" 2>/dev/null && gzip -t "$tmp" 2>/dev/null; then ext=gz; ok=1; else rm -f "$tmp" 2>/dev/null; fi
  fi
  [ "$ok" -eq 1 ] || { echo "[zlog] FAILED (compressor error): $f (original preserved)"; return 0; }
  dest="$f.$ext"
  if [ -e "$dest" ]; then
    rm -f "$tmp" 2>/dev/null
    ZLOG_STATUS="UNSAFE-SKIP"
    echo "[zlog] UNSAFE-SKIP (destination exists): $dest (source preserved)"
    return 0
  fi
  cur=$(zlog_ident "$f" 2>/dev/null) || cur=""
  if [ -z "$cur" ] || [ "$cur" != "$pre" ]; then
    rm -f "$tmp" 2>/dev/null
    ZLOG_STATUS="FAILED"
    echo "[zlog] FAILED (source changed during compression): $f (original preserved)"
    return 0
  fi
  newsize=$(stat -c%s "$tmp" 2>/dev/null || stat -f%z "$tmp" 2>/dev/null || echo 0)
  newsize=${newsize:-0}
  case "$newsize" in ''|*[!0-9]*) newsize=0 ;; esac
  if [ "$newsize" -le 0 ] || [ "$newsize" -ge "$size" ]; then
    rm -f "$tmp" 2>/dev/null
    ZLOG_STATUS="NOT_BENEFICIAL"
    return 0
  fi
  # Publish without overwriting (single rule on every destructive path).
  if ! zlog_publish "$tmp" "$dest"; then
    rm -f "$tmp" 2>/dev/null
    ZLOG_STATUS="UNSAFE-SKIP"
    echo "[zlog] UNSAFE-SKIP (destination exists): $dest (source preserved)"
    return 0
  fi
  # Final check: source must still be identical before removal.
  cur=$(zlog_ident "$f" 2>/dev/null) || cur=""
  if [ -z "$cur" ] || [ "$cur" != "$pre" ]; then
    rm -f "$dest" 2>/dev/null
    ZLOG_STATUS="FAILED"
    echo "[zlog] FAILED (source changed during compression): $f (original preserved)"
    return 0
  fi
  rm -f "$f" 2>/dev/null
  ZLOG_STATUS="COMPRESSED"; ZLOG_NEW="$dest"; ZLOG_NEWSIZE=$newsize
}

zlog_report() {
  # $1=mode $2=roots $3=candidates $4=compressed $5=raw $6=saved $7=purged $8=skipped $9=failed $10=notbene $11=locked
  local comp=$(( $5 - $6 ))
  echo "[zlog] mode=$1 roots=$2 candidates=$3 compressed=$4 purged=$7 skipped=$8 failed=$9 not_beneficial=${10} locked=${11}"
  echo "[zlog] raw=$(zlog_hum "$5") compressed=$(zlog_hum "$comp") saved=$(zlog_hum "$6")"
}

zlog_size() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0
}

do_preview() {
  local roots=0 candidates=0 raw=0
  while IFS= read -r -d '' d; do
    roots=$((roots + 1))
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      s=$(zlog_size "$f"); raw=$((raw + s)); candidates=$((candidates + 1))
      echo "[DRY-RUN] Would compress: $f ($(zlog_hum "$s"))"
    done < <(zlog_candidates "$d") || true
  done < <(zlog_roots) || true
  echo ""
  echo "[DRY-RUN] Total: $candidates files, $(zlog_hum "$raw") raw (compressed size varies by log content; run clean for measured savings)"
}

do_clean() {
  local roots=0 candidates=0 compressed=0 raw=0 saved=0 purged=0 skipped=0 failed=0 notbene=0 locked=0
  local ppre="" pcur=""
  while IFS= read -r -d '' d; do
    roots=$((roots + 1))
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      if zlog_locked "$f"; then locked=$((locked + 1)); skipped=$((skipped + 1)); continue; fi
      # find(1) decided this file was empty, but a writer may have appended
      # since that decision. Re-read the identity and the size immediately
      # before the destructive step and skip on any change, mirroring the two
      # zlog_ident checks the compress path already makes. zlog_locked is not
      # a substitute: lsof/fuser miss a writer that opened, wrote and closed
      # inside the window, and without this the loss is reported as
      # `purged=1 failed=0` — invisible.
      ppre=$(zlog_ident "$f" 2>/dev/null) || ppre=""
      if [ -z "$ppre" ]; then failed=$((failed + 1)); continue; fi
      pcur=$(zlog_ident "$f" 2>/dev/null) || pcur=""
      if [ -z "$pcur" ] || [ "$pcur" != "$ppre" ] || [ -s "$f" ]; then
        skipped=$((skipped + 1)); continue
      fi
      if rm -f "$f" 2>/dev/null; then purged=$((purged + 1)); else failed=$((failed + 1)); fi
    done < <(zlog_purge_candidates "$d") || true
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      candidates=$((candidates + 1))
      s=$(zlog_size "$f")
      if zlog_locked "$f"; then locked=$((locked + 1)); skipped=$((skipped + 1)); continue; fi
      zlog_compress_one "$f" "$s"
      case "$ZLOG_STATUS" in
        COMPRESSED) raw=$((raw + s)); saved=$((saved + s - ZLOG_NEWSIZE)); compressed=$((compressed + 1)) ;;
        NOT_BENEFICIAL) notbene=$((notbene + 1)); skipped=$((skipped + 1)) ;;
        UNSAFE-SKIP) skipped=$((skipped + 1)) ;;
        *) failed=$((failed + 1)) ;;
      esac
    done < <(zlog_candidates "$d") || true
  done < <(zlog_roots) || true
  zlog_report clean "$roots" "$candidates" "$compressed" "$raw" "$saved" "$purged" "$skipped" "$failed" "$notbene" "$locked"
  local dirs=()
  while IFS= read -r -d '' d; do dirs+=("$d"); done < <(zlog_roots) || true
  [ "${#dirs[@]}" -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
  # Propagate failure. The `failed` counter is only visible in the report line,
  # and do_clean's last statement is the `du` pipeline above — so without this
  # a run where every single file errored still exits 0, and any caller gating
  # on the exit status (SKILL.md documents FAILED as an exit-code failure)
  # reads total failure as success.
  [ "$failed" -eq 0 ]
}

DEEP_PATHS=(-path "*/.claude/*" -o -path "*/.config/claude-code/*" -o -path "*/.gemini/*" \
  -o -path "*/.config/Cursor/*" -o -path "*/.cursor/*" -o -path "*/.ollama/*" \
  -o -path "*/.windsurf/*" -o -path "*/.codex/*" -o -path "*/.cache/lm-studio/*" \
  -o -path "*/.lmstudio/*" -o -path "*/.aider/*" \
  -o -path "*/Library/Application Support/Cursor/*" \
  -o -path "*/Library/Application Support/Windsurf/*" \
  -o -path "*/.config/Windsurf/*" -o -path "*/AppData/Local/Ollama/*")

zlog_deep_candidates() {
  # read-only candidate listing; caller decides preview vs clean.
  #
  # Emits TWO record kinds over a single walk of $HOME: the prune branch
  # -print0s each junk directory it skips, the candidate branch -print0s each
  # log file. Callers separate them with `[ -d ]` (a pruned record is always a
  # real directory, a candidate always a real file), which is what lets deep
  # and deep-preview report the prune count without paying for a second full
  # traversal of the home directory.
  find ~ -maxdepth 12 \( -type d \( "${PRUNE[@]}" \) -prune -print0 \) -o \( "${DEEP_PATHS[@]}" \) -type f \
    \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) \
    -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" \
    -not -name "*.tmp.*" -not -name "*.jsonl" \
    -not -name "transcript*" -not -name "conversation*" -not -name "history*" \
    -not -name "*.sqlite*" -not -name "*.db" -not -name "*.wal" -not -name "*.shm" \
    -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" \
    -size +10k -mmin "$ZLOG_MMIN" -print0 2>/dev/null
}

do_deep_preview() {
  local candidates=0 raw=0 pruned=0
  echo "[zlog] deep-preview is read-only; known agent locations only (no unknown-agent discovery)"
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    # Pruned-record or candidate? See zlog_deep_candidates: one walk emits
    # both, and only the prune branch can yield a directory.
    if [ -d "$f" ]; then pruned=$((pruned + 1)); continue; fi
    s=$(zlog_size "$f"); raw=$((raw + s)); candidates=$((candidates + 1))
    echo "[DRY-RUN] Would compress: $f ($(zlog_hum "$s"))"
  done < <(zlog_deep_candidates) || true
  echo ""
  echo "[DRY-RUN] Deep total: $candidates files, $(zlog_hum "$raw") raw; pruned $pruned junk/cache dirs (maxdepth 12)"
}

do_deep() {
  local candidates=0 compressed=0 raw=0 saved=0 skipped=0 failed=0 notbene=0 locked=0 pruned=0
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    if [ -d "$f" ]; then pruned=$((pruned + 1)); continue; fi
    candidates=$((candidates + 1))
    s=$(zlog_size "$f")
    if zlog_locked "$f"; then locked=$((locked + 1)); skipped=$((skipped + 1)); continue; fi
    zlog_compress_one "$f" "$s"
    case "$ZLOG_STATUS" in
      COMPRESSED) raw=$((raw + s)); saved=$((saved + s - ZLOG_NEWSIZE)); compressed=$((compressed + 1)) ;;
      NOT_BENEFICIAL) notbene=$((notbene + 1)); skipped=$((skipped + 1)) ;;
      UNSAFE-SKIP) skipped=$((skipped + 1)) ;;
      *) failed=$((failed + 1)) ;;
    esac
  done < <(zlog_deep_candidates) || true
  zlog_report deep 1 "$candidates" "$compressed" "$raw" "$saved" 0 "$skipped" "$failed" "$notbene" "$locked"
  echo "[zlog] Pruned $pruned junk/cache dirs (maxdepth 12)"
  # Same exit-status contract as do_clean: a deep run where every file errored
  # must not look successful to a caller gating on the exit code.
  [ "$failed" -eq 0 ]
}

do_restore() {
  # restore FILE... : decompress archives back next to the original name
  [ "$#" -gt 0 ] || { echo "[zlog] restore: no files given" >&2; exit 2; }
  local ok=0 fail=0 rc=1 out="" tmp="" tmpd="" tmpf="" wrote=0
  for a in "$@"; do
    case "$a" in
      *.tar.gz) out="${a%.tar.gz}" ;;
      *.zst) out="${a%.zst}" ;;
      *.gz) out="${a%.gz}" ;;
      *.xz) out="${a%.xz}" ;;
      *) echo "[zlog] UNSAFE-SKIP (unknown format): $a"; fail=$((fail + 1)); continue ;;
    esac
    # `[ -e ]` is FALSE for a dangling symlink, so a symlink parked at the
    # destination used to slip past this guard and then get destroyed by the
    # failure-path `rm -f "$out"` below — deleting a file zlog never created.
    # `-L` closes that; together they mean "any pre-existing entry blocks us".
    if [ -e "$out" ] || [ -L "$out" ]; then
      echo "[zlog] UNSAFE-SKIP (destination exists): $out"; fail=$((fail + 1)); continue
    fi
    rc=1; wrote=0
    case "$a" in
      *.tar.gz)
        # Created by tar -czf with a single entry. Require exactly one
        # member whose name equals the intended basename, extract to a
        # temp dir, and publish without overwriting. Anything else is
        # UNSAFE-SKIP. (No clobbering move anywhere in this script.)
        tmpd="$out.$$.restore.dir"; zlog_track "$tmpd"; tmpf="$tmpd/$(basename "$out")"
        if [ "$(tar -tzf "$a" 2>/dev/null | wc -l)" -eq 1 ] \
          && [ "$(tar -tzf "$a" 2>/dev/null)" = "$(basename "$out")" ] \
          && mkdir -p "$tmpd" 2>/dev/null && tar -xzf "$a" -C "$tmpd" 2>/dev/null \
          && [ -f "$tmpf" ] && [ ! -L "$tmpf" ] && [ ! -e "$out" ] && [ ! -L "$out" ] \
          && zlog_publish "$tmpf" "$out" && wrote=1; then rc=0;
        else
          echo "[zlog] UNSAFE-SKIP (member mismatch, multi-entry, or destination busy): $a" >&2
        fi
        rm -rf "$tmpd" 2>/dev/null
        ;;
      # Stream formats decode to a temp file first: a decompression
      # failure must never leave a partial file at the destination.
      *.zst) tmp="$out.$$.tmp.restore"; zlog_track "$tmp"; rm -f "$tmp" 2>/dev/null
        if command -v zstd >/dev/null 2>&1 && zstd -d -q "$a" -o "$tmp" 2>/dev/null \
          && [ -f "$tmp" ] && [ ! -L "$tmp" ] && zlog_publish "$tmp" "$out" && wrote=1; then rc=0; else rc=1; rm -f "$tmp" 2>/dev/null; fi ;;
      *.gz) tmp="$out.$$.tmp.restore"; zlog_track "$tmp"; rm -f "$tmp" 2>/dev/null
        if gzip -d -c "$a" > "$tmp" 2>/dev/null \
          && [ -f "$tmp" ] && [ ! -L "$tmp" ] && zlog_publish "$tmp" "$out" && wrote=1; then rc=0; else rc=1; rm -f "$tmp" 2>/dev/null; fi ;;
      *.xz) tmp="$out.$$.tmp.restore"; zlog_track "$tmp"; rm -f "$tmp" 2>/dev/null
        if command -v xz >/dev/null 2>&1 && xz -d -c "$a" > "$tmp" 2>/dev/null \
          && [ -f "$tmp" ] && [ ! -L "$tmp" ] && zlog_publish "$tmp" "$out" && wrote=1; then rc=0; else rc=1; rm -f "$tmp" 2>/dev/null; fi ;;
    esac
    # `wrote` records that THIS run published the destination, so the cleanup
    # below can only ever remove our own artifact. Without it, any failure that
    # happened to leave a pre-existing entry in place would delete it.
    if [ "$rc" -eq 0 ] && [ "$wrote" -eq 1 ] && [ -f "$out" ] && [ ! -L "$out" ]; then
      echo "[zlog] RESTORED: $out (archive preserved)"; ok=$((ok + 1))
    else
      [ "$wrote" -eq 1 ] && rm -f "$out" 2>/dev/null
      echo "[zlog] FAILED: $a (nothing written)"; fail=$((fail + 1))
    fi
  done
  echo "[zlog] restore: ok=$ok failed=$fail"
  [ "$fail" -eq 0 ]
}

case "$MODE" in
  preview) do_preview ;;
  clean) do_clean ;;
  deep-preview) do_deep_preview ;;
  deep) do_deep ;;
  restore) do_restore "$@" ;;
  *) echo "Usage: $0 preview|clean|deep-preview|deep|restore [--older-than DAYS] [FILE...]" >&2; exit 2 ;;
esac
