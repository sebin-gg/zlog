#!/bin/bash
# zlog skill installer for Antigravity, Gemini CLI, Cursor, Claude Code, and Global Agents
set -e

TARGETS="$HOME/.agents/skills/zlog $HOME/.claude/skills/zlog $HOME/.gemini/skills/zlog"
ZLOG_REF="${ZLOG_REF:-main}"
TMP_FILE="$(mktemp)"

echo "Downloading zlog SKILL.md (ref: $ZLOG_REF)..."
curl -fsSL "https://raw.githubusercontent.com/sebin-gg/zlog/$ZLOG_REF/SKILL.md" -o "$TMP_FILE"

# Verify download is valid SKILL.md
if ! head -1 "$TMP_FILE" | grep -q "^---$"; then
  echo "Error: Downloaded file is not valid SKILL.md (missing frontmatter)"
  rm -f "$TMP_FILE"
  exit 1
fi

for SKILL_DIR in $TARGETS; do
  mkdir -p "$SKILL_DIR"
  if [ -f "$SKILL_DIR/SKILL.md" ]; then
    cp "$SKILL_DIR/SKILL.md" "$SKILL_DIR/SKILL.md.bak"
  fi
  cp "$TMP_FILE" "$SKILL_DIR/SKILL.md"
  echo "✓ installed to $SKILL_DIR/SKILL.md"
done
rm -f "$TMP_FILE"
echo "Trigger in chat with: 'zlog', 'compress logs', 'clean up chat logs', 'pack logs', 'preview zlog', 'dry run', 'find new AI agents', or 'scan disk for hidden AI logs'."
