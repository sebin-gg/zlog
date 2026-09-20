#!/bin/bash
# zlog installer — installs AI skill
# Supports: Antigravity, Gemini CLI, Cursor, Claude Code, Codex, Windsurf, Ollama, Aider, LM Studio
set -e

ZLOG_REF="${ZLOG_REF:-main}"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT
REPO_RAW="https://raw.githubusercontent.com/sebin-gg/zlog/${ZLOG_REF}"
SKILL_FILES="SKILL.md scripts/zlog.sh scripts/zlog.ps1 references/agent-paths.md references/safety.md references/formats.md"

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

echo "Downloading zlog skill (ref: ${ZLOG_REF:-main})..."
download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_RAW/$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$REPO_RAW/$1"
  else
    echo "Error: curl or wget required to download the skill" >&2
    exit 1
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR" "$TMP_FILE"' EXIT
for f in $SKILL_FILES; do
  mkdir -p "$TMP_DIR/$(dirname "$f")"
  download "$f" "$TMP_DIR/$f"
done

# Verify download is a valid skill (frontmatter present)
if ! head -1 "$TMP_DIR/SKILL.md" | grep -q "^---$"; then
  echo "Error: Downloaded SKILL.md is not valid (missing frontmatter)" >&2
  exit 1
fi
if [ ! -s "$TMP_DIR/scripts/zlog.sh" ] || [ ! -s "$TMP_DIR/scripts/zlog.ps1" ]; then
  echo "Error: Downloaded scripts are empty" >&2
  exit 1
fi

for SKILL_DIR in "${SKILL_DIRS[@]}"; do
  mkdir -p "$SKILL_DIR"
  if [ -f "$SKILL_DIR/SKILL.md" ]; then
    cp "$SKILL_DIR/SKILL.md" "$SKILL_DIR/SKILL.md.bak"
  fi
  for f in $SKILL_FILES; do
    mkdir -p "$SKILL_DIR/$(dirname "$f")"
    cp "$TMP_DIR/$f" "$SKILL_DIR/$f"
  done
  chmod +x "$SKILL_DIR/scripts/zlog.sh" 2>/dev/null || true
  echo "✓ installed to $SKILL_DIR/ (SKILL.md + scripts/ + references/)"
done
rm -rf "$TMP_DIR" "$TMP_FILE"
echo "Trigger in chat with: 'zlog', 'compress logs', 'clean up chat logs', 'pack logs', 'preview zlog', 'dry run', 'find new AI agents', or 'scan disk for hidden AI logs'."
