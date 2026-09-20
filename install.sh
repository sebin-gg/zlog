#!/bin/bash
# zlog installer — installs AI skill + terminal CLI
# Supports: Antigravity, Gemini CLI, Cursor, Claude Code, Codex, Windsurf, Ollama, Aider, LM Studio
set -e

REPO_RAW="https://raw.githubusercontent.com/sebin-gg/zlog/main"
SKILL_SRC="$REPO_RAW/SKILL.md"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/zlog"

# Skill dirs: primary (agentskills.io spec) + common agent-specific locations if their parent exists or always create primary
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

echo "==> zlog installer"
echo ""

# --- 1. Install SKILL.md ---
for d in "${SKILL_DIRS[@]}"; do
  mkdir -p "$d"
  echo "Downloading SKILL.md -> $d/SKILL.md ..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SKILL_SRC" -o "$d/SKILL.md"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$d/SKILL.md" "$SKILL_SRC"
  else
    echo "Error: curl or wget required to download SKILL.md" >&2
    exit 1
  fi
done
echo "✓ Skill installed to ${SKILL_DIRS[0]}/SKILL.md"

# --- 2. Install CLI to ~/.local/bin/zlog ---
mkdir -p "$BIN_DIR"
echo "Installing CLI -> $BIN_PATH ..."

cat > "$BIN_PATH" <<'ZLOG_CLI_EOF'
#!/bin/bash
# zlog CLI — Multi-Agent Session Log Storage Optimizer
# Usage: zlog [--dry-run] [--deep] [--help]
set -e

DIRS=(~/.claude ~/.config/claude-code ~/.config/Cursor ~/.cursor ~/.gemini ~/.ollama ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.aider)

usage() {
  cat <<'USAGE'
zlog — compress AI agent session logs

Usage:
  zlog                Compress logs in known agent dirs (standard mode)
  zlog --dry-run      Preview what would be compressed (no changes)
  zlog --deep         Deep scan ~ (maxdepth 12, pruned) for agent logs
  zlog --help         Show this help

What it does:
  - Purges empty 0-byte *.log/*.out/*.trace
  - Skips files <10KiB, <60s old, or currently locked (fuser/lsof)
  - Never descends into node_modules, Caches, GPUCache, .git, etc.
  - Compresses with zstd -15 (fallback xz -9, gzip) and verifies output
  - Reports: "[zlog] Compressed N files: X -> Y (saved Z, P% smaller)"
  - Excludes *.jsonl, SKILL.md, README*, LICENSE*; *.txt NOT included by default

Requires: bash, find, stat, tar/gzip; optional: zstd, xz, fuser, lsof, numfmt
USAGE
}

MODE="standard"
for arg in "$@"; do
  case "$arg" in
    --dry-run|--dry_run|-n) MODE="dry-run" ;;
    --deep|--deep-scan) MODE="deep" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $arg (try --help)" >&2; exit 1 ;;
  esac
done

compress_one() {
  local f="$1" size="$2"
  local locked=0
  if command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null; then locked=1; fi
  if [ "$locked" -eq 0 ] && command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1; then locked=1; fi
  if [ "$locked" -eq 1 ]; then return 2; fi
  if command -v zstd >/dev/null 2>&1; then zstd -15 -q --rm "$f" 2>/dev/null
  elif command -v xz >/dev/null 2>&1; then xz -9 "$f" 2>/dev/null
  else gzip -f "$f" 2>/dev/null
  fi
  for c in zst xz gz; do
    [ -f "$f.$c" ] || continue
    local newsize
    newsize=$(stat -c%s "$f.$c" 2>/dev/null || stat -f%z "$f.$c" 2>/dev/null) || newsize=0
    if [ "$newsize" -eq 0 ]; then rm -f "$f.$c" 2>/dev/null; continue; fi
    echo "$newsize"
    return 0
  done
  return 1
}

run_standard() {
  local raw=0 saved=0 count=0
  for d in "${DIRS[@]}"; do
    expanded=$(eval echo "$d")
    [ -d "$expanded" ] || continue
    find -L "$expanded" \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -empty -type f -delete 2>/dev/null || true
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      local size newsize rc
      size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
      newsize=$(compress_one "$f" "$size"); rc=$?
      if [ "$rc" -eq 2 ]; then continue; fi
      if [ "$rc" -eq 0 ]; then
        raw=$((raw + size)); saved=$((saved + size - newsize)); count=$((count + 1))
      fi
    done < <(find -L "$expanded" \( -type d \( -name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 \) -print 2>/dev/null)
  done
  if [ "$count" -gt 0 ]; then
    local comp=$((raw - saved))
    local raw_h comp_h saved_h
    raw_h=$(numfmt --to=iec "$raw" 2>/dev/null || echo "${raw}B")
    comp_h=$(numfmt --to=iec "$comp" 2>/dev/null || echo "${comp}B")
    saved_h=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
    echo "[zlog] Compressed $count files: $raw_h -> $comp_h (saved $saved_h, $(( saved * 100 / raw ))% smaller)"
  else
    echo "[zlog] No files to compress."
  fi
  local dirs=(); for d in "${DIRS[@]}"; do expanded=$(eval echo "$d"); [ -d "$expanded" ] && [ ! -L "$expanded" ] && dirs+=("$expanded"); done
  [ ${#dirs[@]} -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
}

run_dry_run() {
  local total=0 count=0
  for d in "${DIRS[@]}"; do
    expanded=$(eval echo "$d")
    [ -d "$expanded" ] || continue
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      local size hum
      size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
      total=$((total + size)); count=$((count + 1))
      hum=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")
      echo "[DRY-RUN] Would compress: $f ($hum)"
    done < <(find -L "$expanded" \( -type d \( -name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 \) -print 2>/dev/null)
  done
  local saved comp
  saved=$((total * 77 / 100))
  comp=$((total - saved))
  local total_hum comp_hum
  total_hum=$(numfmt --to=iec "$total" 2>/dev/null || echo "${total}B")
  comp_hum=$(numfmt --to=iec "$comp" 2>/dev/null || echo "${comp}B")
  echo ""
  echo "[DRY-RUN] Total: $count files, $total_hum raw -> ~$comp_hum compressed (est. ~77% savings, 4-5x; varies by log entropy)"
}

run_deep() {
  local pruned raw saved count
  pruned=$(find -L ~ -maxdepth 12 \( -type d \( -name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git \) -prune \) -print 2>/dev/null | wc -l)
  raw=0; saved=0; count=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local size newsize rc
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    newsize=$(compress_one "$f" "$size"); rc=$?
    if [ "$rc" -eq 2 ]; then continue; fi
    if [ "$rc" -eq 0 ]; then
      raw=$((raw + size)); saved=$((saved + size - newsize)); count=$((count + 1))
    fi
  done < <(find -L ~ -maxdepth 12 \( -type d \( -name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git \) -prune \) -o \( -path "*/.claude/*" -o -path "*/.config/claude-code/*" -o -path "*/.gemini/*" -o -path "*/.config/Cursor/*" -o -path "*/.cursor/*" -o -path "*/.ollama/*" -o -path "*/.windsurf/*" -o -path "*/.codex/*" -o -path "*/.cache/lm-studio/*" -o -path "*/.lm-studio/*" -o -path "*/.aider/*" \) -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print 2>/dev/null)
  if [ "$count" -gt 0 ]; then
    local comp=$((raw - saved))
    local raw_h comp_h saved_h
    raw_h=$(numfmt --to=iec "$raw" 2>/dev/null || echo "${raw}B")
    comp_h=$(numfmt --to=iec "$comp" 2>/dev/null || echo "${comp}B")
    saved_h=$(numfmt --to=iec "$saved" 2>/dev/null || echo "${saved}B")
    echo "[zlog] Deep scan compressed $count files: $raw_h -> $comp_h (saved $saved_h, $(( saved * 100 / raw ))% smaller)"
  fi
  echo "[zlog] Deep scan pruned $pruned junk/cache dirs (maxdepth 12)"
}

case "$MODE" in
  standard) run_standard ;;
  dry-run) run_dry_run ;;
  deep) run_deep ;;
esac
ZLOG_CLI_EOF

chmod +x "$BIN_PATH"
echo "✓ CLI installed to $BIN_PATH"

# --- 3. PATH check ---
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  echo "NOTE: $BIN_DIR is not on your PATH."
  echo "  Add it with:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
  echo "  (or ~/.zshrc for Zsh)"
else
  echo "✓ $BIN_DIR is on PATH"
fi

echo ""
echo "Done! Usage:"
echo "  zlog              # compress logs"
echo "  zlog --dry-run    # preview"
echo "  zlog --deep       # deep scan"
echo "  zlog --help       # help"
echo ""
echo "Or trigger via AI chat: 'zlog', 'compress logs', 'clean chat logs'"
for d in "${SKILL_DIRS[@]}"; do echo "  Skill: $d/SKILL.md"; done
