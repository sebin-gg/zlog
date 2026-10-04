#!/bin/bash
# tests/test-install.sh — integration tests for install.sh
# (fresh install, upgrade backup, invalid-skill abort, rename-failure rollback).
# Run: bash tests/test-install.sh [repo-root]
# Uses a file:// repo override plus a temp HOME; no network access.
set -u
REPO="${1:-$(dirname "$0")/..}"
REPO="$(cd "$REPO" && pwd)"
FX="$(mktemp -d)"; trap 'chmod -R u+rwX "$FX" 2>/dev/null; rm -rf "$FX"' EXIT
export HOME="$FX/home"
mkdir -p "$HOME" "$FX/repo"
# Mirror install.sh's array exactly — a space-joined string here would let the
# fixture drift from what the installer actually installs.
SKILL_FILES=(
  SKILL.md
  scripts/zlog.sh
  scripts/zlog.ps1
  references/agent-paths.md
  references/safety.md
  references/formats.md
)
for f in "${SKILL_FILES[@]}"; do
  mkdir -p "$FX/repo/$(dirname "$f")"
  cp "$REPO/$f" "$FX/repo/$f"
done

fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi }
DEST="$HOME/.agents/skills/zlog"

echo "--- fresh install ---"
ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i1.txt" \
  || { echo "FAIL: fresh install exited nonzero"; fail=1; }
for f in "${SKILL_FILES[@]}"; do
  check "installed $f" "[ -s \"$DEST/$f\" ]"
done
check "executable bit" "[ -x \"$DEST/scripts/zlog.sh\" ]"
check "frontmatter" "head -1 \"$DEST/SKILL.md\" | grep -q '^---\$'"

echo "--- upgrade backs up whole previous dir ---"
echo "OLD-MARKER" >> "$DEST/SKILL.md"
ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i2.txt" \
  || { echo "FAIL: upgrade exited nonzero"; fail=1; }
BACKUP="$(ls -d "$DEST".bak.* 2>/dev/null | head -n 1)"
check "backup dir created" "[ -n \"$BACKUP\" ] && [ -d \"$BACKUP\" ]"
check "backup has old content" "grep -q OLD-MARKER \"$BACKUP/SKILL.md\""
check "live dir fresh" "! grep -q OLD-MARKER \"$DEST/SKILL.md\""
check "backup is full skill" "[ -s \"$BACKUP/scripts/zlog.sh\" ] && [ -s \"$BACKUP/references/safety.md\" ]"

echo "--- invalid skill aborts, live untouched ---"
cp "$DEST/SKILL.md" "$FX/live-skill.bak"
printf 'garbage-no-frontmatter\n' > "$FX/repo/SKILL.md"
if ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i3.txt" 2>&1; then
  echo "FAIL: invalid skill accepted"; fail=1
else
  echo "PASS: invalid skill rejected"
fi
check "live untouched" "cmp -s \"$DEST/SKILL.md\" \"$FX/live-skill.bak\""
cp "$REPO/SKILL.md" "$FX/repo/SKILL.md"

echo "--- publish failure aborts, live intact ---"
mkdir -p "$FX/nomv"
printf '#!/bin/bash\nexit 1\n' > "$FX/nomv/mv"; chmod +x "$FX/nomv/mv"
if PATH="$FX/nomv:$PATH" ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i4.txt" 2>&1; then
  echo "FAIL: install succeeded despite failing mv"; fail=1
else
  echo "PASS: install failed as expected"
  check "live intact after abort" "[ -s \"$DEST/SKILL.md\" ] && cmp -s \"$DEST/SKILL.md\" \"$FX/live-skill.bak\""
  check "no half-installed stage" "[ -z \"\$(ls -d \"$DEST\".new.* 2>/dev/null || true)\" ]"
fi

echo "--- promote failure rolls back to previous skill ---"
mkdir -p "$FX/partialmv"
cat > "$FX/partialmv/mv" <<'EOF'
#!/bin/bash
for a in "$@"; do case "$a" in *.new.*) exit 1;; esac; done
if [ -x /bin/mv ]; then exec /bin/mv "$@"; else exec /usr/bin/mv "$@"; fi
EOF
chmod +x "$FX/partialmv/mv"
if PATH="$FX/partialmv:$PATH" ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i5.txt" 2>&1; then
  echo "FAIL: install succeeded despite failing promote"; fail=1
else
  echo "PASS: install failed as expected"
  check "rollback restored live skill" "[ -d \"$DEST\" ] && cmp -s \"$DEST/SKILL.md\" \"$FX/live-skill.bak\""
fi

echo "--- two installs in the same second keep both backups ---"
# `date +%Y%m%d%H%M%S` has one-second granularity, so two upgrades inside the
# same second computed the SAME backup name and the unconditional
# `rm -rf "$BACKUP"` destroyed the only good copy. Pin `date` so the collision
# is deterministic instead of a race, and assert neither backup was clobbered.
mkdir -p "$FX/fakedate"
cat > "$FX/fakedate/date" <<'EOF'
#!/bin/bash
# ignore the format and always return the same frozen timestamp
echo 20200101000000
EOF
chmod +x "$FX/fakedate/date"
mark_backup() { echo "MARKER-$1" >> "$DEST/SKILL.md"; }
mark_backup one
PATH="$FX/fakedate:$PATH" ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i6.txt" 2>&1
check "first upgrade succeeded" "[ -d \"$DEST\" ]"
mark_backup two
PATH="$FX/fakedate:$PATH" ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i7.txt" 2>&1
check "second upgrade succeeded" "[ -d \"$DEST\" ]"
BACKUPS=$(ls -d "$DEST".bak.* 2>/dev/null | wc -l | tr -d ' ')
check "two distinct backups survive a same-second reinstall" "[ \"$BACKUPS\" -ge 2 ]"
if [ "$BACKUPS" -ge 2 ] 2>/dev/null; then
  kept=0
  for b in "$DEST".bak.*; do
    grep -q 'MARKER-' "$b/SKILL.md" 2>/dev/null && kept=$((kept + 1))
  done
  check "each backup still holds its own content" "[ $kept -ge 2 ]"
fi

echo "--- rollback failure is reported honestly ---"
# The old code ran `mv "$BACKUP" "$SKILL_DIR" || true` and then printed
# "previous version restored" unconditionally, so a failed rollback left the
# user with NO installed skill while the message claimed otherwise.
mkdir -p "$FX/deadmv"
cat > "$FX/deadmv/mv" <<'EOF'
#!/bin/bash
# Fail the promote (STAGE -> live) and the rollback (BACKUP -> live), but
# ALLOW the backup step (live -> BACKUP). Distinguish by argument position:
# in `mv "$SKILL_DIR" "$BACKUP"` only the SECOND arg matches *.bak.*, while in
# `mv "$BACKUP" "$SKILL_DIR"` the FIRST one does.
n=0
for a in "$@"; do
  n=$((n + 1))
  case "$a" in
    *.new.*) exit 1 ;;
  esac
  if [ "$n" -eq 1 ]; then
    case "$a" in
      *.bak.*) exit 1 ;;
    esac
  fi
done
if [ -x /bin/mv ]; then exec /bin/mv "$@"; else exec /usr/bin/mv "$@"; fi
EOF
chmod +x "$FX/deadmv/mv"
cp "$DEST/SKILL.md" "$FX/pre-deadmv.bak" 2>/dev/null || true
if PATH="$FX/deadmv:$PATH" ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i8.txt" 2>&1; then
  echo "FAIL: install succeeded despite failing promote"; fail=1
else
  echo "PASS: install failed as expected"
  check "does not falsely claim rollback succeeded" "! grep -q 'previous version restored' \"$FX/i8.txt\""
  check "says the rollback also failed" "grep -qi 'rollback also failed' \"$FX/i8.txt\""
  check "names the recoverable backup" "grep -q 'still at:' \"$FX/i8.txt\""
  check "previous version still recoverable on disk" "[ -n \"\$(ls -d \"$DEST\".bak.* 2>/dev/null | head -n 1)\" ]"
fi
# Put a working skill back so the exit trap's tree is coherent.
rm -rf "$DEST"; mkdir -p "$DEST"
ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i9.txt" 2>&1 || true

if [ "$fail" -eq 0 ]; then echo "INSTALL TESTS ALL PASS"; else echo "INSTALL TESTS FAILED"; fi
exit $fail
