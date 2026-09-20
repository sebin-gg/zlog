# zlog agent-path registry

Machine-readable path knowledge. Scripts embed the same roots; this file
records what each root is, when it was verified, and what is protected.

Columns: Agent | OS | Root | Purpose | Protected | Verified | Source

| Agent | OS | Root | Purpose | Protected | Verified | Source |
|---|---|---|---|---|---|---|
| Claude Code | Linux/macOS | `~/.claude` | session/tool logs | `transcript.*`, configs | 2026-09-20 | repo fixture (Linux paths); macOS layout same rel path |
| Claude Code Config | Linux/macOS | `~/.config/claude-code` | agent config + logs | config files | 2026-09-20 | vendor docs (paths only) |
| Cursor IDE | Linux | `~/.config/Cursor` | IDE + agent logs | `*.jsonl`, user data | 2026-09-20 | vendor docs (paths only) |
| Cursor IDE | macOS | `~/Library/Application Support/Cursor` | IDE + agent logs | same | 2026-09-20 | vendor docs (paths only) |
| Cursor IDE | Windows | `%APPDATA%\Cursor` | IDE + agent logs (`logs\…`) | same | 2026-09-20 | verified on Win11 host (`logs\20260803T…` present) |
| Cursor (Legacy) | any | `~/.cursor` | legacy logs | same | 2026-09-20 | verified on Win11 host (60k files) |
| Gemini CLI | Linux/macOS | `~/.gemini` | CLI logs, history | `history/*`, `config/*` | 2026-09-20 | vendor docs (paths only) |
| Gemini Antigravity | any | `~/.gemini/antigravity/` | agent brain/tasks (`*.log`) | task DBs | 2026-09-20 | verified on Win11 host (`brain\…\task-*.log`) |
| Gemini Antigravity CLI | any | `~/.gemini/antigravity-cli/logs/` | CLI server logs | — | 2026-09-20 | verified on Win11 host (dir exists) |
| Ollama | Linux/macOS | `~/.ollama` | model server data | models (never compressed: no `.log` match) | 2026-09-20 | vendor docs (paths only) |
| Ollama | Windows | `%LOCALAPPDATA%\Ollama` | app/server/upgrade logs | installers | 2026-09-20 | verified on Win11 host (dir exists) |
| Windsurf | Linux | `~/.windsurf`, `~/.config/Windsurf` | IDE + agent logs | user data | 2026-09-20 | vendor docs (paths only) |
| Windsurf | macOS | `~/Library/Application Support/Windsurf` | IDE + agent logs | same | 2026-09-20 | vendor docs (paths only) |
| Windsurf | Windows | `%APPDATA%\Windsurf` | IDE + agent logs | same | 2026-09-20 | vendor docs (paths only) |
| Codex CLI | any | `~/.codex` | sandbox logs (`.sandbox/*.log`) | `sqlite/` live DBs (explicitly excluded) | 2026-09-20 | verified on Win11 host (`.sandbox/*.log` + `sqlite/logs_2.sqlite` 32MB) |
| LM Studio | any | `~/.cache/lm-studio` | older layout logs | models/caches | 2026-09-20 | legacy layout, kept for coverage |
| LM Studio | any | `~/.lmstudio` | current layout (`server-logs`, `bin`) | models, conversations | 2026-09-20 | LM Studio docs (`~/.lmstudio/bin`, `server-logs`) |
| Aider | any | `~/.aider` | chat logs | `*.md` history (no `.log` match) | 2026-09-20 | vendor docs (paths only) |

Notes:

- "verified on Win11 host" means the directory layout was listed on a real
  Windows 11 machine on 2026-09-20. "vendor docs (paths only)" means the
  path spelling was checked against vendor documentation without a live host.
- Linux service paths (e.g. `/usr/share/ollama`) stay out of scope
  (root-owned, no sudo).
- Git Bash on Windows resolves `$HOME` to `%USERPROFILE%`, so
  `$HOME/AppData/Local/Ollama` covers the Ollama Windows path there too.
