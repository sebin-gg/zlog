# zlog — Multi-Agent Session Log Storage Optimizer

![zlog Social Card](https://raw.githubusercontent.com/sebin-gg/zlog/main/assets/zlog-social-card.png)

<p align="center">
  <a href="https://agentskills.io"><img src="https://img.shields.io/badge/spec-agentskills.io-blue" alt="Spec"></a>
  <a href="https://skills.sh"><img src="https://img.shields.io/badge/registry-skills.sh-purple" alt="Registry"></a>
  <a href="https://github.com/sebin-gg/zlog/actions"><img src="https://github.com/sebin-gg/zlog/actions/workflows/validate.yml/badge.svg" alt="Validate"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License"></a>
  <a href="#compatibility"><img src="https://img.shields.io/badge/compatibility-Linux%20tested-success" alt="Compatibility"></a>
  <a href="https://github.com/sebin-gg/zlog/stargazers"><img src="https://img.shields.io/github/stars/sebin-gg/zlog?style=social" alt="Stars"></a>
</p>

> **The zero-config log compressor for AI agent developers.** Compresses session logs across Cursor, Claude Code, Antigravity, Ollama & Windsurf while skipping conversation transcripts. Tested on Linux; macOS, WSL, and Windows 11 snippets ship untested.

---

## 🚀 Quick Install (1-Line)

### via `skills.sh` Package Manager
```bash
npx skills add sebin-gg/zlog
```

### via Shell Script
```bash
curl -fsSL https://raw.githubusercontent.com/sebin-gg/zlog/main/install.sh | bash
# CLI installed to ~/.local/bin/zlog — ensure ~/.local/bin is on your PATH
# Usage: zlog              # compress
#        zlog --dry-run    # preview
#        zlog --deep       # deep scan
# Skill installed to ~/.agents/skills/zlog/SKILL.md — trigger in chat with: 'zlog', 'compress logs', or 'clean chat logs'.
```

> **What gets installed?** `install.sh` does two things: (1) downloads `SKILL.md` to `~/.agents/skills/zlog/` (and `~/.claude/skills/` / `~/.gemini/skills/` if those dirs exist) so your AI agent can invoke `zlog` via chat, and (2) writes an executable `~/.local/bin/zlog` wrapper for direct terminal use. If you only want the skill, the `npx skills add` path is sufficient. For terminal-only use, copy the one-line snippets below.

---

## ⚡ Key Highlights

- **High-Ratio Compression**: Tries `zstd -15`, falls back to `xz -9` / `gzip`. Reports per-run savings with a single summary line.
- **0-Byte Log Purging**: Cleans dead empty files automatically.
- **Process Lock Checks**: Checks kernel locks via `fuser -s` (Linux/WSL), `lsof` (macOS), or `[System.IO.File]::Open` (Windows 11). Files with active locks are skipped; the macOS/Windows paths are not runtime-tested.
- **One Canonical Prune List**: Every POSIX snippet defines the junk-dir prune once as a `prune` array (`node_modules`, `Caches`, `Cache`, `Code Cache`, `blob_storage`, `GPUCache`, `DawnGraphiteCache`, `DawnWebGPUCache`, `.git`) and reuses it everywhere — standard scan, deep scan, and purge never diverge.
- **Memory Context Intact**: Excludes `transcript.jsonl` files by filter.
- **Single-Line Output**: Condenses multi-folder scan results into one clean line.
- **Linux Tested**: Runs on Linux (Bash, Zsh). macOS, WSL, and Windows 11 PowerShell snippets ship untested.
- **Junk-Pruned Hybrid Deep Scan**: Skips `Caches`/`node_modules`/GPU-cache junk via prune; capped at depth 12 to bound the walk.
- **Windows 11 PowerShell Note**: The PowerShell variant recurses unpruned (no `-prune` equivalent) but filters out any file whose path contains a junk-dir segment (`\node_modules\`, `\Caches\`, `\Cache\`, `\Code Cache\`, `\blob_storage\`, `\GPUCache\`, `\DawnGraphiteCache\`, `\DawnWebGPUCache\`, `\.git\`) — matching the POSIX prune list; the find-based scans on Linux/macOS/WSL skip those dirs wholesale. It purges 0-byte logs first, then reports the same single-line summary.

---

## 📊 Storage Savings

Savings depend on log content (repetitive text compresses best). Run the Dry-Run preview for your own numbers — the skill reports per-run raw → compressed totals.

---

## 🏗️ How It Works

```mermaid
graph TD
    A["Wrap-up Prompt / Trigger"] --> B{"Scan AI Agent Paths"}
    B --> C["~/.claude, ~/.config/Cursor, ~/.gemini, ~/.ollama, ~/.aider etc."]
    C --> D{"Process Lock Check"}
    D -- "fuser / lsof / System.IO detects active PID" --> E["Skip File - In-Flight Safety"]
    D -- "No active process lock (or tools unavailable → age check)" --> F{"File & Window Filters"}
    F -- "*.jsonl / SKILL.md / README* / <10KB / <60s old" --> G["Skip File - Protected"]
    F -- "*.log / *.out / *.trace" --> H["zstd -15 / xz -9 / gzip -f (+ verify)"]
    H --> I["Report Savings + Total (e.g. Compressed 15 files: 34M -> 8M)"]
```

---

## 🌐 Supported AI Agent Runtimes

| # | AI Agent / IDE | Default Log Directory | Tested |
| :---: | :--- | :--- | :--- |
| 1 | **Antigravity CLI** | `~/.gemini/antigravity-cli/logs/` | Linux |
| 2 | **Gemini CLI** | `~/.gemini/` | Linux |
| 3 | **Cursor IDE** | `~/.config/Cursor/` · `~/Library/Application Support/Cursor/` (macOS) · `%APPDATA%\Cursor\` (Windows) | Linux |
| 4 | **Cursor (Legacy)** | `~/.cursor/` | Linux |
| 5 | **Claude Code** | `~/.claude/` | Linux |
| 6 | **Claude Code Config** | `~/.config/claude-code/` | Linux |
| 7 | **Ollama** | `~/.ollama/` · `%LOCALAPPDATA%\Ollama\` (Windows app/server logs) | Linux |
| 8 | **Windsurf** | `~/.windsurf/` · `~/.config/Windsurf/` (Linux) · `~/Library/Application Support/Windsurf/` (macOS) · `%APPDATA%\Windsurf\` (Windows) | Linux |
| 9 | **Codex CLI** | `~/.codex/` | Linux |
| 10 | **LM Studio** | `~/.cache/lm-studio/` (older layout) | Linux |
| 11 | **LM Studio** | `~/.lm-studio/` (current layout) | Linux |

> Note: paths verified against vendor docs; only Linux is runtime-tested. macOS, WSL, and Windows 11 snippets ship untested.

> Note: both LM Studio layouts (`~/.cache/lm-studio` and `~/.lm-studio`) are scanned on all platforms including the Windows 11 PowerShell path list.

---

## 💻 One-Line Command Snippets

### POSIX Shell (tested on Linux)

```bash
raw=0; saved=0; count=0
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
for d in ~/.gemini ~/.config/Cursor "$HOME/Library/Application Support/Cursor" ~/.cursor ~/.ollama "$HOME/AppData/Local/Ollama" ~/.claude ~/.config/claude-code ~/.windsurf ~/.config/Windsurf "$HOME/Library/Application Support/Windsurf" ~/.codex ~/.cache/lm-studio ~/.lm-studio; do
  [ -d "$d" ] || continue
  find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -empty -exec rm -f {} + \) 2>/dev/null || true
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    locked=0
    if command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null; then locked=1; fi
    if [ "$locked" -eq 0 ] && command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1; then locked=1; fi
    if [ "$locked" -eq 1 ]; then continue; fi
    if command -v zstd >/dev/null 2>&1; then zstd -15 -q --rm "$f" 2>/dev/null
    elif command -v xz >/dev/null 2>&1; then xz -9 "$f" 2>/dev/null
    else gzip -f "$f" 2>/dev/null
    fi
    for c in zst xz gz; do
      [ -f "$f.$c" ] || continue
      newsize=$(stat -c%s "$f.$c" 2>/dev/null || stat -f%z "$f.$c" 2>/dev/null) || newsize=0
      if [ "$newsize" -eq 0 ]; then rm -f "$f.$c" 2>/dev/null; continue; fi
      raw=$((raw + size)); saved=$((saved + size - newsize)); count=$((count + 1))
      break
    done
  done < <(find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 \) 2>/dev/null)
done
if [ "$count" -gt 0 ]; then
  comp=$((raw - saved))
  raw_h=$(echo "$raw" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  comp_h=$(echo "$comp" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  saved_h=$(echo "$saved" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  pct=0; [ "$raw" -gt 0 ] && pct=$(( saved * 100 / raw ))
  echo "[zlog] Compressed $count files: $raw_h -> $comp_h (saved $saved_h, $pct% smaller)"
fi
dirs=(); for d in ~/.gemini ~/.config/Cursor "$HOME/Library/Application Support/Cursor" ~/.cursor ~/.ollama "$HOME/AppData/Local/Ollama" ~/.claude ~/.config/claude-code ~/.windsurf ~/.config/Windsurf "$HOME/Library/Application Support/Windsurf" ~/.codex ~/.cache/lm-studio ~/.lm-studio; do [ -d "$d" ] && [ ! -L "$d" ] && dirs+=("$d"); done; [ ${#dirs[@]} -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
```

### Windows 11 PowerShell (not runtime-tested)

```powershell
$zlogPaths = "$env:USERPROFILE\.gemini","$env:APPDATA\Cursor","$env:USERPROFILE\.config\Cursor","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:LOCALAPPDATA\Ollama","$env:USERPROFILE\.claude","$env:USERPROFILE\.config\claude-code","$env:USERPROFILE\.windsurf","$env:APPDATA\Windsurf","$env:USERPROFILE\.config\Windsurf","$env:USERPROFILE\.codex","$env:USERPROFILE\.cache\lm-studio","$env:USERPROFILE\.lm-studio"
$junk = '\node_modules\','\Caches\','\Cache\','\Code Cache\','\blob_storage\','\GPUCache\','\DawnGraphiteCache\','\DawnWebGPUCache\','\.git\'
function zlogFmt($b) { if ($b -ge 1073741824) { "{0:N1}G" -f ($b/1073741824) } elseif ($b -ge 1048576) { "{0:N1}M" -f ($b/1048576) } elseif ($b -ge 1024) { "{0:N1}K" -f ($b/1024) } else { "${b}B" } }
Get-ChildItem -Path $zlogPaths -Recurse -Include *.log,*.out,*.txt,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $p = $_.FullName; $_.Length -eq 0 -and -not ($junk | Where-Object { $p -like "*$_*" }) } | Remove-Item -Force -ErrorAction SilentlyContinue
$count=0; $raw=0; $saved=0
Get-ChildItem -Path $zlogPaths -Recurse -Include *.log,*.out,*.txt,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $p = $_.FullName; $_.Length -gt 10KB -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) -and -not ($junk | Where-Object { $p -like "*$_*" }) -and (try { $s = [System.IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $s.Close(); $true } catch { $false }) } | ForEach-Object { $size=$_.Length; tar.exe -czf "$($_.FullName).tar.gz" -C $_.DirectoryName $_.Name; if ($LASTEXITCODE -eq 0 -and (Test-Path "$($_.FullName).tar.gz")) { $new=(Get-Item "$($_.FullName).tar.gz").Length; $raw+=$size; $saved+=($size-$new); $count++; Remove-Item $_.FullName } }
if ($count -gt 0) { $comp=$raw-$saved; $pct=0; if ($raw -gt 0) { $pct=[math]::Floor($saved*100/$raw) }; echo "[zlog] Compressed $count files: $(zlogFmt $raw) -> $(zlogFmt $comp) (saved $(zlogFmt $saved), $pct% smaller)" }
```

---

> Note: the Windows PowerShell scan recurses unpruned (PowerShell has no `-prune`) but applies the same junk-dir path-segment filter as the POSIX prune list; the find-based scans skip those dirs wholesale. It purges 0-byte logs first, then reports the same single-line summary. Neither variant is runtime-tested on Windows.

---

## 🎬 Demo

### Live Terminal Recording

```bash
# Record your own demo with asciinema (recommended)
asciinema rec zlog-demo.cast
# ... run: zlog / curl install / npx skills add ...
# Ctrl+D to stop
asciinema upload zlog-demo.cast
```

### Example Output (illustrative — exact numbers vary by machine)

```
[zlog] Compressed 23 files: 847M -> 12M (saved 835M, 98% smaller)
1.2G    total
```

The output is a single summary line: file count, raw → compressed, savings percentage, and total directory size.

### Record & Share

1. **Install asciinema**: `pipx install asciinema` / `brew install asciinema` / `choco install asciinema`
2. **Record**: `asciinema rec zlog-demo.cast`
3. **Run zlog**: trigger via your agent or run the one-liner
4. **Upload**: `asciinema upload zlog-demo.cast`
5. **Embed**: Paste the URL in issues, discussions, or social posts

---

## ❓ FAQ

- **Does `zlog` break chat history?**  
  **No.** `transcript.jsonl` files are strictly excluded by filter.

- **What if an AI agent is actively writing to a log file?**  
  Kernel lock checks (`fuser -s` / `lsof` / `System.IO.File`) & 60s age buffer (`-mmin +1`) skip active files. Lock checks require `fuser` (Linux/WSL) or `lsof` (macOS); without either only the age buffer protects. Behavior against live agents is not runtime-tested.

- **How do I read or search compressed `.zst` / `.gz` logs?**  
  - Read: `zstdcat file.log.zst` or `zcat file.log.gz`
  - Read Windows `.tar.gz`: `tar -xzf file.log.tar.gz`
  - Search: `zstdgrep "error" file.log.zst` or `zgrep "error" file.log.gz`

- **Is `zlog` safe to run during multi-agent sessions?**  
  It is designed to be: process-lock checks and age filters skip files that are in use. Not runtime-tested against live agents.

- **How does the deep scan stay bounded?**  
  Hybrid pruning + depth cap: junk/cache dirs (`node_modules`, `Caches`, `Code Cache`, `blob_storage`, `GPUCache`, `.git`, …) are pruned wholesale, while `-maxdepth 12` bounds the walk. The pruned-dir count is reported.

---

## 🌟 Support Open Source

If `zlog` saved space on your drive, consider giving it a **⭐ Star** on [GitHub](https://github.com/sebin-gg/zlog)!

---

## 📄 License

[MIT](LICENSE) © 2026 Sebin Mathew
