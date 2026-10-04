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
# BSD touch lacks -d, BSD systems lack sha256sum.
touch_old() {
  python3 -c 'import os,sys,time; t=time.time()-300
for p in sys.argv[1:]: os.utime(p,(t,t))' "$@"
}
# SHA-256 rather than MD5: this only fingerprints a file listing to prove a
# command changed nothing, but a weak hash trips Sonar rule S4790
# (weak-hash), which is pure noise for a test helper.
fsum() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi }
# GNU vs BSD stat, mirroring zlog.sh's own fallback.
fstat() { stat -c '%s %Y' "$1" 2>/dev/null || stat -f '%z %m' "$1" 2>/dev/null; }
# Fingerprint the whole tree: path, entry type, size, mtime and content hash.
#
# The old form was `find "$HOME" | sort | fsum`, which hashed the *path list
# only*. A file could be truncated, appended to, or rewritten in place and the
# "deep-preview changes nothing" assertions would still pass — verified: an
# in-place same-length rewrite produced an identical fingerprint.
#
# NUL-separated throughout, deliberately without `sort`: the fixture contains a
# newline-bearing filename, so any newline-delimited pipeline would split it, and
# `sort -z` does not exist on BSD. find's own order is stable for an unchanged
# tree, which is the only case this needs to compare.
tree_sum() {
  find "$HOME" -print0 | while IFS= read -r -d '' p; do
    if [ -L "$p" ]; then
      printf '%s\0L\0%s\0' "$p" "$(readlink "$p" 2>/dev/null)"
    elif [ -d "$p" ]; then
      printf '%s\0D\0%s\0' "$p" "$(fstat "$p")"
    elif [ -f "$p" ]; then
      printf '%s\0F\0%s\0%s\0' "$p" "$(fstat "$p")" "$(fsum "$p" 2>/dev/null | cut -d' ' -f1)"
    else
      printf '%s\0?\0' "$p"
    fi
  done | fsum
}

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
# `check` eval's its second argument, so every variable that reaches it must be
# quoted *inside the eval'd string* as well. An unquoted `$HOME` there splits on
# whitespace and the test silently FAILS (not skips) whenever the path contains
# a space — which is exactly the portability this suite exists to prove.
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi }
# tree_sum is defined with fsum/fstat near the top of this file.

echo "--- preview (must change nothing) ---"
bash "$ZLOG_SH" preview > "$FX/prev.txt"
check "preview lists candidate" "grep -q ok.log \"\$FX/prev.txt\""
check "preview changes nothing" "[ -f \"$ZLOG_TEST_ROOT\"/ok.log ]"

echo "--- clean ---"
bash "$ZLOG_SH" clean > "$FX/clean.txt"; cat "$FX/clean.txt"
check "compressible archived" "[ ! -f \"$ZLOG_TEST_ROOT\"/ok.log ] && ls \"$ZLOG_TEST_ROOT\"/ok.log.* >/dev/null"
check "symlink escape blocked" "[ -f \"$OUT\"/secret.log ] && [ ! -e \"$OUT\"/secret.log.zst ] && [ ! -e \"$OUT\"/secret.log.gz ] && [ ! -e \"$OUT\"/secret.log.xz ]"
check "old empty purged" "[ ! -f \"$ZLOG_TEST_ROOT\"/oldempty.log ]"
check "fresh empty kept" "[ -f \"$ZLOG_TEST_ROOT\"/newempty.log ]"
check "empty transcript protected" "[ -f \"$ZLOG_TEST_ROOT\"/transcript_empty.log ]"
check "empty history protected" "[ -f \"$ZLOG_TEST_ROOT\"/history.log ]"
check "empty conversation protected" "[ -f \"$ZLOG_TEST_ROOT\"/conversation.out ]"
check "junk kept" "[ -f \"$ZLOG_TEST_ROOT\"/node_modules/junk.log ]"
check "high-entropy kept" "[ -f \"$ZLOG_TEST_ROOT\"/noise.log ]"
check "stale artifact not counted" "[ -f \"$ZLOG_TEST_ROOT\"/stale.log ]"
check "jsonl kept" "[ -f \"$ZLOG_TEST_ROOT\"/keep.jsonl ]"
check "transcript kept" "[ -f \"$ZLOG_TEST_ROOT\"/transcript.log ]"
check "sqlite-wal kept" "[ -f \"$ZLOG_TEST_ROOT\"/data.sqlite-wal ]"
check "small kept" "[ -f \"$ZLOG_TEST_ROOT\"/small.log ]"
check "no tmp leftovers" "[ -z \"\$(ls \"$ZLOG_TEST_ROOT\"/ | grep 'tmp\\.' || true)\" ]"
check "report line present" "grep -q '^\\[zlog\\] mode=clean' \"\$FX/clean.txt\""

echo "--- restore ---"
ARCH=$(ls "$ZLOG_TEST_ROOT"/ok.log.* | head -n 1)
bash "$ZLOG_SH" restore "$ARCH" > "$FX/rest.txt"; cat "$FX/rest.txt"
check "restored" "[ -f \"$ZLOG_TEST_ROOT\"/ok.log ] && [ -f \"$ARCH\" ]"
check "restore refuses existing dest" "! bash \"$ZLOG_SH\" restore \"$ARCH\""

echo "--- tree fingerprint is actually sensitive ---"
# Guard the guard. tree_sum backs the two "deep-preview changes nothing"
# assertions; when it hashed only the path list, a file could be rewritten in
# place and those checks still passed. Prove the fingerprint reacts to a
# same-length content change, a truncation and a new file, then restore.
FP="$ZLOG_TEST_ROOT/fp.log"
python3 -c "open('$FP','w').write('A'*4096)"
fp_a=$(tree_sum)
python3 -c "open('$FP','w').write('B'*4096)"
fp_b=$(tree_sum)
check "fingerprint sees same-length content change" "[ \"$fp_a\" != \"$fp_b\" ]"
: > "$FP"
fp_c=$(tree_sum)
check "fingerprint sees truncation" "[ \"$fp_b\" != \"$fp_c\" ]"
: > "$ZLOG_TEST_ROOT/fp-extra.log"
fp_d=$(tree_sum)
check "fingerprint sees a new file" "[ \"$fp_c\" != \"$fp_d\" ]"
rm -f "$FP" "$ZLOG_TEST_ROOT/fp-extra.log"
check "fingerprint is stable when nothing changes" "[ \"\$(tree_sum)\" = \"$(tree_sum)\" ]"

echo "--- deep-preview read-only ---"
before=$(tree_sum)
bash "$ZLOG_SH" deep-preview > /dev/null
check "deep-preview changes nothing" "[ \"\$(tree_sum)\" = \"$before\" ]"

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
check "collision source preserved" "[ -f \"$ZLOG_TEST_ROOT\"/collide.log ]"
check "collision dest untouched" "cmp -s \"$ZLOG_TEST_ROOT\"/collide.log.zst \"$FX\"/collide.zst.orig && cmp -s \"$ZLOG_TEST_ROOT\"/collide.log.gz \"$FX\"/collide.gz.orig && cmp -s \"$ZLOG_TEST_ROOT\"/collide.log.xz \"$FX\"/collide.xz.orig"
check "collision reported" "grep -q 'UNSAFE-SKIP' \"\$FX/clean2.txt\""
check "collision no tmp leftovers" "[ -z \"\$(ls \"$ZLOG_TEST_ROOT\"/ | grep 'tmp\\.' || true)\" ]"
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
  check "race source preserved" "[ -f \"$ZLOG_TEST_ROOT\"/race.log ]"
  check "race no archive" "[ ! -e \"$ZLOG_TEST_ROOT\"/race.log.zst ] && [ ! -e \"$ZLOG_TEST_ROOT\"/race.log.gz ] && [ ! -e \"$ZLOG_TEST_ROOT\"/race.log.xz ]"
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
check "traversal no escape" "[ ! -e \"$ZLOG_TEST_ROOT\"/escape.log ] && [ ! -e \"$FX\"/escape.log ] && [ ! -e \"$ZLOG_TEST_ROOT\"/../escape.log ]"
check "traversal no output" "[ ! -e \"$ZLOG_TEST_ROOT\"/trav.log ]"
check "mismatch refused" "! bash \"$ZLOG_SH\" restore \"$ZLOG_TEST_ROOT/mismatch.log.tar.gz\""
check "mismatch no output" "[ ! -e \"$ZLOG_TEST_ROOT\"/mismatch.log ]"
check "malicious archives kept" "[ -f \"$ZLOG_TEST_ROOT\"/trav.log.tar.gz ] && [ -f \"$ZLOG_TEST_ROOT\"/mismatch.log.tar.gz ]"
rm -f "$ZLOG_TEST_ROOT/trav.log.tar.gz" "$ZLOG_TEST_ROOT/mismatch.log.tar.gz"

echo "--- corrupt archive restore ---"
head -c 100 /dev/urandom > "$ZLOG_TEST_ROOT/corrupt.log.zst"
check "corrupt refused" "! bash \"$ZLOG_SH\" restore \"$ZLOG_TEST_ROOT/corrupt.log.zst\""
check "corrupt no output" "[ ! -e \"$ZLOG_TEST_ROOT\"/corrupt.log ]"
check "corrupt archive kept" "[ -f \"$ZLOG_TEST_ROOT\"/corrupt.log.zst ]"
rm -f "$ZLOG_TEST_ROOT/corrupt.log.zst"

echo "--- corrupt stream restore leaves no partial output ---"
head -c 100 /dev/urandom > "$ZLOG_TEST_ROOT/corrupt2.log.gz"
check "corrupt gz refused" "! bash \"$ZLOG_SH\" restore \"$ZLOG_TEST_ROOT/corrupt2.log.gz\""
check "corrupt gz no output" "[ ! -e \"$ZLOG_TEST_ROOT\"/corrupt2.log ]"
check "corrupt gz no tmp leftovers" "[ -z \"\$(ls \"$ZLOG_TEST_ROOT\"/ | grep 'tmp\\.restore' || true)\" ]"
check "corrupt gz archive kept" "[ -f \"$ZLOG_TEST_ROOT\"/corrupt2.log.gz ]"
rm -f "$ZLOG_TEST_ROOT/corrupt2.log.gz"

echo "--- deep scan end-to-end (fake HOME) ---"
python3 -c "open('$ZLOG_TEST_ROOT/deepfix.log','w').write('compressible log line\n'*2000)"
touch_old "$ZLOG_TEST_ROOT/deepfix.log"
bash "$ZLOG_SH" deep-preview > "$FX/deepprev.txt"
check "deep-preview lists candidate" "grep -q deepfix.log \"\$FX/deepprev.txt\""
before=$(tree_sum)
bash "$ZLOG_SH" deep-preview > /dev/null
check "deep-preview still read-only" "[ \"\$(tree_sum)\" = \"$before\" ]"
bash "$ZLOG_SH" deep > "$FX/deep.txt"; cat "$FX/deep.txt"
check "deep archived" "[ ! -f \"$ZLOG_TEST_ROOT\"/deepfix.log ] && ls \"$ZLOG_TEST_ROOT\"/deepfix.log.* >/dev/null"
check "deep report line present" "grep -q '^\\[zlog\\] mode=deep' \"\$FX/deep.txt\""

echo "--- missing compressors (all fail → source preserved) ---"
mkdir -p "$FX/nocomp"
for t in zstd xz gzip; do printf '#!/bin/bash\nexit 1\n' > "$FX/nocomp/$t"; chmod +x "$FX/nocomp/$t"; done
python3 -c "open('$ZLOG_TEST_ROOT/nocomp.log','w').write('compressible log line\n'*2000)"
touch_old "$ZLOG_TEST_ROOT/nocomp.log"
PATH="$FX/nocomp:$PATH" bash "$ZLOG_SH" clean > "$FX/clean4.txt"; cat "$FX/clean4.txt"
check "nocomp source preserved" "[ -f \"$ZLOG_TEST_ROOT\"/nocomp.log ]"
check "nocomp no archive" "[ ! -e \"$ZLOG_TEST_ROOT\"/nocomp.log.zst ] && [ ! -e \"$ZLOG_TEST_ROOT\"/nocomp.log.gz ] && [ ! -e \"$ZLOG_TEST_ROOT\"/nocomp.log.xz ]"
rm -f "$ZLOG_TEST_ROOT/nocomp.log"; rm -rf "$FX/nocomp"

echo "--- newline filename ---"
NLFILE="$ZLOG_TEST_ROOT/nl
name.log"
python3 -c "open('$ZLOG_TEST_ROOT/nl\nname.log','w').write('compressible log line\n'*2000)"
touch_old "$NLFILE"
bash "$ZLOG_SH" clean > "$FX/clean5.txt"; cat "$FX/clean5.txt"
check "newline archived" "[ ! -e \"\$NLFILE\" ] && (ls \"\$ZLOG_TEST_ROOT\" | grep -q 'nl')"
check "newline no tmp leftovers" "[ -z \"\$(ls \"$ZLOG_TEST_ROOT\"/ | grep 'tmp\\.' || true)\" ]"

echo "--- leading-dash filename (never lost, whatever tar decides) ---"
python3 -c "open('$ZLOG_TEST_ROOT/-dash.log','w').write('compressible log line\n'*2000)"
touch_old "$ZLOG_TEST_ROOT/-dash.log"
bash "$ZLOG_SH" clean > "$FX/clean-dash.txt"; cat "$FX/clean-dash.txt"
check "dash never lost" "[ -f \"$ZLOG_TEST_ROOT\"/-dash.log ] || ls \"$ZLOG_TEST_ROOT\"/-dash.log.* >/dev/null"
check "dash no tmp leftovers" "[ -z \"\$(ls \"$ZLOG_TEST_ROOT\"/ | grep 'tmp\\.' || true)\" ]"

echo "--- hardlinks compress independently ---"
python3 -c "open('$ZLOG_TEST_ROOT/hard1.log','w').write('compressible log line\n'*2000)"
ln "$ZLOG_TEST_ROOT/hard1.log" "$ZLOG_TEST_ROOT/hard2.log"
touch_old "$ZLOG_TEST_ROOT/hard1.log" "$ZLOG_TEST_ROOT/hard2.log"
bash "$ZLOG_SH" clean > "$FX/clean6.txt"; cat "$FX/clean6.txt"
check "hardlinks both handled" "[ ! -e \"$ZLOG_TEST_ROOT\"/hard1.log ] && [ ! -e \"$ZLOG_TEST_ROOT\"/hard2.log ]"
check "hardlinks archives exist" "ls \"$ZLOG_TEST_ROOT\"/hard1.log.* >/dev/null && ls \"$ZLOG_TEST_ROOT\"/hard2.log.* >/dev/null"

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
    check "noperm preserved" "[ -f \"$ZLOG_TEST_ROOT\"/noperm.log ]"
  fi
fi
chmod 644 "$ZLOG_TEST_ROOT/noperm.log" 2>/dev/null; rm -f "$ZLOG_TEST_ROOT/noperm.log"

echo "--- --older-than rejects non-numeric and negative values ---"
# Unvalidated, these either abort under `set -u` ("abc: unbound variable") or
# build a nonsense `find -mmin "+-7199"` that reports zero candidates, which
# reads as a clean bill of health on a destructive path.
for bad in abc -5 1.5 "" " " 1e3; do
  out=$(bash "$ZLOG_SH" preview --older-than "$bad" 2>&1); rc=$?
  check "--older-than '$bad' rejected (rc=2)" "[ $rc -eq 2 ]"
  check "--older-than '$bad' explains itself" "printf '%s' \"\$out\" | grep -qi 'non-negative'"
done
out=$(bash "$ZLOG_SH" preview --older-than 2>&1); rc=$?
check "--older-than with no value rejected (rc=2)" "[ $rc -eq 2 ]"
out=$(bash "$ZLOG_SH" preview --older-than 0 2>&1); rc=$?
check "--older-than 0 accepted" "[ $rc -eq 0 ]"
out=$(bash "$ZLOG_SH" preview --older-than 7 2>&1); rc=$?
check "--older-than 7 accepted" "[ $rc -eq 0 ]"

echo "--- --older-than is decimal, not octal, and bounded ---"
# Bash reads a leading-zero literal as octal: `010` would silently mean 8 days
# and `08` is a hard "value too great for base" error that used to be swallowed.
# Large values also overflow `days * 1440` into a wrong (possibly negative)
# -mmin threshold, selecting the wrong files.
for v in 0 00 000 00010 7 08 09 010 0010 00010 36500; do
  out=$(bash "$ZLOG_SH" preview --older-than "$v" 2>&1); rc=$?
  check "--older-than '$v' accepted as decimal" "[ $rc -eq 0 ]"
  # Accepting must also be silent. Stripping the zeros from 0/00/000 used to
  # leave an empty string, so `10#` errored on stderr while the script still
  # exited 0 — an rc-only assertion missed it.
  check "--older-than '$v' emits no shell error" "! printf '%s' \"\$out\" | grep -qiE 'invalid integer|value too great|unbound variable'"
done
for v in 36501 99999 18446744073709551616 99999999999999999999; do
  out=$(bash "$ZLOG_SH" preview --older-than "$v" 2>&1); rc=$?
  check "--older-than '$v' rejected (out of range)" "[ $rc -eq 2 ]"
  check "--older-than '$v' explains the bound" "printf '%s' \"\$out\" | grep -qi '36500'"
done

echo "--- restoring an empty file succeeds ---"
# A 0-byte original is a legitimate `.log`. The old `-s` guard demanded a
# non-empty temp file, so every empty archive reported FAILED and deleted its
# own output. Corrupt archives must still be rejected with nothing written.
RD="$FX/restore-empty"; mkdir -p "$RD"
: > "$RD/empty.log"; gzip -9 -c "$RD/empty.log" > "$RD/empty.log.gz" 2>/dev/null
rm -f "$RD/empty.log"
out=$(bash "$ZLOG_SH" restore "$RD/empty.log.gz" 2>&1); rc=$?
check "empty restore succeeds" "[ $rc -eq 0 ] && [ -f \"\$RD/empty.log\" ]"
check "empty restore reports RESTORED" "printf '%s' \"\$out\" | grep -q RESTORED"
printf 'NOT A VALID GZIP STREAM' > "$RD/corrupt.log.gz"
out=$(bash "$ZLOG_SH" restore "$RD/corrupt.log.gz" 2>&1); rc=$?
check "corrupt archive still rejected" "[ $rc -ne 0 ]"
check "corrupt archive writes nothing" "[ ! -e \"\$RD/corrupt.log\" ]"
check "corrupt leaves no tmp" "[ -z \"\$(ls \"$RD\" | grep 'tmp' || true)\" ]"

echo "--- restore never deletes a pre-existing dangling symlink ---"
# `[ -e ]` is FALSE for a dangling symlink, so the old guard let one through and
# the failure-path `rm -f "$out"` destroyed it — deleting a file zlog never
# created, while reporting "nothing written". Assert on lexists, not -e, since
# -e is exactly the test that used to lie.
SY="$FX/symdest"; mkdir -p "$SY"
printf 'NOT A VALID ARCHIVE' > "$SY/svc.log.gz"
ln -s "$SY/ghost-target" "$SY/svc.log"
out=$(bash "$ZLOG_SH" restore "$SY/svc.log.gz" 2>&1); rc=$?
check "dangling symlink dest refused" "[ $rc -ne 0 ]"
check "dangling symlink survives (lexists)" "[ -L \"$SY/svc.log\" ]"
check "symlink target still missing" "[ ! -e \"$SY/ghost-target\" ]"
check "no partial output beside symlink" "[ -z \"\$(ls \"$SY\" | grep -v -e svc.log -e svc.log.gz -e ghost-target || true)\" ]"
# A *valid* archive must also refuse rather than replace the symlink.
printf 'payload\n' > "$SY/p2.log"; gzip -9 -c "$SY/p2.log" > "$SY/p2.log.gz" 2>/dev/null
rm -f "$SY/p2.log"; ln -s "$SY/ghost2" "$SY/p2.log"
out=$(bash "$ZLOG_SH" restore "$SY/p2.log.gz" 2>&1); rc=$?
check "valid archive also refuses symlink dest" "[ $rc -ne 0 ]"
check "symlink not replaced by real file" "[ -L \"$SY/p2.log\" ] && [ ! -f \"$SY/p2.log\" ]"
rm -rf "$SY"

echo "--- purge never deletes a file that gained content mid-run (TOCTOU) ---"
# find(1) reports the file empty, but a writer appends before the rm. The purge
# loop used a bare `rm -f` with no identity re-check, so the append was lost and
# the report said `purged=1 failed=0`. The invariant we can assert without
# winning the race: if the file exists afterwards, its content is intact.
TG="$FX/toctou"; mkdir -p "$TG"
toctou_bad=0
for i in 1 2 3 4 5; do
  t="$TG/t$i.log"; : > "$t"; touch_old "$t"
  ( sleep 0.01; printf 'LIVE SESSION DATA\n' >> "$t" ) &
  ZLOG_TEST_ROOT="$TG" bash "$ZLOG_SH" clean >/dev/null 2>&1
  wait
  # Race-free invariant: whatever the interleaving, a surviving file must still
  # hold the writer's bytes. A file zlog deleted outright is also a loss, so
  # also require that a file which gained content was never removed.
  if [ ! -e "$t" ]; then
    toctou_bad=$((toctou_bad + 1))
  elif ! grep -q 'LIVE SESSION DATA' "$t" 2>/dev/null; then
    toctou_bad=$((toctou_bad + 1))
  fi
done
check "purge never loses a concurrent writer's data" "[ $toctou_bad -eq 0 ]"
rm -rf "$TG"

echo "--- clean/deep exit non-zero when files fail ---"
# do_clean used to end on the `du` pipeline, so a run where every file errored
# still exited 0 and any caller gating on the exit code read it as success.
mkdir -p "$FX/deadc"
for t in zstd xz gzip; do printf '#!/bin/bash\nexit 1\n' > "$FX/deadc/$t"; chmod +x "$FX/deadc/$t"; done
python3 -c "open('$FX/deadc/f.log','w').write('compressible log line\n'*2000)"
touch_old "$FX/deadc/f.log"
PATH="$FX/deadc:$PATH" ZLOG_TEST_ROOT="$FX/deadc" bash "$ZLOG_SH" clean > "$FX/deadc.txt" 2>&1; rc=$?
check "clean reports failed>0" "grep -q 'failed=1' \"$FX/deadc.txt\""
check "clean exits non-zero when files fail" "[ $rc -ne 0 ]"
rm -rf "$FX/deadc"

echo "--- purge quarantines the name before deciding ---"
# The rename is the load-bearing part: after it a writer that opens by path
# cannot reach the file, so the check-then-unlink window no longer exists. A
# writer that gets there first must also never lose bytes — the file is put
# back untouched when it turns out non-empty.
PQ="$FX/quarantine"; mkdir -p "$PQ"
# (a) still empty at resolve time -> purged
: > "$PQ/empty.log"; touch_old "$PQ/empty.log"
ZLOG_TEST_ROOT="$PQ" bash "$ZLOG_SH" clean > "$FX/pq1.txt" 2>&1
check "quarantine purges a still-empty file" "[ ! -e \"$PQ/empty.log\" ]"
check "quarantine leaves no .purge debris" "[ -z \"\$(ls \"$PQ\" | grep 'purge' || true)\" ]"
check "quarantine reports purged" "grep -q 'purged=1' \"$FX/pq1.txt\""
# (b) gains content before resolve -> put back, byte-for-byte
: > "$PQ/grew.log"; touch_old "$PQ/grew.log"
python3 -c "open('$PQ/grew.log','a').write('LIVE SESSION DATA\n')" &
wait
ZLOG_TEST_ROOT="$PQ" bash "$ZLOG_SH" clean > "$FX/pq2.txt" 2>&1
check "non-empty file survives the purge" "[ -f \"$PQ/grew.log\" ]"
check "its bytes are intact" "grep -q 'LIVE SESSION DATA' \"$PQ/grew.log\""
check "no .purge debris after skip" "[ -z \"\$(ls \"$PQ\" | grep 'purge' || true)\" ]"
rm -rf "$PQ"

echo "--- quarantine is never orphaned by an interrupt ---"
# The rename and the unlink are separate steps, so a signal can land between
# them. The invariant that must hold afterwards: a file that was mid-quarantine
# is either resolved (purged, because it was still empty) or put back — never
# left behind as <name>.purge debris with no record of where it came from.
# This also guards the artifact-vs-exit-status rule: if the rename succeeded but
# mv was then killed, the non-zero status must not be read as "nothing moved".
QI="$FX/qint"; mkdir -p "$QI"
: > "$QI/victim.log"; touch_old "$QI/victim.log"
if command -v setsid >/dev/null 2>&1; then
  mkdir -p "$FX/qbin"
  cat > "$FX/qbin/mv" <<'MVEOF'
#!/bin/bash
# Perform the real rename, then stall when the destination is a quarantine
# target, so the signal lands while the file is quarantined.
src=""; dst=""
for a in "$@"; do
  case "$a" in
    -n) ;;
    *) if [ -z "$src" ]; then src="$a"; elif [ -z "$dst" ]; then dst="$a"; fi ;;
  esac
done
/bin/mv -n "$src" "$dst" 2>/dev/null || exit 1
case "$dst" in *.purge) sleep 3 ;; esac
exit 0
MVEOF
  chmod +x "$FX/qbin/mv"
  cat > "$FX/run_qint.sh" <<RUNNER
#!/bin/bash
echo \$\$ > "$QI/pg.pid"
exec env PATH="$FX/qbin:\$PATH" ZLOG_TEST_ROOT="$QI" bash "$ZLOG_SH" clean
RUNNER
  chmod +x "$FX/run_qint.sh"
  setsid bash "$FX/run_qint.sh" >/dev/null 2>&1 &
  i=0
  while [ ! -s "$QI/pg.pid" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i + 1)); done
  # wait until the file is genuinely quarantined
  i=0
  while [ -z "$(ls "$QI" 2>/dev/null | grep 'purge' || true)" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i + 1)); done
  check "test reached the quarantined state" "[ -n \"\$(ls \"$QI\" | grep 'purge' || true)\" ]"
  pgid=$(cat "$QI/pg.pid" 2>/dev/null || echo "")
  [ -n "$pgid" ] && kill -TERM -- "-$pgid" 2>/dev/null
  i=0
  while [ -n "$(ls "$QI" 2>/dev/null | grep 'purge' || true)" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i + 1)); done
  [ -n "$pgid" ] && kill -9 -- "-$pgid" 2>/dev/null
  check "interrupt leaves no orphaned .purge debris" "[ -z \"\$(ls \"$QI\" | grep 'purge' || true)\" ]"
  rm -rf "$FX/qbin" "$FX/run_qint.sh"
else
  echo "SKIP: quarantine interrupt (no setsid)"
fi
rm -rf "$QI"

echo "--- tmp artifacts cleaned up on interrupt ---"
# Temp files live next to their source and exist for as long as the compressor
# runs. The script had no trap at all, so a Ctrl-C (which the tty delivers to
# the whole foreground process group, killing the compressor mid-write) left a
# truncated *.tmp.zst behind in the user's log directory.
#
# The stub must CREATE the temp before stalling, exactly as `zstd -o` does —
# a stub that merely sleeps first never creates the artifact and the test passes
# vacuously against the unfixed script.
IC="$FX/interrupt"; mkdir -p "$IC"
REAL_ZSTD2="$(command -v zstd || true)"
if [ -n "$REAL_ZSTD2" ]; then
  mkdir -p "$FX/slowbin"
  cat > "$FX/slowbin/zstd" <<STUB
#!/bin/bash
out=""; prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && out="\$a"; prev="\$a"; done
[ -n "\$out" ] && printf 'PARTIAL' > "\$out"
sleep 3
exec "$REAL_ZSTD2" "\$@"
STUB
  chmod +x "$FX/slowbin/zstd"
  python3 -c "open('$IC/big.log','w').write('compressible log line\n'*40000)"
  touch_old "$IC/big.log"
  # A terminal's Ctrl-C delivers SIGINT to the entire foreground process GROUP,
  # so the compressor, its `sleep` and the script all die at the same instant.
  # Reproducing that faithfully matters: if only the compressor is signalled,
  # the script simply takes its normal "compressor failed" branch and removes
  # the temp by itself — which is why an earlier version of this test passed
  # vacuously against the unfixed script. For the unfixed script the shell dies
  # before it can run that `rm -f`, leaving a truncated *.tmp.zst behind.
  #
  # setsid puts the script in its own session so we can signal that group
  # without hitting the test runner itself.
  # Use SIGTERM, not SIGINT: bash *defers* SIGINT while a foreground child runs,
  # so the shell survives, takes its normal "compressor failed" branch and
  # removes the temp itself — the unfixed script then passes, which is how an
  # earlier version of this test passed vacuously. SIGTERM is not special-cased,
  # so an untrapped script dies before it can run that `rm -f`.
  if command -v setsid >/dev/null 2>&1; then
    cat > "$FX/run_clean.sh" <<RUNNER
#!/bin/bash
echo \$\$ > "$IC/pg.pid"
exec env PATH="$FX/slowbin:\$PATH" ZLOG_TEST_ROOT="$IC" bash "$ZLOG_SH" clean
RUNNER
    chmod +x "$FX/run_clean.sh"
    setsid bash "$FX/run_clean.sh" >/dev/null 2>&1 &
    i=0
    while [ ! -s "$IC/pg.pid" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i + 1)); done
    # wait until the compressor has actually written the temp
    i=0
    while [ -z "$(ls "$IC" 2>/dev/null | grep 'tmp\.' || true)" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i + 1)); done
    pgid=$(cat "$IC/pg.pid" 2>/dev/null || echo "")
    [ -n "$pgid" ] && kill -TERM -- "-$pgid" 2>/dev/null
    # Poll rather than `wait`: the trap removes the temp asynchronously, and a
    # fixed sleep would make this test flaky in the passing direction.
    i=0
    while [ -n "$(ls "$IC" 2>/dev/null | grep 'tmp\.' || true)" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i + 1)); done
    check "interrupt leaves no tmp artifacts" "[ -z \"\$(ls \"$IC\" | grep 'tmp\\.' || true)\" ]"
    [ -n "$pgid" ] && kill -9 -- "-$pgid" 2>/dev/null
    rm -rf "$FX/slowbin" "$FX/run_clean.sh"
  else
    echo "SKIP: interrupt cleanup (no setsid to create a process group)"
  fi
else
  echo "SKIP: interrupt cleanup (no zstd)"
fi
rm -rf "$IC"



if [ "$fail" -eq 0 ]; then echo "POSIX TESTS ALL PASS"; else echo "POSIX TESTS FAILED"; fi
exit $fail
