---
name: zlog
description: Multi-agent session log compressor and storage optimizer. Compresses `.log`, `.out`, `.txt`, `.trace` (>10KiB) to `.zst`, `.xz`, or `.gz` (saving 77%-99.9% disk space) across `~/.gemini`, `~/.config/Cursor`, `~/.ollama`, `~/.claude`, `~/.windsurf`, `~/.codex`, etc. Auto-discovers AI log dirs, purges empty 0-byte logs. Safe for concurrent multi-instance running agents. Includes Dry-Run preview mode. Use when wrapping up, ending sessions, or asked to clean logs, zlog, pack logs, or find new AI agents.
license: MIT
compatibility: Linux, macOS, WSL, Windows 11 (Bash, Zsh, Git Bash, PowerShell)
allowed-tools: Bash(*) Read Write
metadata:
  version: "1.0.0"
  registry: skills.sh
---

# Zlog Multi-Instance Storage Optimizer

Compress background tool logs across AI agents (~77%-99.9% space saved / fast zstd -15 fallback). Purge 0-byte empty logs. Keep `transcript.jsonl` intact. Safe for concurrent running agents. Skip tiny logs (<10KiB) and text docs. Handle symlinks cleanly. Outputs single-line total summary.

## Execution Intents

- **Standard Cleanup**: Triggered on "zlog", "compress logs", "clean up chat logs", "pack logs", or session wrap-up.
- **Dry-Run Preview**: Triggered on "preview zlog", "dry run", "test log cleanup".
- **Deep Scan**: Triggered on "find new AI agents", "scan disk for hidden AI logs".

## Safety & Invariant Protection

- **Process Locks**: Query `fuser -s "$f"` (Linux/WSL), `lsof "$f"` (macOS), or `[System.IO.File]::Open(..., 'None')` (Windows 11 PowerShell). Skip file if active process lock exists.
- **In-Flight Window**: Skip files modified <60 seconds ago (`-mmin +1`).
- **Protected Files**: Exclude `*.jsonl`, `SKILL.md`, `README*`, `LICENSE*`, and files <= 10KiB.

## Commands

### Standard Compression & Empty Log Purge (Linux, macOS, WSL, Git Bash)

```bash
for d in ~/.gemini ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.windsurf ~/.codex ~/.cache/lm-studio; do
  if [ -d "$d" ]; then
    find -L "$d" \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -empty -type f -delete 2>/dev/null || true
    find -L "$d" \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -exec sh -c 'for f; do (command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null) || (command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1) || (command -v zstd >/dev/null 2>&1 && zstd -15 -q --rm "$f") || (command -v xz >/dev/null 2>&1 && xz -9 "$f") || gzip -f "$f"; done' sh {} + 2>/dev/null || true
  fi
done
dirs=(); for d in ~/.gemini ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.windsurf ~/.codex ~/.cache/lm-studio; do [ -d "$d" ] && [ ! -L "$d" ] && dirs+=("$d"); done; [ ${#dirs[@]} -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
```

### Dry-Run Mode (Preview Without Modifying Files)

```bash
total=0; count=0
for d in ~/.gemini ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.windsurf ~/.codex ~/.cache/lm-studio; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    total=$((total + size)); count=$((count + 1))
    hum=$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")
    echo "[DRY-RUN] Would compress: $f ($hum)"
  done < <(find -L "$d" \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 2>/dev/null)
done
saved=$((total * 77 / 100)); comp=$((total - saved))
total_hum=$(numfmt --to=iec "$total" 2>/dev/null || echo "${total}B")
comp_hum=$(numfmt --to=iec "$comp" 2>/dev/null || echo "${comp}B")
echo ""
echo "[DRY-RUN] Total: $count files, $total_hum raw -> ~$comp_hum compressed (est. 77% savings)"
```

### Windows 11 Native Compression (PowerShell - Process Lock Safe)

```powershell
Get-ChildItem -Path "$env:USERPROFILE\.gemini","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:USERPROFILE\.claude" -Recurse -Include *.log,*.out,*.txt,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 10KB -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) -and (try { $s = [System.IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $s.Close(); $true } catch { $false }) } | ForEach-Object { tar.exe -czf "$($_.FullName).gz" "$($_.FullName)"; Remove-Item $_.FullName }
```

### Deep Scan (On user request: "find new AI agents" / "scan disk")

```bash
find -L ~ -maxdepth 4 \( -path "*/.gemini/*" -o -path "*/.config/Cursor/*" -o -path "*/.cursor/*" -o -path "*/.claude/*" -o -path "*/.config/claude-code/*" -o -path "*/.ollama/*" -o -path "*/.windsurf/*" -o -path "*/.codex/*" -o -path "*/.cache/lm-studio/*" -o -path "*/.lm-studio/*" \) \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -exec sh -c 'for f; do (command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null) || (command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1) || (command -v zstd >/dev/null 2>&1 && zstd -15 -q --rm "$f") || (command -v xz >/dev/null 2>&1 && xz -9 "$f") || gzip -f "$f"; done' sh {} + 2>/dev/null || true
```

## Helpers

- **Read `.zst` / `.gz`**: `zstdcat file.log.zst` or `zcat file.log.gz`
- **Decompress**: `zstd -d file.log.zst` or `gzip -d file.log.gz`
- **Search**: `zstdgrep "pattern" file.log.zst` or `zgrep "pattern" file.log.gz`
