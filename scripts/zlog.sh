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

ZLOG_MMIN="+1"
MODE="${1:-}"
shift || true
if [ "${1:-}" = "--older-than" ]; then
  ZLOG_MMIN="+$(( ${2:-0} * 1440 + 1 ))"
  shift 2 || true
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

# Transactional compression of one file.
# Sets ZLOG_STATUS to: COMPRESSED | UNSAFE-SKIP | FAILED | NOT_BENEFICIAL
# and ZLOG_NEW / ZLOG_NEWSIZE on success. Never overwrites an existing
# archive; never deletes a source that changed during compression.
zlog_compress_one() {
  local f="$1" size="$2" tmp="" ext="" ok=0 dest="" newsize="" pre="" cur=""
  ZLOG_STATUS="FAILED"; ZLOG_NEW=""; ZLOG_NEWSIZE=0
  pre=$(zlog_ident "$f" 2>/dev/null) || { echo "[zlog] FAILED (source unreadable): $f (original preserved)"; return 0; }
  if command -v zstd >/dev/null 2>&1; then
    tmp="$f.$$.tmp.zst"
    if zstd -15 -q "$f" -o "$tmp" 2>/dev/null && zstd -t -q "$tmp" 2>/dev/null; then ext=zst; ok=1; else rm -f "$tmp" 2>/dev/null; fi
  fi
  if [ "$ok" -eq 0 ] && command -v xz >/dev/null 2>&1; then
    tmp="$f.$$.tmp.xz"
    if xz -9 -c "$f" > "$tmp" 2>/dev/null && xz -t "$tmp" 2>/dev/null; then ext=xz; ok=1; else rm -f "$tmp" 2>/dev/null; fi
  fi
  if [ "$ok" -eq 0 ]; then
    tmp="$f.$$.tmp.gz"
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
  # Publish without overwriting: hardlink tmp to dest fails if dest exists
  # (same directory, so same filesystem). Falls back to no-clobber move.
  if ln "$tmp" "$dest" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
  elif mv -n "$tmp" "$dest" 2>/dev/null && [ -e "$dest" ] && [ ! -e "$tmp" ]; then
    :
  else
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
  while IFS= read -r -d '' d; do
    roots=$((roots + 1))
    while IFS= read -r -d '' f; do
      [ -z "$f" ] && continue
      if zlog_locked "$f"; then locked=$((locked + 1)); skipped=$((skipped + 1)); continue; fi
      rm -f "$f" 2>/dev/null && purged=$((purged + 1)) || { failed=$((failed + 1)); }
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
}

DEEP_PATHS=(-path "*/.claude/*" -o -path "*/.config/claude-code/*" -o -path "*/.gemini/*" \
  -o -path "*/.config/Cursor/*" -o -path "*/.cursor/*" -o -path "*/.ollama/*" \
  -o -path "*/.windsurf/*" -o -path "*/.codex/*" -o -path "*/.cache/lm-studio/*" \
  -o -path "*/.lmstudio/*" -o -path "*/.aider/*" \
  -o -path "*/Library/Application Support/Cursor/*" \
  -o -path "*/Library/Application Support/Windsurf/*" \
  -o -path "*/.config/Windsurf/*" -o -path "*/AppData/Local/Ollama/*")

zlog_deep_candidates() {
  # read-only candidate listing; caller decides preview vs clean
  find ~ -maxdepth 12 \( -type d \( "${PRUNE[@]}" \) -prune \) -o \( "${DEEP_PATHS[@]}" \) -type f \
    \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) \
    -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" \
    -not -name "*.tmp.*" -not -name "*.jsonl" \
    -not -name "transcript*" -not -name "conversation*" -not -name "history*" \
    -not -name "*.sqlite*" -not -name "*.db" -not -name "*.wal" -not -name "*.shm" \
    -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" \
    -size +10k -mmin "$ZLOG_MMIN" -print0 2>/dev/null
}

do_deep_preview() {
  local candidates=0 raw=0
  echo "[zlog] deep-preview is read-only; known agent locations only (no unknown-agent discovery)"
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    s=$(zlog_size "$f"); raw=$((raw + s)); candidates=$((candidates + 1))
    echo "[DRY-RUN] Would compress: $f ($(zlog_hum "$s"))"
  done < <(zlog_deep_candidates) || true
  pruned=$(find ~ -maxdepth 12 -type d \( "${PRUNE[@]}" \) -prune -print 2>/dev/null | wc -l)
  echo ""
  echo "[DRY-RUN] Deep total: $candidates files, $(zlog_hum "$raw") raw; pruned $pruned junk/cache dirs (maxdepth 12)"
}

do_deep() {
  local candidates=0 compressed=0 raw=0 saved=0 skipped=0 failed=0 notbene=0 locked=0
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
  done < <(zlog_deep_candidates) || true
  pruned=$(find ~ -maxdepth 12 -type d \( "${PRUNE[@]}" \) -prune -print 2>/dev/null | wc -l)
  zlog_report deep 1 "$candidates" "$compressed" "$raw" "$saved" 0 "$skipped" "$failed" "$notbene" "$locked"
  echo "[zlog] Pruned $pruned junk/cache dirs (maxdepth 12)"
}

do_restore() {
  # restore FILE... : decompress archives back next to the original name
  [ "$#" -gt 0 ] || { echo "[zlog] restore: no files given" >&2; exit 2; }
  local ok=0 fail=0
  for a in "$@"; do
    case "$a" in
      *.tar.gz) out="${a%.tar.gz}" ;;
      *.zst) out="${a%.zst}" ;;
      *.gz) out="${a%.gz}" ;;
      *.xz) out="${a%.xz}" ;;
      *) echo "[zlog] UNSAFE-SKIP (unknown format): $a"; fail=$((fail + 1)); continue ;;
    esac
    if [ -e "$out" ]; then echo "[zlog] UNSAFE-SKIP (destination exists): $out"; fail=$((fail + 1)); continue; fi
    rc=1
    case "$a" in
      *.tar.gz)
        # Created by tar -czf with a single entry. Require exactly one
        # member whose name equals the intended basename, extract to a
        # temp dir, and move the entry out. Anything else is UNSAFE-SKIP.
        tmpd="$out.$$.restore.dir"; tmpf="$tmpd/$(basename "$out")"
        if [ "$(tar -tzf "$a" 2>/dev/null | wc -l)" -eq 1 ] \
          && [ "$(tar -tzf "$a" 2>/dev/null)" = "$(basename "$out")" ] \
          && mkdir -p "$tmpd" 2>/dev/null && tar -xzf "$a" -C "$tmpd" 2>/dev/null \
          && [ -f "$tmpf" ] && [ ! -L "$tmpf" ] && mv -f "$tmpf" "$out" 2>/dev/null; then rc=0;
        else
          echo "[zlog] UNSAFE-SKIP (member mismatch or multi-entry): $a" >&2
        fi
        rm -rf "$tmpd" 2>/dev/null
        ;;
      *.zst) command -v zstd >/dev/null 2>&1 && zstd -d -q "$a" -o "$out" 2>/dev/null && rc=0 ;;
      *.gz) gzip -d -c "$a" > "$out" 2>/dev/null && rc=0 ;;
      *.xz) command -v xz >/dev/null 2>&1 && xz -d -c "$a" > "$out" 2>/dev/null && rc=0 ;;
    esac
    if [ "$rc" -eq 0 ] && [ -s "$out" ]; then echo "[zlog] RESTORED: $out (archive preserved)"; ok=$((ok + 1)); else rm -f "$out" 2>/dev/null; echo "[zlog] FAILED: $a (nothing written)"; fail=$((fail + 1)); fi
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
