#!/bin/bash
# zlog installer — installs AI skill
# Supports: Antigravity, Gemini CLI, Cursor, Claude Code, Codex, Windsurf, Ollama, Aider, LM Studio
set -e

ZLOG_REF="${ZLOG_REF:-main}"
TMP_FILE="$(mktemp)"
REPO_RAW="https://raw.githubusercontent.com/sebin-gg/zlog/${ZLOG_REF}"
SKILL_SRC="$REPO_RAW/SKILL.md"

# Skill dirs: primary (agentskills.io spec) + agent-specific locations if their parent exists
SKILL_DIRS=(
  "$HOME/.agents/skills/zlog"
)

# Also install to Claude/Gemini skills if those homes exist (non-fatal)
if [ -d "$HOME/.claude" ] || [ -d "$HOME/.config/claude-code" ]; then
  SKILL_DIRS+=("$HOME/.claude/skills/zlog")
fi
if [ -d "$HOME/.gemini" ]; then
  SKILL_DIRS+=("$HOME/.gemini/skills/zlog")
fi

echo "Downloading zlog SKILL.md (ref: ${ZLOG_REF:-main})..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$SKILL_SRC" -o "$TMP_FILE"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP_FILE" "$SKILL_SRC"
else
  echo "Error: curl or wget required to download SKILL.md" >&2
  exit 1
fi

# Verify download is valid SKILL.md
if ! head -1 "$TMP_FILE" | grep -q "^---$"; then
  echo "Error: Downloaded file is not valid SKILL.md (missing frontmatter)" >&2
  rm -f "$TMP_FILE"
  exit 1
fi

for SKILL_DIR in "${SKILL_DIRS[@]}"; do
  mkdir -p "$SKILL_DIR"
  if [ -f "$SKILL_DIR/SKILL.md" ]; then
    cp "$SKILL_DIR/SKILL.md" "$SKILL_DIR/SKILL.md.bak"
  fi
  cp "$TMP_FILE" "$SKILL_DIR/SKILL.md"
  echo "✓ installed to $SKILL_DIR/SKILL.md"
done
rm -f "$TMP_FILE"
echo "Trigger in chat with: 'zlog', 'compress logs', 'clean up chat logs', 'pack logs', 'preview zlog', 'dry run', 'find new AI agents', or 'scan disk for hidden AI logs'."
