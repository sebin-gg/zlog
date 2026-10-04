#!/bin/bash
# zlog installer — installs AI skill
# Supports: Antigravity, Gemini CLI, Cursor, Claude Code, Codex, Windsurf, Ollama, Aider, LM Studio
set -e

ZLOG_REF="${ZLOG_REF:-main}"
# ZLOG_REPO_RAW override exists for integration tests (file:// URL); users
# should keep the default pinned GitHub raw host.
REPO_RAW="${ZLOG_REPO_RAW:-https://raw.githubusercontent.com/sebin-gg/zlog/${ZLOG_REF}}"
# An array, not a space-joined string. `for f in $SKILL_FILES` relies on word
# splitting, so any future entry containing a space or a glob character would
# silently split into bogus paths and corrupt the install.
SKILL_FILES=(
  SKILL.md
  scripts/zlog.sh
  scripts/zlog.ps1
  references/agent-paths.md
  references/safety.md
  references/formats.md
)

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
trap 'rm -rf "$TMP_DIR"' EXIT
for f in "${SKILL_FILES[@]}"; do
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
  for f in "${SKILL_FILES[@]}"; do
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
    # Allocate a backup path that cannot be raced, and never delete an existing
    # backup to make room. `date +%S` alone collides between two installs in the
    # same second, and $$ does not fix that either: separate PID namespaces
    # sharing a home directory can reuse a PID within the same second.
    #
    # `mktemp -d` reserves the container ATOMICALLY, so nobody else can own that
    # name. The container is then kept — not released — and the skill is moved in
    # as a named child of it. That matters: if we rmdir'd the container first,
    # anything creating that path in the gap would make `mv` place the skill
    # *inside* it, leaving the installer reporting a backup that is not one and
    # a rollback that restores from the wrong place. Because the container is
    # empty and ours, "$CONTAINER/zlog" cannot pre-exist, so mv cannot nest.
    CONTAINER="$(mktemp -d "$SKILL_DIR.bak.XXXXXXXXXX" 2>/dev/null || true)"
    if [ -z "$CONTAINER" ] || [ ! -d "$CONTAINER" ]; then
      rm -rf "$STAGE"
      echo "Error: cannot allocate a backup directory for $SKILL_DIR" >&2
      exit 1
    fi
    BACKUP="$CONTAINER/$(basename "$SKILL_DIR")"
    if [ -e "$BACKUP" ] || [ -L "$BACKUP" ]; then
      rm -rf "$STAGE"
      echo "Error: backup destination $BACKUP is unexpectedly occupied" >&2
      exit 1
    fi
    mv "$SKILL_DIR" "$BACKUP" || { rm -rf "$STAGE"; echo "Error: cannot back up $SKILL_DIR" >&2; exit 1; }
    if mv "$STAGE" "$SKILL_DIR"; then
      echo "✓ installed to $SKILL_DIR/ (previous skill backed up to $BACKUP/)"
    else
      rm -rf "$STAGE"
      # Only claim the rollback worked if it actually did. The old
      # `... || true` printed "previous version restored" unconditionally, so a
      # failed restore left the user with NO installed skill while the message
      # said otherwise. On failure, name the backup so it is recoverable.
      #
      # Never move INTO an occupied destination: if another installer created
      # $SKILL_DIR in the gap, plain `mv "$BACKUP" "$SKILL_DIR"` would succeed
      # by nesting the backup as $SKILL_DIR/<basename> and still exit 0, so a
      # bare status check would claim a restore that never happened. Refuse the
      # move when the destination is occupied and report the backup path.
      #
      # Fingerprint the backup directory BEFORE the move, so a same-named child
      # found afterward can be told apart from our own backup. The previous
      # installation may legitimately contain a top-level child also named
      # `zlog` (this installer never creates one, but a user can); device+inode
      # says whether that child IS the moved backup — nested by a concurrent
      # occupant winning the residual race between the check and the mv — or
      # just rode along inside it. Same portable `stat` fallback zlog.sh uses
      # (GNU -c, BSD -f).
      BACKUP_ID="$(stat -c '%d %i' "$BACKUP" 2>/dev/null || stat -f '%d %i' "$BACKUP" 2>/dev/null || true)"
      if [ -e "$SKILL_DIR" ] || [ -L "$SKILL_DIR" ]; then
        echo "Error: install to $SKILL_DIR failed AND the rollback was skipped:" >&2
        echo "       $SKILL_DIR is now occupied (possibly by another installer)," >&2
        echo "       so moving the backup there would nest it instead of restoring it." >&2
        echo "       The previous version is still at: $BACKUP" >&2
      elif mv "$BACKUP" "$SKILL_DIR" 2>/dev/null \
        && [ -d "$SKILL_DIR" ] \
        && [ ! -e "$BACKUP" ] && [ ! -L "$BACKUP" ]; then
        NESTED="$SKILL_DIR/$(basename "$SKILL_DIR")"
        NESTED_ID="$(stat -c '%d %i' "$NESTED" 2>/dev/null || stat -f '%d %i' "$NESTED" 2>/dev/null || true)"
        if { [ -e "$NESTED" ] || [ -L "$NESTED" ]; } \
          && [ -n "$BACKUP_ID" ] && [ "$NESTED_ID" = "$BACKUP_ID" ]; then
          echo "Error: install to $SKILL_DIR failed AND the rollback nested the backup" >&2
          echo "       inside the occupying directory instead of restoring it." >&2
          echo "       The previous version is still at: $NESTED" >&2
        else
          echo "Error: install to $SKILL_DIR failed, previous version restored" >&2
          if [ -e "$NESTED" ] || [ -L "$NESTED" ]; then
            echo "       Note: $NESTED pre-existed inside the previous installation" >&2
            echo "       and was restored with it; it is not rollback debris." >&2
          fi
        fi
      else
        if [ -e "$BACKUP" ] || [ -L "$BACKUP" ]; then
          echo "Error: install to $SKILL_DIR failed AND the rollback also failed." >&2
          echo "       The previous version is still at: $BACKUP" >&2
          echo "       Restore it manually with:" >&2
          echo "         mv \"$BACKUP\" \"$SKILL_DIR\"" >&2
        else
          echo "Error: install to $SKILL_DIR failed and the backup is no longer at $BACKUP;" >&2
          echo "       inspect $SKILL_DIR before retrying." >&2
        fi
      fi
      exit 1
    fi
  else
    mkdir -p "$(dirname "$SKILL_DIR")"
    mv "$STAGE" "$SKILL_DIR" || { rm -rf "$STAGE"; echo "Error: install to $SKILL_DIR failed" >&2; exit 1; }
    echo "✓ installed to $SKILL_DIR/ (SKILL.md + scripts/ + references/)"
  fi
done
rm -rf "$TMP_DIR"
echo "Trigger in chat with: 'zlog', 'compress logs', 'clean up chat logs', 'pack logs', 'preview zlog', 'dry run', 'find new AI agents', or 'scan disk for hidden AI logs'."
