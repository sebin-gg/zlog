#!/bin/bash
# tests/test-posix.sh — fixture tests for scripts/zlog.sh (destructive behavior).
# Run: bash tests/test-posix.sh [path/to/zlog.sh]
set -u
ZLOG_SH="${1:-$(dirname "$0")/../scripts/zlog.sh}"
FX="$(mktemp -d)"; trap 'rm -rf "$FX"' EXIT
export HOME="$FX/home" ZLOG_TEST_ROOT="$FX/home/.claude"
OUT="$FX/outside"
mkdir -p "$ZLOG_TEST_ROOT/node_modules" "$HOME/.cursor" "$OUT"

python3 -c "open('$ZLOG_TEST_ROOT/ok.log','w').write('compressible log line\n'*2000)"
head -c 20480 /dev/urandom > "$ZLOG_TEST_ROOT/noise.log"
head -c 20480 /dev/urandom > "$OUT/secret.log"
ln -s "$OUT" "$ZLOG_TEST_ROOT/linkdir"
ln -s ok.log "$ZLOG_TEST_ROOT/link.log"
head -c 20480 /dev/urandom > "$ZLOG_TEST_ROOT/stale.log"
head -c 100 /dev/urandom > "$ZLOG_TEST_ROOT/stale.log.zst"
: > "$ZLOG_TEST_ROOT/oldempty.log"
: > "$ZLOG_TEST_ROOT/newempty.log"
: > "$ZLOG_TEST_ROOT/transcript_empty.log"
: > "$ZLOG_TEST_ROOT/history.log"
: > "$ZLOG_TEST_ROOT/conversation.out"
head -c 20480 /dev/urandom > "$ZLOG_TEST_ROOT/node_modules/junk.log"
head -c 20480 /dev/urandom > "$ZLOG_TEST_ROOT/keep.jsonl"
head -c 20480 /dev/urandom > "$ZLOG_TEST_ROOT/transcript.log"
head -c 20480 /dev/urandom > "$ZLOG_TEST_ROOT/data.sqlite-wal"
head -c 20480 /dev/urandom > "$ZLOG_TEST_ROOT/small.log"
touch -d '5 minutes ago' "$ZLOG_TEST_ROOT/ok.log" "$ZLOG_TEST_ROOT/noise.log" \
  "$OUT/secret.log" "$ZLOG_TEST_ROOT/stale.log" "$ZLOG_TEST_ROOT/stale.log.zst" \
  "$ZLOG_TEST_ROOT/oldempty.log" "$ZLOG_TEST_ROOT/node_modules/junk.log" \
  "$ZLOG_TEST_ROOT/keep.jsonl" "$ZLOG_TEST_ROOT/transcript.log" \
  "$ZLOG_TEST_ROOT/transcript_empty.log" "$ZLOG_TEST_ROOT/history.log" \
  "$ZLOG_TEST_ROOT/conversation.out"

fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi }

echo "--- preview (must change nothing) ---"
bash "$ZLOG_SH" preview > "$FX/prev.txt"
check "preview lists candidate" "grep -q ok.log \"\$FX/prev.txt\""
check "preview changes nothing" "[ -f $ZLOG_TEST_ROOT/ok.log ]"

echo "--- clean ---"
bash "$ZLOG_SH" clean > "$FX/clean.txt"; cat "$FX/clean.txt"
check "compressible archived" "[ ! -f $ZLOG_TEST_ROOT/ok.log ] && ls $ZLOG_TEST_ROOT/ok.log.* >/dev/null"
check "symlink escape blocked" "[ -f $OUT/secret.log ] && [ ! -e $OUT/secret.log.zst ] && [ ! -e $OUT/secret.log.gz ] && [ ! -e $OUT/secret.log.xz ]"
check "old empty purged" "[ ! -f $ZLOG_TEST_ROOT/oldempty.log ]"
check "fresh empty kept" "[ -f $ZLOG_TEST_ROOT/newempty.log ]"
check "empty transcript protected" "[ -f $ZLOG_TEST_ROOT/transcript_empty.log ]"
check "empty history protected" "[ -f $ZLOG_TEST_ROOT/history.log ]"
check "empty conversation protected" "[ -f $ZLOG_TEST_ROOT/conversation.out ]"
check "junk kept" "[ -f $ZLOG_TEST_ROOT/node_modules/junk.log ]"
check "high-entropy kept" "[ -f $ZLOG_TEST_ROOT/noise.log ]"
check "stale artifact not counted" "[ -f $ZLOG_TEST_ROOT/stale.log ]"
check "jsonl kept" "[ -f $ZLOG_TEST_ROOT/keep.jsonl ]"
check "transcript kept" "[ -f $ZLOG_TEST_ROOT/transcript.log ]"
check "sqlite-wal kept" "[ -f $ZLOG_TEST_ROOT/data.sqlite-wal ]"
check "small kept" "[ -f $ZLOG_TEST_ROOT/small.log ]"
check "no tmp leftovers" "[ -z \"\$(ls $ZLOG_TEST_ROOT/ | grep 'tmp\\.' || true)\" ]"
check "report line present" "grep -q '^\\[zlog\\] mode=clean' \"\$FX/clean.txt\""

echo "--- restore ---"
ARCH=$(ls "$ZLOG_TEST_ROOT"/ok.log.* | head -n 1)
bash "$ZLOG_SH" restore "$ARCH" > "$FX/rest.txt"; cat "$FX/rest.txt"
check "restored" "[ -f $ZLOG_TEST_ROOT/ok.log ] && [ -f \"$ARCH\" ]"
check "restore refuses existing dest" "! bash \"$ZLOG_SH\" restore \"$ARCH\""

echo "--- deep-preview read-only ---"
before=$(find "$HOME" | sort | md5sum)
bash "$ZLOG_SH" deep-preview > /dev/null
check "deep-preview changes nothing" "[ \"\$(find $HOME | sort | md5sum)\" = \"$before\" ]"

if [ "$fail" -eq 0 ]; then echo "POSIX TESTS ALL PASS"; else echo "POSIX TESTS FAILED"; fi
exit $fail
