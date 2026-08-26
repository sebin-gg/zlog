# zlog — Multi-Agent Session Log Storage Optimizer

![zlog Social Card](https://raw.githubusercontent.com/sebin-gg/zlog/main/assets/zlog-social-card.png)

<p align="center">
  <a href="https://agentskills.io"><img src="https://img.shields.io/badge/spec-agentskills.io-blue" alt="Spec"></a>
  <a href="https://skills.sh"><img src="https://img.shields.io/badge/registry-skills.sh-purple" alt="Registry"></a>
  <a href="https://github.com/sebin-gg/zlog/actions"><img src="https://github.com/sebin-gg/zlog/actions/workflows/validate.yml/badge.svg" alt="Validate"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License"></a>
  <a href="#compatibility"><img src="https://img.shields.io/badge/compatibility-Linux%20%7C%20macOS%20%7C%20Windows%2011-success" alt="Compatibility"></a>
  <a href="https://github.com/sebin-gg/zlog/stargazers"><img src="https://img.shields.io/github/stars/sebin-gg/zlog?style=social" alt="Stars"></a>
</p>

Compress background tool logs across core AI agent runtimes. Save ~77%-99.9% SSD space (up to 500x ratio). Keep conversation transcripts 100% intact.

---

## ⚡ Key Features

- **77%-99.9% Disk Space Savings**: Compresses `.log`, `.out`, `.txt`, `.trace` files into `.zst`, `.xz`, or `.gz` archives.
- **Context-Safe**: Excludes `transcript.jsonl` files. Zero memory loss for AI agents.
- **Process Lock Safety**: Checks kernel locks via `fuser -s` (Linux/WSL), `lsof` (macOS), or `[System.IO.File]::Open` (Windows 11). Skips open files.
- **In-Flight Guard**: Skips files modified <60 seconds ago (`-mmin +1`).
- **Dry-Run Mode**: Preview space savings without touching files.
- **Core AI Agent Presets**: Auto-targets Antigravity, Gemini CLI, Cursor, Claude Code, Ollama, Windsurf, Codex, and LM Studio.

---

## 📊 Performance Benchmark

| Metric | Raw Logs | With `zlog` | Storage Saved |
| :--- | :--- | :--- | :--- |
| **Compression Ratio** | 1.0x | **Up to 500x (.zst / .gz)** | **77%-99.9% SSD Space Saved** |
| **Monthly Footprint** | ~9.0 GB | **~2.07 GB** | **~6.93 GB / Month Saved** |
| **Yearly Footprint** | ~108 GB | **~24.8 GB** | **~83.2 GB / Year Saved** |

---

## 🚀 Installation

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/sebin-gg/zlog/main/install.sh | bash
```

### `skills.sh` CLI

```bash
npx skills add sebin-gg/zlog
```

---

## 🏗️ Architecture

```mermaid
graph TD
    A["User / Wrap-up Trigger"] --> B{"Scan AI Agent Paths"}
    B --> C["~/.gemini, ~/.config/Cursor, ~/.ollama, ~/.claude, etc."]
    C --> D{"Process Lock Check"}
    D -- "fuser / lsof detects active PID" --> E["Skip File - In-Flight Safety"]
    D -- "No active process lock" --> F{"File Filters"}
    F -- "*.jsonl / SKILL.md / README* / <10KB" --> G["Skip File - Protected"]
    F -- "*.log / *.out / *.txt / *.trace" --> H["Compress to .zst / .gz"]
    H --> I["Report Total Disk Space Saved via du"]
```

---

## 🌐 Supported AI Agent Runtimes

| # | AI Agent / IDE | Default Path | OS Support |
| :---: | :--- | :--- | :--- |
| 1 | **Antigravity CLI** | `~/.gemini/antigravity-cli/logs/` | Linux, macOS, Windows 11 |
| 2 | **Gemini CLI** | `~/.gemini/` | Linux, macOS, Windows 11 |
| 3 | **Cursor IDE** | `~/.config/Cursor/` | Linux, macOS, Windows 11 |
| 4 | **Cursor (Legacy)** | `~/.cursor/` | Linux, macOS, Windows 11 |
| 5 | **Claude Code** | `~/.claude/` | Linux, macOS, Windows 11 |
| 6 | **Claude Code Config** | `~/.config/claude-code/` | Linux, macOS, Windows 11 |
| 7 | **Ollama** | `~/.ollama/` | Linux, macOS, Windows 11 |
| 8 | **Windsurf** | `~/.windsurf/` | Linux, macOS, Windows 11 |
| 9 | **Codex CLI** | `~/.codex/` | Linux, macOS, Windows 11 |
| 10 | **LM Studio** | `~/.cache/lm-studio/` | Linux, macOS, Windows 11 |

---

## 💻 CLI Snippets

### POSIX Shell (Linux, macOS, WSL, Git Bash)

```bash
for d in ~/.gemini ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.windsurf ~/.codex ~/.cache/lm-studio; do
  if [ -d "$d" ]; then
    find -L "$d" \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -empty -type f -delete 2>/dev/null || true
    find -L "$d" \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -exec sh -c 'for f; do (command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null) || (command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1) || (command -v zstd >/dev/null 2>&1 && zstd -15 -q --rm "$f") || (command -v xz >/dev/null 2>&1 && xz -9 "$f") || gzip -f "$f"; done' sh {} + 2>/dev/null || true
  fi
done
dirs=(); for d in ~/.gemini ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.windsurf ~/.codex ~/.cache/lm-studio; do [ -d "$d" ] && [ ! -L "$d" ] && dirs+=("$d"); done; [ ${#dirs[@]} -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
```

### Windows 11 Native Compression (PowerShell - Process Lock Safe)

```powershell
Get-ChildItem -Path "$env:USERPROFILE\.gemini","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:USERPROFILE\.claude" -Recurse -Include *.log,*.out,*.txt,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 10KB -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) -and (try { $s = [System.IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $s.Close(); $true } catch { $false }) } | ForEach-Object { tar.exe -czf "$($_.FullName).gz" "$($_.FullName)"; Remove-Item $_.FullName }
```

---

## ❓ FAQ

- **Break chat history?** No. `transcript.jsonl` files excluded.
- **Process safety?** `fuser -s` / `lsof` / `System.IO.File::Open` checks kernel locks. Open files skipped.
- **Read compressed logs?** `zstdcat file.log.zst` or `zcat file.log.gz` to view, `zstdgrep "error" file.log.zst` or `zgrep "error" file.log.gz` to search.

---

## 📄 License

[MIT](LICENSE) © 2026 Sebin Mathew
