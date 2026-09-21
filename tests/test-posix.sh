#!/bin/bash
# tests/test-posix.sh — fixture tests for scripts/zlog.sh (destructive behavior).
# Run: bash tests/test-posix.sh [path/to/zlog.sh]
set -u
ZLOG_SH="${1:-$(dirname "$0")/../scripts/zlog.sh}"
FX="$(mktemp -d)"; trap 'rm -rf "$FX"' EXIT
export HOME="$FX/home" ZLOG_TEST_ROOT="$FX/home/.claude"
OUT="$FX/outside"
mkdir -p "$ZLOG_TEST_ROOT/node_modules" "$HOME/.cursor" "$OUT"

# Portable helpers (Linux + macOS + Git Bash + WSL):
# BSD touch lacks -d, BSD systems lack md5sum.
touch_old() {
  python3 -c 'import os,sys,time; t=time.time()-300
for p in sys.argv[1:]: os.utime(p,(t,t))' "$@"
}
fsum() { if command -v md5sum >/dev/null 2>&1; then md5sum "$@"; else md5 "$@"; fi }

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
touch_old "$ZLOG_TEST_ROOT/ok.log" "$ZLOG_TEST_ROOT/noise.log" \
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
before=$(find "$HOME" | sort | fsum)
bash "$ZLOG_SH" deep-preview > /dev/null
check "deep-preview changes nothing" "[ \"\$(find $HOME | sort | fsum)\" = \"$before\" ]"

echo "--- collision (existing dest → UNSAFE-SKIP, source preserved) ---"
python3 -c "open('$ZLOG_TEST_ROOT/collide.log','w').write('compressible log line\n'*2000)"
touch_old "$ZLOG_TEST_ROOT/collide.log"
echo "pre-existing-dest" > "$ZLOG_TEST_ROOT/collide.log.zst"
echo "pre-existing-dest" > "$ZLOG_TEST_ROOT/collide.log.gz"
echo "pre-existing-dest" > "$ZLOG_TEST_ROOT/collide.log.xz"
cp "$ZLOG_TEST_ROOT/collide.log.zst" "$FX/collide.zst.orig"
cp "$ZLOG_TEST_ROOT/collide.log.gz" "$FX/collide.gz.orig"
cp "$ZLOG_TEST_ROOT/collide.log.xz" "$FX/collide.xz.orig"
bash "$ZLOG_SH" clean > "$FX/clean2.txt"; cat "$FX/clean2.txt"
check "collision source preserved" "[ -f $ZLOG_TEST_ROOT/collide.log ]"
check "collision dest untouched" "cmp -s $ZLOG_TEST_ROOT/collide.log.zst $FX/collide.zst.orig && cmp -s $ZLOG_TEST_ROOT/collide.log.gz $FX/collide.gz.orig && cmp -s $ZLOG_TEST_ROOT/collide.log.xz $FX/collide.xz.orig"
check "collision reported" "grep -q 'UNSAFE-SKIP' \"\$FX/clean2.txt\""
check "collision no tmp leftovers" "[ -z \"\$(ls $ZLOG_TEST_ROOT/ | grep 'tmp\\.' || true)\" ]"
rm -f "$ZLOG_TEST_ROOT/collide.log" "$ZLOG_TEST_ROOT/collide.log.zst" \
  "$ZLOG_TEST_ROOT/collide.log.gz" "$ZLOG_TEST_ROOT/collide.log.xz"

echo "--- TOCTOU (source changed mid-compression → preserved) ---"
if command -v zstd >/dev/null 2>&1; then
  REAL_ZSTD="$(command -v zstd)"
  mkdir -p "$FX/fakebin"
  printf '#!/bin/bash\nfor a in "$@"; do case "$a" in *.log) [ -f "$a" ] && echo RACE >> "$a" ;; esac; done\nexec "%s" "$@"\n' "$REAL_ZSTD" > "$FX/fakebin/zstd"
  chmod +x "$FX/fakebin/zstd"
  python3 -c "open('$ZLOG_TEST_ROOT/race.log','w').write('compressible log line\n'*2000)"
  touch_old "$ZLOG_TEST_ROOT/race.log"
  PATH="$FX/fakebin:$PATH" bash "$ZLOG_SH" clean > "$FX/clean3.txt"; cat "$FX/clean3.txt"
  check "race source preserved" "[ -f $ZLOG_TEST_ROOT/race.log ]"
  check "race no archive" "[ ! -e $ZLOG_TEST_ROOT/race.log.zst ] && [ ! -e $ZLOG_TEST_ROOT/race.log.gz ] && [ ! -e $ZLOG_TEST_ROOT/race.log.xz ]"
  check "race reported" "grep -q 'source changed' \"\$FX/clean3.txt\""
  rm -f "$ZLOG_TEST_ROOT/race.log" "$ZLOG_TEST_ROOT/race.log".*
  rm -rf "$FX/fakebin"
else
  echo "SKIP: race test (no zstd)"
fi

echo "--- tar traversal / mismatch restore refused ---"
python3 - "$ZLOG_TEST_ROOT" <<'EOF'
import tarfile, sys
root = sys.argv[1]
with tarfile.open(root + '/trav.log.tar.gz', 'w:gz') as t:
    import io
    ti = tarfile.TarInfo('../escape.log'); data = b'evil'
    ti.size = len(data); t.addfile(ti, io.BytesIO(data))
with tarfile.open(root + '/mismatch.log.tar.gz', 'w:gz') as t:
    import io
    ti = tarfile.TarInfo('wrongname.log'); data = b'evil'
    ti.size = len(data); t.addfile(ti, io.BytesIO(data))
EOF
check "traversal refused" "! bash \"$ZLOG_SH\" restore \"$ZLOG_TEST_ROOT/trav.log.tar.gz\""
check "traversal no escape" "[ ! -e $ZLOG_TEST_ROOT/escape.log ] && [ ! -e $FX/escape.log ] && [ ! -e $ZLOG_TEST_ROOT/../escape.log ]"
check "traversal no output" "[ ! -e $ZLOG_TEST_ROOT/trav.log ]"
check "mismatch refused" "! bash \"$ZLOG_SH\" restore \"$ZLOG_TEST_ROOT/mismatch.log.tar.gz\""
check "mismatch no output" "[ ! -e $ZLOG_TEST_ROOT/mismatch.log ]"
check "malicious archives kept" "[ -f $ZLOG_TEST_ROOT/trav.log.tar.gz ] && [ -f $ZLOG_TEST_ROOT/mismatch.log.tar.gz ]"
rm -f "$ZLOG_TEST_ROOT/trav.log.tar.gz" "$ZLOG_TEST_ROOT/mismatch.log.tar.gz"

echo "--- corrupt archive restore ---"
head -c 100 /dev/urandom > "$ZLOG_TEST_ROOT/corrupt.log.zst"
check "corrupt refused" "! bash \"$ZLOG_SH\" restore \"$ZLOG_TEST_ROOT/corrupt.log.zst\""
check "corrupt no output" "[ ! -e $ZLOG_TEST_ROOT/corrupt.log ]"
check "corrupt archive kept" "[ -f $ZLOG_TEST_ROOT/corrupt.log.zst ]"
rm -f "$ZLOG_TEST_ROOT/corrupt.log.zst"

echo "--- corrupt stream restore leaves no partial output ---"
head -c 100 /dev/urandom > "$ZLOG_TEST_ROOT/corrupt2.log.gz"
check "corrupt gz refused" "! bash \"$ZLOG_SH\" restore \"$ZLOG_TEST_ROOT/corrupt2.log.gz\""
check "corrupt gz no output" "[ ! -e $ZLOG_TEST_ROOT/corrupt2.log ]"
check "corrupt gz no tmp leftovers" "[ -z \"\$(ls $ZLOG_TEST_ROOT/ | grep 'tmp\\.restore' || true)\" ]"
check "corrupt gz archive kept" "[ -f $ZLOG_TEST_ROOT/corrupt2.log.gz ]"
rm -f "$ZLOG_TEST_ROOT/corrupt2.log.gz"

echo "--- deep scan end-to-end (fake HOME) ---"
python3 -c "open('$ZLOG_TEST_ROOT/deepfix.log','w').write('compressible log line\n'*2000)"
touch_old "$ZLOG_TEST_ROOT/deepfix.log"
bash "$ZLOG_SH" deep-preview > "$FX/deepprev.txt"
check "deep-preview lists candidate" "grep -q deepfix.log \"\$FX/deepprev.txt\""
before=$(find "$HOME" | sort | fsum)
bash "$ZLOG_SH" deep-preview > /dev/null
check "deep-preview still read-only" "[ \"\$(find $HOME | sort | fsum)\" = \"$before\" ]"
bash "$ZLOG_SH" deep > "$FX/deep.txt"; cat "$FX/deep.txt"
check "deep archived" "[ ! -f $ZLOG_TEST_ROOT/deepfix.log ] && ls $ZLOG_TEST_ROOT/deepfix.log.* >/dev/null"
check "deep report line present" "grep -q '^\\[zlog\\] mode=deep' \"\$FX/deep.txt\""

echo "--- missing compressors (all fail → source preserved) ---"
mkdir -p "$FX/nocomp"
for t in zstd xz gzip; do printf '#!/bin/bash\nexit 1\n' > "$FX/nocomp/$t"; chmod +x "$FX/nocomp/$t"; done
python3 -c "open('$ZLOG_TEST_ROOT/nocomp.log','w').write('compressible log line\n'*2000)"
touch_old "$ZLOG_TEST_ROOT/nocomp.log"
PATH="$FX/nocomp:$PATH" bash "$ZLOG_SH" clean > "$FX/clean4.txt"; cat "$FX/clean4.txt"
check "nocomp source preserved" "[ -f $ZLOG_TEST_ROOT/nocomp.log ]"
check "nocomp no archive" "[ ! -e $ZLOG_TEST_ROOT/nocomp.log.zst ] && [ ! -e $ZLOG_TEST_ROOT/nocomp.log.gz ] && [ ! -e $ZLOG_TEST_ROOT/nocomp.log.xz ]"
rm -f "$ZLOG_TEST_ROOT/nocomp.log"; rm -rf "$FX/nocomp"

echo "--- newline filename ---"
NLFILE="$ZLOG_TEST_ROOT/nl
name.log"
python3 -c "open('$ZLOG_TEST_ROOT/nl\nname.log','w').write('compressible log line\n'*2000)"
touch_old "$NLFILE"
bash "$ZLOG_SH" clean > "$FX/clean5.txt"; cat "$FX/clean5.txt"
check "newline archived" "[ ! -e \"\$NLFILE\" ] && (ls \"$ZLOG_TEST_ROOT\" | grep -q 'nl')"
check "newline no tmp leftovers" "[ -z \"\$(ls $ZLOG_TEST_ROOT/ | grep 'tmp\\.' || true)\" ]"

echo "--- leading-dash filename (never lost, whatever tar decides) ---"
python3 -c "open('$ZLOG_TEST_ROOT/-dash.log','w').write('compressible log line\n'*2000)"
touch_old "$ZLOG_TEST_ROOT/-dash.log"
bash "$ZLOG_SH" clean > "$FX/clean-dash.txt"; cat "$FX/clean-dash.txt"
check "dash never lost" "[ -f $ZLOG_TEST_ROOT/-dash.log ] || ls $ZLOG_TEST_ROOT/-dash.log.* >/dev/null"
check "dash no tmp leftovers" "[ -z \"\$(ls $ZLOG_TEST_ROOT/ | grep 'tmp\\.' || true)\" ]"

echo "--- hardlinks compress independently ---"
python3 -c "open('$ZLOG_TEST_ROOT/hard1.log','w').write('compressible log line\n'*2000)"
ln "$ZLOG_TEST_ROOT/hard1.log" "$ZLOG_TEST_ROOT/hard2.log"
touch_old "$ZLOG_TEST_ROOT/hard1.log" "$ZLOG_TEST_ROOT/hard2.log"
bash "$ZLOG_SH" clean > "$FX/clean6.txt"; cat "$FX/clean6.txt"
check "hardlinks both handled" "[ ! -e $ZLOG_TEST_ROOT/hard1.log ] && [ ! -e $ZLOG_TEST_ROOT/hard2.log ]"
check "hardlinks archives exist" "ls $ZLOG_TEST_ROOT/hard1.log.* >/dev/null && ls $ZLOG_TEST_ROOT/hard2.log.* >/dev/null"

echo "--- permission failure (unreadable source → preserved) ---"
python3 -c "open('$ZLOG_TEST_ROOT/noperm.log','w').write('compressible log line\n'*2000)"
touch_old "$ZLOG_TEST_ROOT/noperm.log"
chmod 000 "$ZLOG_TEST_ROOT/noperm.log"
if cat "$ZLOG_TEST_ROOT/noperm.log" >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
  echo "SKIP: permission test (running as root)"
else
  bash "$ZLOG_SH" clean > "$FX/clean7.txt"; cat "$FX/clean7.txt"
  if cat "$ZLOG_TEST_ROOT/noperm.log" >/dev/null 2>&1; then
    echo "SKIP: permission test (chmod not enforced here)"
  else
    check "noperm preserved" "[ -f $ZLOG_TEST_ROOT/noperm.log ]"
  fi
fi
chmod 644 "$ZLOG_TEST_ROOT/noperm.log" 2>/dev/null; rm -f "$ZLOG_TEST_ROOT/noperm.log"

if [ "$fail" -eq 0 ]; then echo "POSIX TESTS ALL PASS"; else echo "POSIX TESTS FAILED"; fi
exit $fail
