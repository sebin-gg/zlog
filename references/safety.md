# zlog safety model

Best-effort protection for concurrent agents — not a guarantee against
races. Every destructive action passes one shared pipeline:

```text
candidate
  → protected? (Class B → skip)
  → junk location? (Class C → skip)
  → recent? (<60s, or --older-than window → skip)
  → locked by a live process? (fuser/lsof/System.IO.File → skip)
  → empty? (purge path only → delete)
  → compress to temp file
  → exit status ok? (no → drop temp, FAILED)
  → integrity test ok? (zstd -t / xz -t / gzip -t, no → drop temp, FAILED)
  → smaller than source? (no → drop temp, NOT_BENEFICIAL)
  → atomic rename to final archive name
  → delete source
```

## Data classes

- **Class A — safe candidates**: `*.log`, `*.out`, `*.trace`, only when
  every rule above passes.
- **Class B — protected (never touch)**: `*.jsonl`, `transcript.*`,
  `conversation.*`, `history.*`, `*.sqlite*`, `*.db`, `*.wal`, `*.shm`,
  configs, `SKILL.md`, `README*`, `LICENSE*`, already-compressed
  (`*.gz`, `*.zst`, `*.xz`), files ≤10KiB (noise, not worth it).
- **Class C — cache/junk locations (never descend)**: `node_modules`,
  `Caches`, `Cache`, `Code Cache`, `blob_storage`, `GPUCache`,
  `DawnGraphiteCache`, `DawnWebGPUCache`, `.git`.
- **Class D — unknown**: anything else is ignored by default. An unknown
  directory never becomes a compression target merely because its path
  looks AI-related.

## Symlink policy

POSIX scans use non-dereferencing traversal (no `-L`): symlinked
directories are never descended into, symlinked files never match
`-type f`. Scans cannot escape the listed roots via symlink. Verified by
the symlink-escape fixture in `tests/`.

## Known limits

- Lock checks need `fuser` (Linux/WSL) or `lsof` (macOS); without either,
  only the age window protects. Prefer idle periods.
- Hardlinked files (same inode, two names) compress independently — valid
  but duplicated output, reported normally.
- `tar` on Windows archives one file per `.tar.gz`; restore refuses
  multi-entry archives.
- Deep scan bounds depth (`-maxdepth 12`), not total work; it walks known
  agent locations under `$HOME`, never the whole disk blindly.
