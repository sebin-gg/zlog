#!/bin/bash
# zlog installer — installs AI skill
# Supports: Antigravity, Gemini CLI, Cursor, Claude Code, Codex, Windsurf, Ollama, Aider, LM Studio
set -e

ZLOG_REF="${ZLOG_REF:-main}"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT
# ZLOG_REPO_RAW override exists for integration tests (file:// URL); users
# should keep the default pinned GitHub raw host.
REPO_RAW="${ZLOG_REPO_RAW:-https://raw.githubusercontent.com/sebin-gg/zlog/${ZLOG_REF}}"
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
  # Atomic replacement: stage the complete skill, validate it, then
  # rename into place so a failure can never leave a mixed installation.
  STAGE="$SKILL_DIR.new.$$"
  rm -rf "$STAGE"
  for f in $SKILL_FILES; do
    mkdir -p "$STAGE/$(dirname "$f")"
    cp "$TMP_DIR/$f" "$STAGE/$f"
  done
  chmod +x "$STAGE/scripts/zlog.sh" 2>/dev/null || true
  if ! head -1 "$STAGE/SKILL.md" | grep -q "^---$"; then
    echo "Error: staged skill is not valid (missing frontmatter), aborting install to $SKILL_DIR" >&2
    rm -rf "$STAGE"
    exit 1
  fi
  if [ -d "$SKILL_DIR" ]; then
    BACKUP="$SKILL_DIR.bak.$(date +%Y%m%d%H%M%S)"
    rm -rf "$BACKUP"
    mv "$SKILL_DIR" "$BACKUP" || { rm -rf "$STAGE"; echo "Error: cannot back up $SKILL_DIR" >&2; exit 1; }
    if mv "$STAGE" "$SKILL_DIR"; then
      echo "✓ installed to $SKILL_DIR/ (previous skill backed up to $BACKUP/)"
    else
      mv "$BACKUP" "$SKILL_DIR" 2>/dev/null || true
      rm -rf "$STAGE"
      echo "Error: install to $SKILL_DIR failed, previous version restored" >&2
      exit 1
    fi
  else
    mkdir -p "$(dirname "$SKILL_DIR")"
    mv "$STAGE" "$SKILL_DIR" || { rm -rf "$STAGE"; echo "Error: install to $SKILL_DIR failed" >&2; exit 1; }
    echo "✓ installed to $SKILL_DIR/ (SKILL.md + scripts/ + references/)"
  fi
done
rm -rf "$TMP_DIR" "$TMP_FILE"
echo "Trigger in chat with: 'zlog', 'compress logs', 'clean up chat logs', 'pack logs', 'preview zlog', 'dry run', 'find new AI agents', or 'scan disk for hidden AI logs'."
