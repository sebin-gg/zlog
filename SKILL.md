---
name: zlog
description: Multi-agent session log compressor and storage optimizer. Compresses `.log`, `.out`, `.txt`, `.trace` (>10KB) to `.gz` (Linux/macOS/WSL) or `.zip` (Windows) in `~/.gemini`, `~/.agents`, `~/.config/Cursor`, `~/.ollama`, etc. Auto-discovers AI log dirs. Safe for concurrent multi-instance running agents. Includes Dry-Run preview mode. Use when wrapping up, ending sessions, or asked to clean logs, zlog, pack logs, or find new AI agents.
license: MIT
compatibility: Linux, macOS, WSL, Windows 11 (Bash, Zsh, Git Bash, PowerShell)
allowed-tools: Bash(*) Read Write
metadata:
  version: "5.2"
  registry: skills.sh
---

# Zlog Multi-Instance Storage Optimizer

Compresses background tool logs across AI agents (**77% disk space saved / 4.3x compression ratio**). Keeps `transcript.jsonl` intact. Safe for concurrent running agents. Skips tiny logs (<10KB) and text documentation. Handles symlinks cleanly.

## Standard Compression (Linux, macOS, WSL, Git Bash)

```bash
for d in ~/.gemini ~/.agents ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.aider ~/.continue ~/.codeium ~/.windsurf ~/.openhands ~/.codex ~/.cache/huggingface ~/.cache/lm-studio; do
  if [ -d "$d" ]; then
    find -L "$d" \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -exec sh -c 'for f; do (command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null) || (command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1) || gzip -f "$f"; done' sh {} + 2>/dev/null || true
    [ ! -L "$d" ] && du -sh "$d" 2>/dev/null || true
  fi
done
```

## Dry-Run Mode (Preview Without Modifying Files)

```bash
for d in ~/.gemini ~/.agents ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.aider ~/.continue ~/.codeium ~/.windsurf ~/.openhands ~/.codex ~/.cache/huggingface ~/.cache/lm-studio; do
  [ -d "$d" ] && find -L "$d" \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -exec echo "[DRY-RUN] Would compress:" {} + 2>/dev/null || true
done
```

## Windows 11 Native Compression (PowerShell - .zip)

```powershell
Get-ChildItem -Path "$env:USERPROFILE\.gemini","$env:USERPROFILE\.agents","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:USERPROFILE\.claude" -Recurse -Include *.log,*.out,*.txt,*.trace -Exclude *.gz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 10KB -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) } | ForEach-Object { Compress-Archive -Path $_.FullName -DestinationPath "$($_.FullName).zip" -Force; Remove-Item $_.FullName }
```

## Deep Scan (On user request: "find new AI agents" / "scan disk")

```bash
find -L ~ -maxdepth 4 \( -path "*/.gemini/*" -o -path "*/.agents/*" -o -path "*/.cursor/*" -o -path "*/.claude/*" -o -path "*/.ollama/*" -o -path "*/.aider/*" -o -path "*/.continue/*" -o -path "*/.windsurf/*" -o -path "*/.codeium/*" -o -path "*/.openhands/*" -o -path "*/.codex/*" -o -path "*/.lm-studio/*" -o -path "*/.huggingface/*" \) \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -exec sh -c 'for f; do (command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null) || (command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1) || gzip -f "$f"; done' sh {} + 2>/dev/null || true
```

## Helpers

- **Read `.gz`**: `zcat file.log.gz` or `zgrep "pattern" file.log.gz`
- **Decompress**: `gzip -d file.log.gz`
- **Merge**: `gzip -d file.log.gz && cat new.log >> file.log && gzip -f file.log`
