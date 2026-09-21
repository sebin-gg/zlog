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
SKILL_FILES="SKILL.md scripts/zlog.sh scripts/zlog.ps1 references/agent-paths.md references/safety.md references/formats.md"
for f in $SKILL_FILES; do
  mkdir -p "$FX/repo/$(dirname "$f")"
  cp "$REPO/$f" "$FX/repo/$f"
done

fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi }
DEST="$HOME/.agents/skills/zlog"

echo "--- fresh install ---"
ZLOG_REPO_RAW="file://$FX/repo" bash "$REPO/install.sh" > "$FX/i1.txt" \
  || { echo "FAIL: fresh install exited nonzero"; fail=1; }
for f in $SKILL_FILES; do
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

if [ "$fail" -eq 0 ]; then echo "INSTALL TESTS ALL PASS"; else echo "INSTALL TESTS FAILED"; fi
exit $fail
