#!/bin/bash
# zlog skill installer for Antigravity, Gemini CLI, Cursor, Claude Code, and Global Agents
set -e

SKILL_DIR="$HOME/.agents/skills/zlog"
mkdir -p "$SKILL_DIR"

echo "Downloading latest zlog SKILL.md..."
curl -fsSL https://raw.githubusercontent.com/sebin-gg/zlog/main/SKILL.md -o "$SKILL_DIR/SKILL.md"

# Verify download is valid SKILL.md
if ! head -1 "$SKILL_DIR/SKILL.md" | grep -q "^---$"; then
  echo "Error: Downloaded file is not valid SKILL.md (missing frontmatter)"
  rm -f "$SKILL_DIR/SKILL.md"
  exit 1
fi

echo "✓ zlog installed successfully to $SKILL_DIR/SKILL.md!"
echo "Trigger in chat with: 'zlog', 'compress logs', or 'clean chat logs'."
