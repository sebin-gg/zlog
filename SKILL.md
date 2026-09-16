---
name: zlog
description: Compresses AI agent session logs (`.log`, `.out`, `.txt`, `.trace` over 10KiB) to `.zst`, `.xz`, `.gz`, or `.tar.gz` (Windows), saving 77%-99.9% disk space. Purges empty 0-byte logs, skips locked and in-flight files, safe for concurrent multi-instance running agents. Use when wrapping up, ending sessions, or asked to clean logs, zlog, pack logs, or find new AI agents.
license: MIT
compatibility: Linux, macOS, WSL, Windows 11 (Bash, Zsh, Git Bash, PowerShell)
allowed-tools: Bash(*) Read Write
metadata:
  version: "1.3.0"
  registry: skills.sh
---

# Zlog Multi-Instance Storage Optimizer

Compress background tool logs across AI agents (~77%-99.9% space saved / fast zstd -15 fallback). Purge 0-byte empty logs. Keep `transcript.jsonl` intact. Safe for concurrent running agents. Skip tiny logs (<10KiB) and text docs. Handle symlinks cleanly. Reports per-run savings + total summary.

## Execution Intents

- **Standard Cleanup**: Triggered on "zlog", "compress logs", "clean up chat logs", "pack logs", or session wrap-up.
- **Dry-Run Preview**: Triggered on "preview zlog", "dry run", "test log cleanup".
- **Deep Scan**: Triggered on "find new AI agents", "scan disk for hidden AI logs".

## Safety & Invariant Protection

- **Process Locks**: Query `fuser -s "$f"` (Linux/WSL), `lsof "$f"` (macOS), or `[System.IO.File]::Open(..., 'None')` (Windows 11 PowerShell). Skip file if active process lock exists.
- **In-Flight Window**: Skip files modified <60 seconds ago (`-mmin +1`).
- **Protected Files**: Exclude `*.jsonl`, `SKILL.md`, `README*`, `LICENSE*`, and files <= 10KiB.
- **Junk-Dir Pruning**: Every scan shares one canonical prune list — `node_modules`, `Caches`, `Cache`, `Code Cache`, `blob_storage`, `GPUCache`, `DawnGraphiteCache`, `DawnWebGPUCache`, `.git` — defined once per snippet as `prune=(...)` and passed as `"${prune[@]}"`. Pruned-dir count is reported.
- **Depth Bound**: Deep scan capped at `-maxdepth 12` (Antigravity nests ~8 levels deep) — bounded runtime, belt-and-suspenders with pruning.
- **Hardlink Aliases**: Mirror dirs sharing the same inode (e.g. Antigravity `antigravity-*` copies) may list one file several times; each name compresses independently — harmless and self-healing.

## Commands

### Standard Compression & Empty Log Purge (Linux, macOS, WSL, Git Bash)

```bash
raw=0; saved=0; count=0
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
for d in ~/.gemini ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.lm-studio; do
  [ -d "$d" ] || continue
  find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -empty -exec rm -f {} + \) 2>/dev/null || true
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    (command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null) || (command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1) || (command -v zstd >/dev/null 2>&1 && zstd -15 -q --rm "$f") || (command -v xz >/dev/null 2>&1 && xz -9 "$f") || gzip -f "$f"
    for c in zst xz gz; do
      [ -f "$f.$c" ] || continue
      newsize=$(stat -c%s "$f.$c" 2>/dev/null || stat -f%z "$f.$c" 2>/dev/null) || newsize=0
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
  echo "[zlog] Compressed $count files: $raw_h -> $comp_h (saved $saved_h, $(( saved * 100 / raw ))% smaller)"
fi
dirs=(); for d in ~/.gemini ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.lm-studio; do [ -d "$d" ] && [ ! -L "$d" ] && dirs+=("$d"); done; [ ${#dirs[@]} -gt 0 ] && du -ch "${dirs[@]}" 2>/dev/null | tail -n 1 || true
```

### Dry-Run Mode (Preview Without Modifying Files)

```bash
total=0; count=0
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
for d in ~/.gemini ~/.config/Cursor ~/.cursor ~/.ollama ~/.claude ~/.config/claude-code ~/.windsurf ~/.codex ~/.cache/lm-studio ~/.lm-studio; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do
    [ -z "$f" ] && continue
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
    total=$((total + size)); count=$((count + 1))
    hum=$(echo "$size" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
    echo "[DRY-RUN] Would compress: $f ($hum)"
  done < <(find -L "$d" \( -type d \( "${prune[@]}" \) -prune \) -o \( -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 \) 2>/dev/null)
done
saved=$((total * 77 / 100)); comp=$((total - saved))
total_hum=$(echo "$total" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
comp_hum=$(echo "$comp" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
echo ""
echo "[DRY-RUN] Total: $count files, $total_hum raw -> ~$comp_hum compressed (est. 77% savings)"
```

### Windows 11 Native Compression (PowerShell - Process Lock Safe)

```powershell
Get-ChildItem -Path "$env:USERPROFILE\.gemini","$env:USERPROFILE\.cursor","$env:USERPROFILE\.ollama","$env:USERPROFILE\.claude","$env:USERPROFILE\.config\claude-code","$env:USERPROFILE\.windsurf","$env:USERPROFILE\.codex","$env:USERPROFILE\.cache\lm-studio" -Recurse -Include *.log,*.out,*.txt,*.trace -Exclude *.gz,*.zst,*.xz,*.jsonl,SKILL.md,README*,LICENSE* -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 10KB -and $_.LastWriteTime -lt (Get-Date).AddMinutes(-1) -and (try { $s = [System.IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $s.Close(); $true } catch { $false }) } | ForEach-Object { tar.exe -czf "$($_.FullName).tar.gz" -C $_.DirectoryName $_.Name; if ($LASTEXITCODE -eq 0 -and (Test-Path "$($_.FullName).tar.gz")) { Remove-Item $_.FullName } }
```

### Deep Scan (On user request: "find new AI agents" / "scan disk")

```bash
prune=(-name node_modules -o -name Caches -o -name Cache -o -name "Code Cache" -o -name blob_storage -o -name GPUCache -o -name DawnGraphiteCache -o -name DawnWebGPUCache -o -name .git)
pruned=$(find -L ~ -maxdepth 12 \( -type d \( "${prune[@]}" \) -prune \) -print 2>/dev/null | wc -l)
raw=0; saved=0; count=0
while IFS= read -r -d '' f; do
  size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null) || size=0
  (command -v fuser >/dev/null 2>&1 && fuser -s "$f" 2>/dev/null) || (command -v lsof >/dev/null 2>&1 && lsof "$f" >/dev/null 2>&1) || (command -v zstd >/dev/null 2>&1 && zstd -15 -q --rm "$f") || (command -v xz >/dev/null 2>&1 && xz -9 "$f") || gzip -f "$f"
  for c in zst xz gz; do
    [ -f "$f.$c" ] || continue
    newsize=$(stat -c%s "$f.$c" 2>/dev/null || stat -f%z "$f.$c" 2>/dev/null) || newsize=0
    raw=$((raw + size)); saved=$((saved + size - newsize)); count=$((count + 1))
    break
  done
done < <(find -L ~ -maxdepth 12 \( -type d \( "${prune[@]}" \) -prune \) -o \( -path "*/.gemini/*" -o -path "*/.config/Cursor/*" -o -path "*/.cursor/*" -o -path "*/.claude/*" -o -path "*/.config/claude-code/*" -o -path "*/.ollama/*" -o -path "*/.windsurf/*" -o -path "*/.codex/*" -o -path "*/.cache/lm-studio/*" -o -path "*/.lm-studio/*" \) -type f \( -name "*.log" -o -name "*.out" -o -name "*.trace" -o -name "*.txt" \) -not -name "*.gz" -not -name "*.zst" -not -name "*.xz" -not -name "*.jsonl" -not -name "SKILL.md" -not -iname "README*" -not -iname "LICENSE*" -size +10k -mmin +1 -print0 2>/dev/null)
if [ "$count" -gt 0 ]; then
  comp=$((raw - saved))
  raw_h=$(echo "$raw" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  comp_h=$(echo "$comp" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  saved_h=$(echo "$saved" | awk '{if($1>=1073741824)printf "%.1fG",$1/1073741824;else if($1>=1048576)printf "%.1fM",$1/1048576;else if($1>=1024)printf "%.1fK",$1/1024;else printf "%dB",$1}')
  echo "[zlog] Deep scan: $count files, $raw_h -> $comp_h (saved $saved_h, $(( saved * 100 / raw ))% smaller)"
else
  echo "[zlog] Deep scan: no compressible files found"
fi
echo "[zlog] Pruned $pruned junk/cache dirs (maxdepth 12)"
```

## Helpers

- **Read `.zst` / `.gz`**: `zstdcat file.log.zst` or `zcat file.log.gz`
- **Read Windows `.tar.gz`**: `tar -xzf file.log.tar.gz` (extracts original log back)
- **Decompress**: `zstd -d file.log.zst` or `gzip -d file.log.gz`
- **Search**: `zstdgrep "pattern" file.log.zst` or `zgrep "pattern" file.log.gz`
