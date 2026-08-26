#!/bin/bash
# zlog skill installer for Antigravity, Gemini CLI, Cursor, Claude Code, and Global Agents
set -e

SKILL_DIR="$HOME/.agents/skills/zlog"
mkdir -p "$SKILL_DIR"

echo "Downloading latest zlog SKILL.md..."
curl -fsSL https://raw.githubusercontent.com/sebin-gg/zlog/main/SKILL.md -o "$SKILL_DIR/SKILL.md"

echo "✓ zlog installed successfully to $SKILL_DIR/SKILL.md!"
echo "Trigger in chat with: 'zlog', 'compress logs', or 'clean chat logs'."
